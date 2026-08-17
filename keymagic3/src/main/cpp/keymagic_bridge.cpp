#include "keymagic_bridge.h"

#include <cstdint>
#include <cstdio>
#include <limits>
#include <new>
#include <string>
#include <vector>

#define LOG_DOMAIN 0x4B4D
#define LOG_TAG "KeyMagicNative"

#include <hilog/log.h>

#include "keymagic_ffi.h"

namespace {

constexpr size_t kCreateEngineArgCount = 0;
constexpr size_t kDestroyEngineArgCount = 1;
constexpr size_t kLoadKeyboardMinimumArgCount = 2;
constexpr size_t kLoadKeyboardMaximumArgCount = 3;
constexpr size_t kProcessKeyArgCount = 7;
constexpr size_t kResetEngineArgCount = 1;
constexpr size_t kGetCompositionArgCount = 1;
constexpr size_t kSetCompositionArgCount = 2;

struct NativeEngine {
    EngineHandle* handle;
    uint64_t wrapper_id;
    uint64_t engine_id;
    std::string runtime_keyboard_id;
};

uint64_t g_next_wrapper_id = 1;
uint64_t g_next_engine_id = 1;

uint64_t AllocateWrapperId()
{
    return g_next_wrapper_id++;
}

uint64_t AllocateEngineId()
{
    // NAPI calls for this module are serialized on its ArkTS thread. A
    // monotonically increasing ID is sufficient to prove which active native
    // handle processes each physical key without exposing raw pointers.
    return g_next_engine_id++;
}

std::string Fnv1a64(const uint8_t* data, size_t length)
{
    constexpr uint64_t kOffsetBasis = 14695981039346656037ULL;
    constexpr uint64_t kPrime = 1099511628211ULL;
    constexpr char kHex[] = "0123456789ABCDEF";

    uint64_t hash = kOffsetBasis;
    for (size_t index = 0; index < length; ++index) {
        hash ^= static_cast<uint64_t>(data[index]);
        hash *= kPrime;
    }

    std::string text = "0x";
    text.reserve(18);
    for (int shift = 60; shift >= 0; shift -= 4) {
        text.push_back(kHex[(hash >> shift) & 0x0FULL]);
    }
    return text;
}

std::string NativeEngineDescription(const NativeEngine& engine)
{
    return "wrapperId=" + std::to_string(engine.wrapper_id) +
        " engineId=" + std::to_string(engine.engine_id) +
        " runtimeKeyboardId=" +
        (engine.runtime_keyboard_id.empty() ? "<none>" : engine.runtime_keyboard_id);
}

void FreeProcessOutput(ProcessKeyOutput* output);

std::string Utf8CodePoints(const char* text)
{
    if (text == nullptr || *text == '\0') {
        return "<empty>";
    }

    const auto* bytes = reinterpret_cast<const uint8_t*>(text);
    std::string result;
    for (size_t index = 0; bytes[index] != 0;) {
        uint32_t codepoint = 0xFFFDU;
        size_t width = 1;
        const uint8_t first = bytes[index];
        if (first <= 0x7FU) {
            codepoint = first;
        } else if ((first & 0xE0U) == 0xC0U && (bytes[index + 1] & 0xC0U) == 0x80U) {
            codepoint = (static_cast<uint32_t>(first & 0x1FU) << 6U) |
                static_cast<uint32_t>(bytes[index + 1] & 0x3FU);
            width = 2;
        } else if ((first & 0xF0U) == 0xE0U && (bytes[index + 1] & 0xC0U) == 0x80U &&
            (bytes[index + 2] & 0xC0U) == 0x80U) {
            codepoint = (static_cast<uint32_t>(first & 0x0FU) << 12U) |
                (static_cast<uint32_t>(bytes[index + 1] & 0x3FU) << 6U) |
                static_cast<uint32_t>(bytes[index + 2] & 0x3FU);
            width = 3;
        } else if ((first & 0xF8U) == 0xF0U && (bytes[index + 1] & 0xC0U) == 0x80U &&
            (bytes[index + 2] & 0xC0U) == 0x80U && (bytes[index + 3] & 0xC0U) == 0x80U) {
            codepoint = (static_cast<uint32_t>(first & 0x07U) << 18U) |
                (static_cast<uint32_t>(bytes[index + 1] & 0x3FU) << 12U) |
                (static_cast<uint32_t>(bytes[index + 2] & 0x3FU) << 6U) |
                static_cast<uint32_t>(bytes[index + 3] & 0x3FU);
            width = 4;
        }

        char rendered[12] = {0};
        std::snprintf(rendered, sizeof(rendered), "U+%04X", codepoint);
        if (!result.empty()) {
            result.push_back(' ');
        }
        result += rendered;
        index += width;
    }
    return result;
}

bool LogKeyboardFingerprint(
    EngineHandle* handle,
    uint64_t wrapper_id,
    uint64_t engine_id,
    const std::string& requested_subtype_id,
    const std::string& byte_hash)
{
    // Host-core validation establishes Shift+4 as a one-step, all-four-layout
    // discriminator. Run the identical KeyMagic input on the newly loaded
    // handle before it can become live, then reset so this probe cannot alter
    // the user's composition.
    constexpr int kProbeKeyCode = 20;
    constexpr char kProbeCharacter = '4';
    ProcessKeyOutput output = {0, nullptr, 0, nullptr, 0};
    const KeyMagicResult status = keymagic_engine_process_key(
        handle, kProbeKeyCode, kProbeCharacter, 1, 0, 0, 0, &output);
    const std::string text_codepoints = Utf8CodePoints(output.text);
    const std::string composition_codepoints = Utf8CodePoints(output.composing_text);
    FreeProcessOutput(&output);
    const KeyMagicResult reset_status = keymagic_engine_reset(handle);
    const bool success = status == KeyMagicResult_Success && reset_status == KeyMagicResult_Success;
    OH_LOG_INFO(LOG_APP, "%{public}s",
        ("NATIVE KEYBOARD FINGERPRINT wrapperId=" + std::to_string(wrapper_id) +
            " engineId=" + std::to_string(engine_id) +
            " requestedSubtypeId=" + requested_subtype_id +
            " km2Hash=" + byte_hash +
            " probe=Shift+4(keyCode=20,char=4,shift=true)" +
            " action=" + std::to_string(output.action_type) +
            " deleteCount=" + std::to_string(output.delete_count) +
            " processed=" + std::to_string(output.is_processed) +
            " resultTextCodepoints=" + text_codepoints +
            " resultCompositionCodepoints=" + composition_codepoints +
            " resetStatus=" + std::to_string(static_cast<int>(reset_status)) +
            " success=" + (success ? "true" : "false")).c_str());
    return success;
}

void ThrowTypeError(napi_env env, const char* message)
{
    napi_throw_type_error(env, nullptr, message);
}

void ThrowError(napi_env env, const char* message)
{
    napi_throw_error(env, nullptr, message);
}

napi_value Undefined(napi_env env)
{
    napi_value value = nullptr;
    napi_get_undefined(env, &value);
    return value;
}

bool GetArguments(napi_env env, napi_callback_info info, napi_value* args, size_t* argc, size_t minimum)
{
    if (napi_get_cb_info(env, info, argc, args, nullptr, nullptr) != napi_ok) {
        ThrowError(env, "Unable to read native function arguments.");
        return false;
    }

    if (*argc < minimum) {
        ThrowTypeError(env, "Not enough arguments for KeyMagic native function.");
        return false;
    }

    return true;
}

NativeEngine* GetNativeEngine(napi_env env, napi_value value, bool require_live_handle)
{
    void* data = nullptr;
    if (napi_get_value_external(env, value, &data) != napi_ok || data == nullptr) {
        ThrowTypeError(env, "Expected a KeyMagic engine handle.");
        return nullptr;
    }

    auto* engine = static_cast<NativeEngine*>(data);
    if (require_live_handle && engine->handle == nullptr) {
        ThrowError(env, "The KeyMagic engine has already been destroyed.");
        return nullptr;
    }

    return engine;
}

bool GetBoolean(napi_env env, napi_value value, bool* result, const char* name)
{
    bool boolean_value = false;
    if (napi_get_value_bool(env, value, &boolean_value) != napi_ok) {
        ThrowTypeError(env, name);
        return false;
    }

    *result = boolean_value;
    return true;
}

bool GetInternalKeyCode(napi_env env, napi_value value, int* result)
{
    uint32_t key_code = 0;
    if (napi_get_value_uint32(env, value, &key_code) != napi_ok) {
        ThrowTypeError(env, "keyCode must be an unsigned KeyMagic virtual-key value.");
        return false;
    }

    if (key_code > std::numeric_limits<uint16_t>::max()) {
        ThrowTypeError(env, "keyCode exceeds the KeyMagic virtual-key range.");
        return false;
    }

    *result = static_cast<int>(key_code);
    return true;
}

bool GetAsciiCharacter(napi_env env, napi_value value, char* result)
{
    size_t byte_length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &byte_length) != napi_ok) {
        ThrowTypeError(env, "character must be a string.");
        return false;
    }

    if (byte_length > 1) {
        ThrowTypeError(env, "character must be empty or a single-byte ASCII character.");
        return false;
    }

    if (byte_length == 0) {
        *result = 0;
        return true;
    }

    char buffer[2] = {0, 0};
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, buffer, sizeof(buffer), &copied) != napi_ok || copied != 1) {
        ThrowTypeError(env, "character must be empty or a single-byte ASCII character.");
        return false;
    }

    *result = buffer[0];
    return true;
}

bool GetUtf8String(napi_env env, napi_value value, std::string* result, const char* name)
{
    size_t byte_length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &byte_length) != napi_ok) {
        ThrowTypeError(env, name);
        return false;
    }

    std::vector<char> buffer(byte_length + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &copied) != napi_ok) {
        ThrowTypeError(env, name);
        return false;
    }
    *result = std::string(buffer.data(), copied);
    return true;
}

void FreeProcessOutput(ProcessKeyOutput* output)
{
    if (output->text != nullptr) {
        keymagic_free_string(output->text);
        output->text = nullptr;
    }
    if (output->composing_text != nullptr) {
        keymagic_free_string(output->composing_text);
        output->composing_text = nullptr;
    }
}

bool SetNamedInt32(napi_env env, napi_value object, const char* name, int32_t value)
{
    napi_value property = nullptr;
    return napi_create_int32(env, value, &property) == napi_ok &&
        napi_set_named_property(env, object, name, property) == napi_ok;
}

bool SetNamedBool(napi_env env, napi_value object, const char* name, bool value)
{
    napi_value property = nullptr;
    return napi_get_boolean(env, value, &property) == napi_ok &&
        napi_set_named_property(env, object, name, property) == napi_ok;
}

bool SetNamedString(napi_env env, napi_value object, const char* name, const char* value)
{
    napi_value property = nullptr;
    return napi_create_string_utf8(env, value, NAPI_AUTO_LENGTH, &property) == napi_ok &&
        napi_set_named_property(env, object, name, property) == napi_ok;
}

napi_value CreateStatus(napi_env env, KeyMagicResult status)
{
    napi_value value = nullptr;
    if (napi_create_int32(env, static_cast<int32_t>(status), &value) != napi_ok) {
        ThrowError(env, "Unable to create KeyMagic status value.");
        return nullptr;
    }
    return value;
}

void FinalizeEngine(napi_env /* env */, void* data, void* /* hint */)
{
    auto* engine = static_cast<NativeEngine*>(data);
    if (engine == nullptr) {
        return;
    }

    if (engine->handle != nullptr) {
        keymagic_engine_free(engine->handle);
        engine->handle = nullptr;
        OH_LOG_INFO(LOG_APP, "%{public}s",
            ("NATIVE ENGINE FINALIZE " + NativeEngineDescription(*engine)).c_str());
    }
    delete engine;
}

napi_value CreateEngine(napi_env env, napi_callback_info info)
{
    napi_value args[1] = {nullptr};
    size_t argc = kCreateEngineArgCount;
    if (!GetArguments(env, info, args, &argc, kCreateEngineArgCount)) {
        return nullptr;
    }

    auto* engine = new (std::nothrow) NativeEngine{
        keymagic_engine_new(),
        AllocateWrapperId(),
        AllocateEngineId(),
        "",
    };
    if (engine == nullptr || engine->handle == nullptr) {
        delete engine;
        ThrowError(env, "Unable to create the KeyMagic engine.");
        return nullptr;
    }

    napi_value external = nullptr;
    if (napi_create_external(env, engine, FinalizeEngine, nullptr, &external) != napi_ok) {
        keymagic_engine_free(engine->handle);
        delete engine;
        ThrowError(env, "Unable to create the KeyMagic NAPI engine handle.");
        return nullptr;
    }

    OH_LOG_INFO(LOG_APP, "%{public}s",
        ("NATIVE ENGINE CREATE " + NativeEngineDescription(*engine)).c_str());
    return external;
}

napi_value DestroyEngine(napi_env env, napi_callback_info info)
{
    napi_value args[kDestroyEngineArgCount] = {nullptr};
    size_t argc = kDestroyEngineArgCount;
    if (!GetArguments(env, info, args, &argc, kDestroyEngineArgCount)) {
        return nullptr;
    }

    NativeEngine* engine = GetNativeEngine(env, args[0], false);
    if (engine == nullptr) {
        return nullptr;
    }

    if (engine->handle != nullptr) {
        keymagic_engine_free(engine->handle);
        engine->handle = nullptr;
        OH_LOG_INFO(LOG_APP, "%{public}s",
            ("NATIVE ENGINE DESTROY " + NativeEngineDescription(*engine)).c_str());
    }

    return Undefined(env);
}

napi_value LoadKeyboard(napi_env env, napi_callback_info info)
{
    napi_value args[kLoadKeyboardMaximumArgCount] = {nullptr};
    size_t argc = kLoadKeyboardMaximumArgCount;
    if (!GetArguments(env, info, args, &argc, kLoadKeyboardMinimumArgCount)) {
        return nullptr;
    }

    NativeEngine* engine = GetNativeEngine(env, args[0], true);
    if (engine == nullptr) {
        return nullptr;
    }

    bool is_typed_array = false;
    if (napi_is_typedarray(env, args[1], &is_typed_array) != napi_ok || !is_typed_array) {
        ThrowTypeError(env, "keyboardData must be a Uint8Array.");
        return nullptr;
    }

    napi_typedarray_type array_type = napi_int8_array;
    size_t element_count = 0;
    void* data = nullptr;
    napi_value array_buffer = nullptr;
    size_t byte_offset = 0;
    if (napi_get_typedarray_info(env, args[1], &array_type, &element_count, &data, &array_buffer, &byte_offset) != napi_ok ||
        array_type != napi_uint8_array || data == nullptr || element_count == 0) {
        ThrowTypeError(env, "keyboardData must be a non-empty Uint8Array.");
        return nullptr;
    }

    std::string subtype_id = "<unspecified>";
    if (argc >= kLoadKeyboardMaximumArgCount && !GetUtf8String(env, args[2], &subtype_id, "subtypeId must be a string.")) {
        return nullptr;
    }

    // A new core handle is fully parsed and initialized before replacing the
    // active handle. This keeps the prior running keyboard alive if the new
    // resource fails, and makes the engine that processKey() uses explicit.
    EngineHandle* replacement_handle = keymagic_engine_new();
    const uint64_t replacement_id = AllocateEngineId();
    if (replacement_handle == nullptr) {
        ThrowError(env, "Unable to create replacement KeyMagic engine.");
        return nullptr;
    }

    const std::string byte_hash = Fnv1a64(static_cast<const uint8_t*>(data), element_count);
    OH_LOG_INFO(LOG_APP, "%{public}s",
        ("NATIVE ENGINE CREATE engineId=" + std::to_string(replacement_id) +
            " reason=keyboard-load").c_str());
    const auto status = keymagic_engine_load_keyboard_from_memory(
        replacement_handle,
        static_cast<const uint8_t*>(data),
        element_count);

    if (status != KeyMagicResult_Success) {
        keymagic_engine_free(replacement_handle);
        OH_LOG_ERROR(LOG_APP, "%{public}s",
            ("NATIVE LOAD KEYBOARD engineId=" + std::to_string(replacement_id) +
                " subtypeId=" + subtype_id +
                " byteLength=" + std::to_string(element_count) +
                " km2Hash=fnv1a64:" + byte_hash +
                " success=false").c_str());
        return CreateStatus(env, status);
    }

    if (!LogKeyboardFingerprint(
            replacement_handle,
            engine->wrapper_id,
            replacement_id,
            subtype_id,
            byte_hash)) {
        keymagic_engine_free(replacement_handle);
        ThrowError(env, "Loaded keyboard failed KeyMagic fingerprint/reset validation.");
        return nullptr;
    }

    EngineHandle* old_handle = engine->handle;
    const uint64_t old_engine_id = engine->engine_id;
    engine->handle = replacement_handle;
    engine->engine_id = replacement_id;
    engine->runtime_keyboard_id = subtype_id;
    keymagic_engine_free(old_handle);

    OH_LOG_INFO(LOG_APP, "%{public}s",
        ("NATIVE LOAD KEYBOARD wrapperId=" + std::to_string(engine->wrapper_id) +
            " engineId=" + std::to_string(engine->engine_id) +
            " subtypeId=" + engine->runtime_keyboard_id +
            " byteLength=" + std::to_string(element_count) +
            " km2Hash=fnv1a64:" + byte_hash +
            " success=true").c_str());
    OH_LOG_INFO(LOG_APP, "%{public}s",
        ("NATIVE ENGINE SWAP wrapperId=" + std::to_string(engine->wrapper_id) +
            " oldEngineId=" + std::to_string(old_engine_id) +
            " newEngineId=" + std::to_string(engine->engine_id) +
            " subtypeId=" + engine->runtime_keyboard_id).c_str());
    return CreateStatus(env, status);
}

napi_value ProcessKey(napi_env env, napi_callback_info info)
{
    napi_value args[kProcessKeyArgCount] = {nullptr};
    size_t argc = kProcessKeyArgCount;
    if (!GetArguments(env, info, args, &argc, kProcessKeyArgCount)) {
        return nullptr;
    }

    NativeEngine* engine = GetNativeEngine(env, args[0], true);
    if (engine == nullptr) {
        return nullptr;
    }

    int key_code = 0;
    char character = 0;
    bool shift = false;
    bool ctrl = false;
    bool alt = false;
    bool caps_lock = false;
    if (!GetInternalKeyCode(env, args[1], &key_code) ||
        !GetAsciiCharacter(env, args[2], &character) ||
        !GetBoolean(env, args[3], &shift, "shift must be a boolean.") ||
        !GetBoolean(env, args[4], &ctrl, "ctrl must be a boolean.") ||
        !GetBoolean(env, args[5], &alt, "alt must be a boolean.") ||
        !GetBoolean(env, args[6], &caps_lock, "capsLock must be a boolean.")) {
        return nullptr;
    }

    const char character_text[2] = {character, 0};
    const char* character_for_log = character == 0 ? "<empty>" : character_text;
    OH_LOG_INFO(LOG_APP,
        "PROCESS KEY NATIVE wrapperId=%{public}d engineId=%{public}d subtypeId=%{public}s key_code=%{public}d character=%{public}s character_byte=%{public}d shift=%{public}d ctrl=%{public}d alt=%{public}d caps_lock=%{public}d",
        static_cast<int>(engine->wrapper_id),
        static_cast<int>(engine->engine_id),
        engine->runtime_keyboard_id.empty() ? "<none>" : engine->runtime_keyboard_id.c_str(),
        key_code,
        character_for_log,
        static_cast<int>(static_cast<unsigned char>(character)),
        shift ? 1 : 0,
        ctrl ? 1 : 0,
        alt ? 1 : 0,
        caps_lock ? 1 : 0);

    ProcessKeyOutput output = {0, nullptr, 0, nullptr, 0};
    const auto status = keymagic_engine_process_key(
        engine->handle,
        key_code,
        character,
        shift ? 1 : 0,
        ctrl ? 1 : 0,
        alt ? 1 : 0,
        caps_lock ? 1 : 0,
        &output);

    if (status != KeyMagicResult_Success) {
        FreeProcessOutput(&output);
        OH_LOG_ERROR(LOG_APP, "KeyMagic key processing failed. status=%{public}d", static_cast<int>(status));
        return CreateStatus(env, status);
    }

    napi_value result = nullptr;
    const bool built_result =
        napi_create_object(env, &result) == napi_ok &&
        SetNamedInt32(env, result, "actionType", output.action_type) &&
        SetNamedString(env, result, "text", output.text == nullptr ? "" : output.text) &&
        SetNamedInt32(env, result, "deleteCount", output.delete_count) &&
        SetNamedString(env, result, "composingText", output.composing_text == nullptr ? "" : output.composing_text) &&
        SetNamedBool(env, result, "isProcessed", output.is_processed != 0) &&
        SetNamedInt32(env, result, "engineId", static_cast<int32_t>(engine->engine_id)) &&
        SetNamedString(env, result, "runtimeKeyboardId",
            engine->runtime_keyboard_id.empty() ? "" : engine->runtime_keyboard_id.c_str());

    FreeProcessOutput(&output);
    if (!built_result) {
        ThrowError(env, "Unable to create KeyMagic process-key result.");
        return nullptr;
    }

    OH_LOG_DEBUG(LOG_APP, "Processed KeyMagic key. action=%{public}d deleteCount=%{public}d processed=%{public}d",
        static_cast<int>(output.action_type), static_cast<int>(output.delete_count), static_cast<int>(output.is_processed));
    return result;
}

napi_value ResetEngine(napi_env env, napi_callback_info info)
{
    napi_value args[kResetEngineArgCount] = {nullptr};
    size_t argc = kResetEngineArgCount;
    if (!GetArguments(env, info, args, &argc, kResetEngineArgCount)) {
        return nullptr;
    }

    NativeEngine* engine = GetNativeEngine(env, args[0], true);
    if (engine == nullptr) {
        return nullptr;
    }

    const auto status = keymagic_engine_reset(engine->handle);
    OH_LOG_INFO(LOG_APP, "Reset KeyMagic engine. status=%{public}d", static_cast<int>(status));
    return CreateStatus(env, status);
}

napi_value GetComposition(napi_env env, napi_callback_info info)
{
    napi_value args[kGetCompositionArgCount] = {nullptr};
    size_t argc = kGetCompositionArgCount;
    if (!GetArguments(env, info, args, &argc, kGetCompositionArgCount)) {
        return nullptr;
    }

    NativeEngine* engine = GetNativeEngine(env, args[0], true);
    if (engine == nullptr) {
        return nullptr;
    }

    char* composition = keymagic_engine_get_composition(engine->handle);
    if (composition == nullptr) {
        ThrowError(env, "Unable to read KeyMagic engine composition.");
        return nullptr;
    }

    napi_value result = nullptr;
    const bool created = napi_create_string_utf8(env, composition, NAPI_AUTO_LENGTH, &result) == napi_ok;
    keymagic_free_string(composition);
    if (!created) {
        ThrowError(env, "Unable to create KeyMagic composition result.");
        return nullptr;
    }
    return result;
}

napi_value SetComposition(napi_env env, napi_callback_info info)
{
    napi_value args[kSetCompositionArgCount] = {nullptr};
    size_t argc = kSetCompositionArgCount;
    if (!GetArguments(env, info, args, &argc, kSetCompositionArgCount)) {
        return nullptr;
    }

    NativeEngine* engine = GetNativeEngine(env, args[0], true);
    if (engine == nullptr) {
        return nullptr;
    }

    std::string composition;
    if (!GetUtf8String(env, args[1], &composition, "composition must be a string.")) {
        return nullptr;
    }

    const auto status = keymagic_engine_set_composition(engine->handle, composition.c_str());
    OH_LOG_DEBUG(LOG_APP, "Set KeyMagic engine composition. status=%{public}d length=%{public}d",
        static_cast<int>(status), static_cast<int>(composition.size()));
    return CreateStatus(env, status);
}

}  // namespace

napi_value InitKeyMagicBridge(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"createEngine", nullptr, CreateEngine, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"destroyEngine", nullptr, DestroyEngine, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"loadKeyboard", nullptr, LoadKeyboard, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"processKey", nullptr, ProcessKey, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"resetEngine", nullptr, ResetEngine, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getComposition", nullptr, GetComposition, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setComposition", nullptr, SetComposition, nullptr, nullptr, nullptr, napi_default, nullptr},
    };

    if (napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors) != napi_ok) {
        ThrowError(env, "Unable to register KeyMagic native functions.");
        return nullptr;
    }

    return exports;
}

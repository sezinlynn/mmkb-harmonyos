#ifndef KEYMAGIC_HARMONYOS_FFI_H
#define KEYMAGIC_HARMONYOS_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Declarations for the existing keymagic-core C ABI. Keep this subset in sync
// with keymagic-core/src/ffi.rs; it deliberately does not define a new Rust API.
typedef struct EngineHandle EngineHandle;

typedef enum {
    KeyMagicResult_Success = 0,
    KeyMagicResult_ErrorInvalidHandle = -1,
    KeyMagicResult_ErrorInvalidParameter = -2,
    KeyMagicResult_ErrorEngineFailure = -3,
    KeyMagicResult_ErrorUtf8Conversion = -4,
    KeyMagicResult_ErrorNoKeyboard = -5,
} KeyMagicResult;

typedef struct {
    int action_type;
    char* text;
    int delete_count;
    char* composing_text;
    int is_processed;
} ProcessKeyOutput;

EngineHandle* keymagic_engine_new(void);
void keymagic_engine_free(EngineHandle* handle);

KeyMagicResult keymagic_engine_load_keyboard_from_memory(
    EngineHandle* handle,
    const uint8_t* km2_data,
    size_t data_len);

KeyMagicResult keymagic_engine_process_key(
    EngineHandle* handle,
    int key_code,
    char character,
    int shift,
    int ctrl,
    int alt,
    int caps_lock,
    ProcessKeyOutput* output);

KeyMagicResult keymagic_engine_reset(EngineHandle* handle);
char* keymagic_engine_get_composition(EngineHandle* handle);
KeyMagicResult keymagic_engine_set_composition(EngineHandle* handle, const char* text);
void keymagic_free_string(char* value);

#ifdef __cplusplus
}
#endif

#endif  // KEYMAGIC_HARMONYOS_FFI_H

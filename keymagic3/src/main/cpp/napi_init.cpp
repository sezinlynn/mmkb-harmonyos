#include "napi/native_api.h"

#include "keymagic_bridge.h"

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    return InitKeyMagicBridge(env, exports);
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "keymagic3",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterKeymagic3Module(void)
{
    napi_module_register(&demoModule);
}

# KeyMagic 3 HarmonyOS smoke test

This DevEco project is the Milestone 1 HarmonyOS PC/2in1 smoke test. It embeds the existing `keymagic-core` Rust static library in the generated NAPI library and calls the existing C FFI. It does not register a system IME.

## Prerequisites

- DevEco Studio's OpenHarmony SDK, with the native SDK installed.
- Rust with `cargo` and `rustup` available on `PATH`.
- Rust target `aarch64-unknown-linux-ohos` installed for the selected toolchain.

Set the SDK root to the directory containing `native/`, for example:

```powershell
$env:OHOS_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony'
```

## Build

From the repository root, build the Rust static library before building the HAP:

```powershell
.\keymagic-harmonyos\scripts\build-core-ohos.ps1 -Profile debug
```

Then open `keymagic-harmonyos/` in DevEco Studio and build/deploy the `arm64-v8a` debug target. The CMake project intentionally stops with an actionable error if the required Rust archive is absent.

## Smoke test

1. Tap **Create engine**.
2. Tap **Load bundled .km2**.
3. Send a debug event, or focus the keyboard-capture area and press a physical key.
4. Inspect the key codes, modifiers, action, text, delete count, composition, and processed flag.
5. Tap **Reset engine**, then **Destroy engine** and create it again.

The page reports actions only. It does not edit another application or provide virtual keyboard behavior.

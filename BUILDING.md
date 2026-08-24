# Building mmKB for HarmonyOS

## Requirements

- DevEco Studio with the OpenHarmony SDK and native toolchain installed.
- This project currently declares `modelVersion` / `targetSdkVersion` `6.1.1(24)` and `compatibleSdkVersion` `6.0.0(20)`.
- Rust and `rustup` on `PATH`.
- Rust target `aarch64-unknown-linux-ohos`.
- A compatible checkout of the upstream [KeyMagic 3](https://github.com/thantthet/keymagic-3) workspace, including `keymagic-core`.

The module targets `arm64-v8a` and declares HarmonyOS `default` and `tablet` device types.

## Repository layout for the native build

The checked-in CMake and PowerShell build script resolve the KeyMagic workspace two levels above this repository. Use this layout, or set the local CMake cache variable `KEYMAGIC_CORE_LIB` to an equivalent archive path without committing that machine-specific change:

```text
keymagic-3/                    # upstream workspace with Cargo.toml
├── keymagic-core/
├── mmkb-harmonyos/            # this repository
└── target/
    └── aarch64-unknown-linux-ohos/
```

## Build the native KeyMagic archive

Set `OHOS_SDK_HOME` to the OpenHarmony SDK directory containing `native/`, then run the helper from the upstream workspace root:

```powershell
$env:OHOS_SDK_HOME = '<OpenHarmony SDK root>'
rustup target add aarch64-unknown-linux-ohos
.\mmkb-harmonyos\scripts\build-core-ohos.ps1 -Profile release
```

The script runs Cargo for `keymagic-core` and expects this output:

```text
target/aarch64-unknown-linux-ohos/release/libkeymagic_core.a
```

The HarmonyOS CMake project statically links that archive into `libkeymagic3.so`. Do not commit the generated archive, native build directories, or HAP output.

## Keyboard rule files

Bundled KeyMagic rules are loaded from:

```text
keymagic3/src/main/resources/rawfile/keyboards/
```

Expected files are `.km2`, `.km2`, and `ZawCode.km2`. Confirm each layout's redistribution permission before adding or replacing a rule file; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Signing

`build-profile.json5` is local-only because it contains certificate paths and signing passwords. It is intentionally ignored.

1. Copy `build-profile.example.json5` to `build-profile.json5`.
2. Fill in your own certificate, provisioning profile, keystore path, alias, and passwords locally.
3. Never commit the populated file or any `.p12`, `.p7b`, `.cer`, private key, or password.

For a public repository, remove the existing tracked `build-profile.json5` from Git's index while retaining the local file used for builds:

```powershell
git rm --cached build-profile.json5
```

## Build the HAP

Open `mmkb-harmonyos/` in DevEco Studio, select the `keymagic3` module and the `default` product, then build a signed HAP. `keymagic3` is retained as the internal native-integration module name. Equivalent command-line build:

```powershell
& '<DevEco Studio>\tools\node\node.exe' '<DevEco Studio>\tools\hvigor\bin\hvigorw.js' `
  --mode module -p module=keymagic3 -p product=default -p requiredDeviceType=phone -p buildMode=release assembleHap
```

The signed output is generated below `keymagic3/build/default/outputs/` and is ignored by Git.

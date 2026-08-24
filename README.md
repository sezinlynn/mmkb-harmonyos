# mmKB for HarmonyOS

mmKB is a Myanmar and English software keyboard for HarmonyOS phones and tablets. It is a HarmonyOS input-method integration of the [KeyMagic 3](https://github.com/thantthet/keymagic-3) input engine.

## Features

- HarmonyOS `inputMethod` extension with a phone/tablet keyboard panel.
- Myanmar and English virtual keyboards, including numbers, symbols, emoji, and configurable appearance, key preview, haptics, and panel height.
- KeyMagic-compatible Myanmar keyboard-rule processing using bundled `.km2` layouts.
- Internal Burmese composition shown by the IME until a real commit boundary.
- Keyboard-layout selection for ZawCode and MM Unicode.

## KeyMagic integration

The native `libkeymagic3.so` N-API module is built from this repository's HarmonyOS bridge (`keymagic3/src/main/cpp/`) and statically links the upstream `keymagic-core` Rust library. The ArkTS wrapper in `KeyMagicNative.ets` calls that module through the upstream C FFI surface.

The expected upstream workspace is KeyMagic 3 version `0.0.11` (or a compatible revision). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution and bundled-layout licensing status.

## Privacy

The application source processes keyboard rules and active Myanmar composition locally. It contains no application network client or telemetry path for typed text. Committed text is sent only to the currently focused editor through HarmonyOS input-method APIs. Local preferences are used for keyboard settings and recently used emoji.

## Building

See [BUILDING.md](BUILDING.md) for the required DevEco Studio/OpenHarmony SDK, Rust native-library build, signing setup, and HAP build command. Never commit signing material; start from [build-profile.example.json5](build-profile.example.json5).

## License

This project is distributed under the [GNU General Public License, version 2 only](LICENSE) (`GPL-2.0-only`). KeyMagic 3 is an upstream GPL-2.0 dependency; this repository is a HarmonyOS integration/port and does not claim ownership of upstream KeyMagic code.

## Upstream

- KeyMagic 3: <https://github.com/thantthet/keymagic-3>

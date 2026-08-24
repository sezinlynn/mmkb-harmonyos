# Third-party notices

This file records third-party software and keyboard-layout material used by mmKB for HarmonyOS. It is an attribution and review aid, not a substitute for the applicable license texts.

## KeyMagic 3

- Upstream: <https://github.com/thantthet/keymagic-3>
- Integrated component: `keymagic-core` Rust engine, built into the HarmonyOS native `libkeymagic3.so` module.
- Upstream workspace version reviewed: `0.0.11`.
- Upstream attribution: `KeyMagic Contributors` (as declared in the upstream Cargo workspace).
- License: GNU General Public License, version 2 (`GPL-2.0`; this port is distributed as `GPL-2.0-only`).

mmKB contains a HarmonyOS integration/port around KeyMagic: the C++ N-API bridge in `keymagic3/src/main/cpp/`, ArkTS binding in `keymagic3/src/main/ets/common/KeyMagicNative.ets`, and HarmonyOS IME code are integration work. They are not represented as upstream KeyMagic source code.

The upstream KeyMagic 3 repository provides the full corresponding source for `keymagic-core`. A source release of this project must retain the GPL license text in [LICENSE](LICENSE) and make the compatible KeyMagic source/build instructions available.

## HarmonyOS development dependencies

The root `oh-package.json5` declares test-only development dependencies:

- `@ohos/hypium` `1.0.25`
- `@ohos/hamock` `1.0.0`

These packages, the HarmonyOS SDK, and DevEco Studio are not vendored in this repository. Their licenses and notices are supplied with their respective distributions.

## Bundled keyboard layouts

The following binary KeyMagic `.km2` layouts are bundled under `keymagic3/src/main/resources/rawfile/keyboards/`. No `.kms` source layout files are bundled in this repository.

| Layout file | Embedded metadata observed | Licensing status |
| --- | --- | --- |
| `.km2` | “မြန်စံ (Smart)”; metadata says it was converted into a KeyMagic layout from the Official  Keyman Layout; credits Thant Thet Khin Zaw | Permission/licensing to be confirmed with the respective rights holder. |
| `.km2` | “”; “, ” | Permission/licensing to be confirmed with the respective rights holder. |
| `ZawCode.km2` | “ဇော်ကုဒ်”; credits `TharLon` | Permission/licensing to be confirmed with the respective rights holder. |

These keyboard-layout files are **not** asserted to be GPL merely because the KeyMagic engine is GPL. Obtain and record written permission or an explicit license for each layout before claiming broad redistribution rights.

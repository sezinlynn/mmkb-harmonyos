import { KeyCode, KeyEvent as InputMethodKeyEvent } from '@kit.InputKit';

import { KeyMagicKeyInput } from './KeyMagicNative';

// Values are keymagic-core/src/types/virtual_keys.rs values, not HarmonyOS
// KeyCode values. Keep mapping here so the Rust engine remains platform-neutral.
export enum KeyMagicVirtualKey {
  Back = 2,
  Tab = 3,
  Return = 4,
  Shift = 5,
  Control = 6,
  Menu = 7,
  Capital = 9,
  Escape = 11,
  Space = 12,
  Prior = 13,
  Next = 14,
  Delete = 15,
  Key0 = 16,
  Key1 = 17,
  Key2 = 18,
  Key3 = 19,
  Key4 = 20,
  Key5 = 21,
  Key6 = 22,
  Key7 = 23,
  Key8 = 24,
  Key9 = 25,
  KeyA = 26,
  KeyB = 27,
  KeyC = 28,
  KeyD = 29,
  KeyE = 30,
  KeyF = 31,
  KeyG = 32,
  KeyH = 33,
  KeyI = 34,
  KeyJ = 35,
  KeyK = 36,
  KeyL = 37,
  KeyM = 38,
  KeyN = 39,
  KeyO = 40,
  KeyP = 41,
  KeyQ = 42,
  KeyR = 43,
  KeyS = 44,
  KeyT = 45,
  KeyU = 46,
  KeyV = 47,
  KeyW = 48,
  KeyX = 49,
  KeyY = 50,
  KeyZ = 51,
  Numpad0 = 52,
  Multiply = 62,
  Add = 63,
  Separator = 64,
  Subtract = 65,
  Decimal = 66,
  Divide = 67,
  F1 = 68,
  LShift = 80,
  RShift = 81,
  LControl = 82,
  RControl = 83,
  LMenu = 84,
  RMenu = 85,
  Oem1 = 86,
  OemPlus = 87,
  OemComma = 88,
  OemMinus = 89,
  OemPeriod = 90,
  Oem2 = 91,
  Oem3 = 92,
  Oem4 = 93,
  Oem5 = 94,
  Oem6 = 95,
  Oem7 = 96,
}

export function keyMagicVirtualKeyFromHarmonyKeyCode(keyCode: number): number {
  if (keyCode >= KeyCode.KEYCODE_0 && keyCode <= KeyCode.KEYCODE_9) {
    return KeyMagicVirtualKey.Key0 + keyCode - KeyCode.KEYCODE_0;
  }
  if (keyCode >= KeyCode.KEYCODE_A && keyCode <= KeyCode.KEYCODE_Z) {
    return KeyMagicVirtualKey.KeyA + keyCode - KeyCode.KEYCODE_A;
  }
  if (keyCode >= KeyCode.KEYCODE_F1 && keyCode <= KeyCode.KEYCODE_F12) {
    return KeyMagicVirtualKey.F1 + keyCode - KeyCode.KEYCODE_F1;
  }
  if (keyCode >= KeyCode.KEYCODE_NUMPAD_0 && keyCode <= KeyCode.KEYCODE_NUMPAD_9) {
    return KeyMagicVirtualKey.Numpad0 + keyCode - KeyCode.KEYCODE_NUMPAD_0;
  }

  switch (keyCode) {
    case KeyCode.KEYCODE_DEL:
      return KeyMagicVirtualKey.Back;
    case KeyCode.KEYCODE_TAB:
      return KeyMagicVirtualKey.Tab;
    case KeyCode.KEYCODE_ENTER:
    case KeyCode.KEYCODE_NUMPAD_ENTER:
      return KeyMagicVirtualKey.Return;
    case KeyCode.KEYCODE_SHIFT_LEFT:
      return KeyMagicVirtualKey.LShift;
    case KeyCode.KEYCODE_SHIFT_RIGHT:
      return KeyMagicVirtualKey.RShift;
    case KeyCode.KEYCODE_CTRL_LEFT:
      return KeyMagicVirtualKey.LControl;
    case KeyCode.KEYCODE_CTRL_RIGHT:
      return KeyMagicVirtualKey.RControl;
    case KeyCode.KEYCODE_ALT_LEFT:
      return KeyMagicVirtualKey.LMenu;
    case KeyCode.KEYCODE_ALT_RIGHT:
      return KeyMagicVirtualKey.RMenu;
    case KeyCode.KEYCODE_CAPS_LOCK:
      return KeyMagicVirtualKey.Capital;
    case KeyCode.KEYCODE_ESCAPE:
      return KeyMagicVirtualKey.Escape;
    case KeyCode.KEYCODE_SPACE:
      return KeyMagicVirtualKey.Space;
    case KeyCode.KEYCODE_PAGE_UP:
      return KeyMagicVirtualKey.Prior;
    case KeyCode.KEYCODE_PAGE_DOWN:
      return KeyMagicVirtualKey.Next;
    case KeyCode.KEYCODE_FORWARD_DEL:
      return KeyMagicVirtualKey.Delete;
    case KeyCode.KEYCODE_NUMPAD_MULTIPLY:
      return KeyMagicVirtualKey.Multiply;
    case KeyCode.KEYCODE_NUMPAD_ADD:
      return KeyMagicVirtualKey.Add;
    case KeyCode.KEYCODE_NUMPAD_COMMA:
      return KeyMagicVirtualKey.Separator;
    case KeyCode.KEYCODE_NUMPAD_SUBTRACT:
      return KeyMagicVirtualKey.Subtract;
    case KeyCode.KEYCODE_NUMPAD_DOT:
      return KeyMagicVirtualKey.Decimal;
    case KeyCode.KEYCODE_NUMPAD_DIVIDE:
      return KeyMagicVirtualKey.Divide;
    case KeyCode.KEYCODE_SEMICOLON:
      return KeyMagicVirtualKey.Oem1;
    case KeyCode.KEYCODE_EQUALS:
      return KeyMagicVirtualKey.OemPlus;
    case KeyCode.KEYCODE_COMMA:
      return KeyMagicVirtualKey.OemComma;
    case KeyCode.KEYCODE_MINUS:
      return KeyMagicVirtualKey.OemMinus;
    case KeyCode.KEYCODE_PERIOD:
      return KeyMagicVirtualKey.OemPeriod;
    case KeyCode.KEYCODE_SLASH:
      return KeyMagicVirtualKey.Oem2;
    case KeyCode.KEYCODE_GRAVE:
      return KeyMagicVirtualKey.Oem3;
    case KeyCode.KEYCODE_LEFT_BRACKET:
      return KeyMagicVirtualKey.Oem4;
    case KeyCode.KEYCODE_BACKSLASH:
      return KeyMagicVirtualKey.Oem5;
    case KeyCode.KEYCODE_RIGHT_BRACKET:
      return KeyMagicVirtualKey.Oem6;
    case KeyCode.KEYCODE_APOSTROPHE:
      return KeyMagicVirtualKey.Oem7;
    default:
      return 0;
  }
}

/**
 * Derives the single-byte character expected by the existing Rust FFI from
 * the physical key identity. HarmonyOS PC can report keyText such as
 * "KEYCODE_U", which is a symbolic name, not text that may be passed to the
 * KeyMagic engine.
 */
function asciiCharacterFromPhysicalKeyCode(keyCode: number, shift: boolean, capsLock: boolean): string {
  if (keyCode >= KeyCode.KEYCODE_A && keyCode <= KeyCode.KEYCODE_Z) {
    const letterOffset = keyCode - KeyCode.KEYCODE_A;
    const useUpperCase = shift !== capsLock;
    return String.fromCharCode((useUpperCase ? 0x41 : 0x61) + letterOffset);
  }

  if (keyCode >= KeyCode.KEYCODE_0 && keyCode <= KeyCode.KEYCODE_9) {
    // Shift is carried separately; the selected KeyMagic layout interprets the
    // physical digit identity together with this modifier state.
    return String.fromCharCode(0x30 + keyCode - KeyCode.KEYCODE_0);
  }

  switch (keyCode) {
    case KeyCode.KEYCODE_SEMICOLON:
      return shift ? ':' : ';';
    case KeyCode.KEYCODE_EQUALS:
      return shift ? '+' : '=';
    case KeyCode.KEYCODE_COMMA:
      return shift ? '<' : ',';
    case KeyCode.KEYCODE_MINUS:
      return shift ? '_' : '-';
    case KeyCode.KEYCODE_PERIOD:
      return shift ? '>' : '.';
    case KeyCode.KEYCODE_SLASH:
      return shift ? '?' : '/';
    case KeyCode.KEYCODE_GRAVE:
      return shift ? '~' : '`';
    case KeyCode.KEYCODE_LEFT_BRACKET:
      return shift ? '{' : '[';
    case KeyCode.KEYCODE_BACKSLASH:
      return shift ? '|' : '\\';
    case KeyCode.KEYCODE_RIGHT_BRACKET:
      return shift ? '}' : ']';
    case KeyCode.KEYCODE_APOSTROPHE:
      return shift ? '"' : '\'';
    case KeyCode.KEYCODE_SPACE:
      return ' ';
    default:
      return '';
  }
}

function modifierPressed(event: KeyEvent, name: string): boolean {
  if (event.getModifierKeyState === undefined) {
    return false;
  }
  return event.getModifierKeyState([name]);
}

/** Converts an ArkUI physical-key event into the existing KeyMagic FFI input. */
export function keyMagicInputFromHarmonyEvent(event: KeyEvent): KeyMagicKeyInput {
  const shift = modifierPressed(event, 'shift');
  const ctrl = modifierPressed(event, 'ctrl');
  const alt = modifierPressed(event, 'alt');
  const capsLock = event.isCapsLockOn === true;
  return {
    keyCode: keyMagicVirtualKeyFromHarmonyKeyCode(event.keyCode),
    character: asciiCharacterFromPhysicalKeyCode(event.keyCode, shift, capsLock),
    shift,
    ctrl,
    alt,
    capsLock,
  };
}

/**
 * Converts the API-20 IME KeyboardDelegate event shape into the same
 * KeyMagic input used by the verified ArkUI smoke page. The IME event exposes
 * the physical key as event.key.code and modifier booleans directly; its
 * unicodeChar is deliberately not used because KeyMagic rules use the
 * validated physical-key mapping and a one-byte ASCII character argument.
 */
export function keyMagicInputFromInputMethodEvent(event: InputMethodKeyEvent): KeyMagicKeyInput {
  const keyCode = event.key.code;
  return {
    keyCode: keyMagicVirtualKeyFromHarmonyKeyCode(keyCode),
    character: asciiCharacterFromPhysicalKeyCode(keyCode, event.shiftKey, event.capsLock),
    shift: event.shiftKey,
    ctrl: event.ctrlKey,
    alt: event.altKey,
    capsLock: event.capsLock,
  };
}

/**
 * Creates the same platform-neutral KeyMagic input shape for a virtual key.
 * The caller supplies the logical KeyMagic virtual-key value and the exact
 * ASCII character a matching physical key would provide. Burmese text never
 * enters this boundary: the loaded KM2 rules remain its only producer.
 */
export function keyMagicInputFromVirtualKey(
  keyCode: KeyMagicVirtualKey,
  character: string = '',
  shift: boolean = false,
): KeyMagicKeyInput {
  return {
    keyCode,
    character,
    shift,
    ctrl: false,
    alt: false,
    capsLock: false,
  };
}

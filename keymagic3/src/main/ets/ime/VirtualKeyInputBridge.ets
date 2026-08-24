import { KeyMagicVirtualKey } from '../common/KeyMagicKeyMap';

/** Commands owned by the keyboard panel rather than by KeyMagic. */
export enum VirtualKeyboardCommand {
  ToggleLanguage = 'toggleLanguage',
  BackspaceRelease = 'backspaceRelease',
  /** Reuses the controller's established composition-boundary commit/reset. */
  CommitComposition = 'commitComposition',
  /** Emoji bypasses KeyMagic but still uses the controller's known editor transport. */
  InsertEmoji = 'insertEmoji',
}

/** The one authoritative language-mode state for controller routing and panel rendering. */
export enum KeyboardLanguageMode {
  Burmese = 'burmese',
  English = 'english',
}

/** A panel button's physical-key equivalent, before KeyMagic processing. */
export interface VirtualKeyPress {
  keyCode: KeyMagicVirtualKey;
  /** The unshifted ASCII character from the matching physical key. */
  character?: string;
  /** The shifted ASCII character from the matching physical key. */
  shiftedCharacter?: string;
  /** English-only shifted text when KeyMagic must keep the physical ASCII digit. */
  englishShiftedCharacter?: string;
  /** A symbol-layer key that represents a shifted physical key directly. */
  forceShift?: boolean;
  /** Use only the static action's forceShift value, not the panel's visual Shift state. */
  ignoreVirtualShift?: boolean;
  /** Keep the visual Shift layer for the next press in a multi-action KeyMagic key. */
  preserveVirtualShift?: boolean;
  /** True only for an existing Backspace hold-repeat tick, never its initial DOWN. */
  isBackspaceRepeat?: boolean;
  /** A panel action that does not represent a KeyMagic key. */
  command?: VirtualKeyboardCommand;
  label: string;
}

type VirtualKeyPressHandler = (press: VirtualKeyPress) => void;
type VirtualKeyboardLanguageModeListener = (mode: KeyboardLanguageMode) => void;

// The IME controller and its panel run in the same InputMethodExtension
// runtime. This bridge transports logical panel state only; it never owns
// KeyMagic, composition, or editor state.
let handler: VirtualKeyPressHandler | undefined;
let keyboardLanguageMode: KeyboardLanguageMode = KeyboardLanguageMode.Burmese;
let keyboardLanguageModeListener: VirtualKeyboardLanguageModeListener | undefined;

export function setVirtualKeyPressHandler(nextHandler: VirtualKeyPressHandler): void {
  handler = nextHandler;
}

export function clearVirtualKeyPressHandler(expectedHandler: VirtualKeyPressHandler): void {
  if (handler === expectedHandler) {
    handler = undefined;
  }
}

export function dispatchVirtualKeyPress(press: VirtualKeyPress): void {
  if (handler !== undefined) {
    handler(press);
  }
}

/** Reads the controller-owned virtual-keyboard mode without creating a UI copy. */
export function getVirtualKeyboardLanguageMode(): KeyboardLanguageMode {
  return keyboardLanguageMode;
}

/** Publishes a mode transition from the controller to the currently loaded panel. */
export function setVirtualKeyboardLanguageMode(nextMode: KeyboardLanguageMode): KeyboardLanguageMode {
  const previousMode = keyboardLanguageMode;
  if (previousMode === nextMode) {
    return previousMode;
  }
  keyboardLanguageMode = nextMode;
  if (keyboardLanguageModeListener !== undefined) {
    keyboardLanguageModeListener(nextMode);
  }
  return previousMode;
}

/** The IME owns one fixed panel, so it registers exactly one display listener. */
export function setVirtualKeyboardLanguageModeListener(listener: VirtualKeyboardLanguageModeListener): void {
  keyboardLanguageModeListener = listener;
  listener(keyboardLanguageMode);
}

export function clearVirtualKeyboardLanguageModeListener(expectedListener: VirtualKeyboardLanguageModeListener): void {
  if (keyboardLanguageModeListener === expectedListener) {
    keyboardLanguageModeListener = undefined;
  }
}

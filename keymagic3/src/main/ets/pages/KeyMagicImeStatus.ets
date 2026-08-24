import { KeyMagicVirtualKey } from '../common/KeyMagicKeyMap';
import { hilog } from '@kit.PerformanceAnalysisKit';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import vibrator from '@ohos.vibrator';
import {
  EmojiCategory,
  EmojiCategoryId,
  emojiCategoryById,
  EMOJI_CATEGORIES,
} from '../keyboard/EmojiData';
import {
  clearVirtualKeyboardLanguageModeListener,
  dispatchVirtualKeyPress,
  getVirtualKeyboardLanguageMode,
  KeyboardLanguageMode,
  setVirtualKeyboardLanguageModeListener,
  VirtualKeyboardCommand,
} from '../ime/VirtualKeyInputBridge';
import { EmojiRecentSettings, EMOJI_RECENT_LIMIT } from '../settings/EmojiRecentSettings';

const KEYBOARD_UI_LOG_DOMAIN = 0x0000;
const KEYBOARD_UI_LOG_TAG = 'KeyMagicIme';
// Burmese reserves this strip permanently. It is not conditional on the
// composition text, so composition updates never move or resize a key row.
const BURMESE_COMPOSITION_STRIP_HEIGHT = 46;
const BURMESE_KEY_FONT_SIZE = 20;
const BURMESE_KEY_LINE_HEIGHT = 46;
// The equal-width Myanmar line box needs a little more physical space above
// and below it than Latin. This 4/1 padding keeps glyph extents inside the
// enlarged cap while moving the visual center down by roughly 1.5vp,
// uniformly.
const BURMESE_KEY_OPTICAL_TOP_PADDING = 4;
const BURMESE_KEY_OPTICAL_BOTTOM_PADDING = 1;
const BURMESE_LONG_PRESS_DELAY_MS = 400;
const BURMESE_POPUP_OPTION_WIDTH = 78;
const BURMESE_POPUP_HEIGHT = 60;
const BURMESE_POPUP_GAP = 4;
const BURMESE_POPUP_EDGE_MARGIN = 4;
const BURMESE_LONG_PRESS_CANCEL_SLOP = 24;
const KEY_PREVIEW_EDGE_MARGIN = 3;
const KEY_PREVIEW_GAP = 2;
// Keep this bubble recognizably related to its source key.  The bounds cap
// prevents a wide special key or multi-codepoint Myanmar label from becoming
// a large floating tile.
const KEY_PREVIEW_WIDTH_RATIO = 1.12;
const KEY_PREVIEW_HEIGHT_RATIO = 1.16;
const KEY_PREVIEW_MIN_WIDTH = 32;
const KEY_PREVIEW_MAX_WIDTH = 52;
const KEY_PREVIEW_MIN_HEIGHT = 40;
const KEY_PREVIEW_MAX_HEIGHT = 60;
const KEY_PREVIEW_ENGLISH_FONT_SIZE = 25;
const KEY_PREVIEW_ENGLISH_LINE_HEIGHT = 32;
const KEY_PREVIEW_BURMESE_FONT_SIZE = 26;
const KEY_PREVIEW_BURMESE_LINE_HEIGHT = 38;
// 30 ms is still a subtle keypress pulse, but is materially easier to feel
// than the previous 18 ms diagnostic on typical phone motors.
const HAPTIC_TAP_DURATION_MS = 30;
const HAPTIC_LONG_PRESS_DURATION_MS = 36;

interface HapticRuntimeError {
  code?: number;
  message?: string;
}

/**
 * A static keycap plus its independent logical KeyMagic input. `label` is
 * always declared by the screen layout; it is never derived from the engine.
 */
interface KeyMagicActionDefinition {
  keyCode: KeyMagicVirtualKey;
  /** The physical ASCII identity supplied to the existing shared handler. */
  character?: string;
  /** The shifted physical ASCII identity supplied to the shared handler. */
  shiftedCharacter?: string;
  /** This static key is a shifted KeyMagic action even without a Shift tap. */
  forceShift?: boolean;
}

/** One reusable Burmese long-press alternative, expressed only as KeyMagic actions. */
interface PopupKeyOption {
  id: string;
  label: string;
  actions: KeyMagicActionDefinition[];
}

interface VirtualKeyDefinition extends KeyMagicActionDefinition {
  /** Stable UI identity required only for keys with long-press alternatives. */
  id?: string;
  label: string;
  /** Optional English keycap text for the common numbers/symbol layer. */
  englishLabel?: string;
  /** Optional English shifted keycap text. */
  englishShiftedLabel?: string;
  /** English text for a shifted ASCII identity, when it differs. */
  englishShiftedCharacter?: string;
  /**
   * One-shot KeyMagic state selectors required before this physical identity.
   * These are internal actions only; they never determine a displayed keycap.
   */
  prefixActions?: KeyMagicActionDefinition[];
  longPressOptions?: PopupKeyOption[];
  weight?: number;
}

/**
 * Adds the existing, proven `္ဆ` long-press behavior to a consonant without
 * deriving any physical identity from its visible label. The popup dispatches
 * the virama identity first and then precisely this key's already-declared
 * KeyMagic action (including any existing prefix actions and Shift state).
 */
function withStackedConsonant(id: string, key: VirtualKeyDefinition): VirtualKeyDefinition {
  const actions: KeyMagicActionDefinition[] = [
    { keyCode: KeyMagicVirtualKey.Oem3, character: '`' },
  ];
  if (key.prefixActions !== undefined) {
    key.prefixActions.forEach((action: KeyMagicActionDefinition): void => {
      actions.push({
        keyCode: action.keyCode,
        character: action.character,
        shiftedCharacter: action.shiftedCharacter,
        forceShift: action.forceShift,
      });
    });
  }
  actions.push({
    keyCode: key.keyCode,
    character: key.character,
    shiftedCharacter: key.shiftedCharacter,
    forceShift: key.forceShift,
  });
  return {
    id,
    label: key.label,
    keyCode: key.keyCode,
    character: key.character,
    shiftedCharacter: key.shiftedCharacter,
    forceShift: key.forceShift,
    englishLabel: key.englishLabel,
    englishShiftedLabel: key.englishShiftedLabel,
    englishShiftedCharacter: key.englishShiftedCharacter,
    prefixActions: key.prefixActions,
    weight: key.weight,
    longPressOptions: [{
      id: `stacked-${id}`,
      label: `္${key.label}`,
      actions,
    }],
  };
}

interface PopupKeyAnchor {
  globalLeft: number;
  globalTop: number;
  width: number;
  height: number;
}

type BurmeseBottomKeyKind = 'numbers' | 'language' | 'logical' | 'space' | 'enter';

/** One complete screenshot footer key, including its visual width and action kind. */
interface BurmeseBottomKeyDefinition {
  kind: BurmeseBottomKeyKind;
  label: string;
  weight: number;
  logicalKey?: VirtualKeyDefinition;
}

/** The visible page is independent from the controller-owned language mode. */
enum KeyboardLayer {
  Letters = 'letters',
  Numbers = 'numbers',
  Symbols = 'symbols',
  Emoji = 'emoji',
}

/** Responsive fixed-panel keyboard with screenshot-defined Burmese keycaps. */
@Entry
@Component
struct KeyMagicImeStatus {
  @StorageLink('keymagicImeCompositionPopupText') composition: string = '';
  @StorageLink('keymagicImeCompositionPopupVisible') compositionPopupVisible: string = 'false';
  @StorageLink('keymagicImeCompositionPopupColorMode') colorMode: string = 'light';
  @StorageLink('keymagicImeVirtualShiftActive') shiftActive: string = 'false';
  @StorageLink('keymagicImeKeyboardPanelVisible') @Watch('onKeyboardPanelVisibilityChanged')
  keyboardPanelVisible: string = 'false';
  @StorageLink('myankeyKeyboardHapticEnabled') @Watch('onHapticSettingChanged') hapticEnabled: boolean = false;
  @StorageLink('myankeyKeyboardKeyPreviewEnabled') keyPreviewEnabled: boolean = true;
  @StorageLink('myankeyKeyboardTheme') keyboardTheme: string = 'system';
  // The controller owns this value in VirtualKeyInputBridge; this @State is only
  // the reactive rendering subscription for the currently visible panel.
  @State languageMode: KeyboardLanguageMode = getVirtualKeyboardLanguageMode();
  @State keyboardLayer: KeyboardLayer = KeyboardLayer.Letters;
  @State longPressPopupVisible: boolean = false;
  @State longPressPopupLeft: number = 0;
  @State longPressPopupTop: number = 0;
  @State longPressHighlightedOptionIndex: number = -1;
  @State keyPreviewVisible: boolean = false;
  @State keyPreviewLabel: string = '';
  @State keyPreviewIsBurmese: boolean = false;
  @State keyPreviewLeft: number = 0;
  @State keyPreviewTop: number = 0;
  @State keyPreviewWidth: number = KEY_PREVIEW_MIN_WIDTH;
  @State keyPreviewHeight: number = KEY_PREVIEW_MIN_HEIGHT;
  @State keyPreviewFontSize: number = KEY_PREVIEW_ENGLISH_FONT_SIZE;
  @State keyPreviewLineHeight: number = KEY_PREVIEW_ENGLISH_LINE_HEIGHT;
  @State selectedEmojiCategoryId: EmojiCategoryId = 'smileys';
  @State recentEmojis: string[] = [];
  private backspacePressed: boolean = false;
  private backspaceInitialTimer: number = -1;
  private backspaceRepeatTimer: number = -1;
  private longPressTimer: number = -1;
  private longPressTouchActive: boolean = false;
  private longPressTriggered: boolean = false;
  private longPressSelectionMoved: boolean = false;
  private longPressKey: VirtualKeyDefinition | undefined;
  private longPressOptions: PopupKeyOption[] = [];
  private readonly longPressAnchors: Map<string, PopupKeyAnchor> = new Map();
  private readonly keyPreviewAnchors: Map<string, PopupKeyAnchor> = new Map();
  private keyboardPageGlobalLeft: number = 0;
  private keyboardPageGlobalTop: number = 0;
  private keyboardPageWidth: number = 0;
  private keyboardPageHeight: number = 0;
  private hapticCapabilityLogged: boolean = false;

  // English is its own QWERTY screen and deliberately never invokes KeyMagic.
  private readonly englishNormalRow1: VirtualKeyDefinition[] = [
    { keyCode: KeyMagicVirtualKey.KeyQ, label: 'q', englishShiftedLabel: 'Q', character: 'q', shiftedCharacter: 'Q' },
    { keyCode: KeyMagicVirtualKey.KeyW, label: 'w', englishShiftedLabel: 'W', character: 'w', shiftedCharacter: 'W' },
    { keyCode: KeyMagicVirtualKey.KeyE, label: 'e', englishShiftedLabel: 'E', character: 'e', shiftedCharacter: 'E' },
    { keyCode: KeyMagicVirtualKey.KeyR, label: 'r', englishShiftedLabel: 'R', character: 'r', shiftedCharacter: 'R' },
    { keyCode: KeyMagicVirtualKey.KeyT, label: 't', englishShiftedLabel: 'T', character: 't', shiftedCharacter: 'T' },
    { keyCode: KeyMagicVirtualKey.KeyY, label: 'y', englishShiftedLabel: 'Y', character: 'y', shiftedCharacter: 'Y' },
    { keyCode: KeyMagicVirtualKey.KeyU, label: 'u', englishShiftedLabel: 'U', character: 'u', shiftedCharacter: 'U' },
    { keyCode: KeyMagicVirtualKey.KeyI, label: 'i', englishShiftedLabel: 'I', character: 'i', shiftedCharacter: 'I' },
    { keyCode: KeyMagicVirtualKey.KeyO, label: 'o', englishShiftedLabel: 'O', character: 'o', shiftedCharacter: 'O' },
    { keyCode: KeyMagicVirtualKey.KeyP, label: 'p', englishShiftedLabel: 'P', character: 'p', shiftedCharacter: 'P' },
  ];
  private readonly englishNormalRow2: VirtualKeyDefinition[] = [
    { keyCode: KeyMagicVirtualKey.KeyA, label: 'a', englishShiftedLabel: 'A', character: 'a', shiftedCharacter: 'A' },
    { keyCode: KeyMagicVirtualKey.KeyS, label: 's', englishShiftedLabel: 'S', character: 's', shiftedCharacter: 'S' },
    { keyCode: KeyMagicVirtualKey.KeyD, label: 'd', englishShiftedLabel: 'D', character: 'd', shiftedCharacter: 'D' },
    { keyCode: KeyMagicVirtualKey.KeyF, label: 'f', englishShiftedLabel: 'F', character: 'f', shiftedCharacter: 'F' },
    { keyCode: KeyMagicVirtualKey.KeyG, label: 'g', englishShiftedLabel: 'G', character: 'g', shiftedCharacter: 'G' },
    { keyCode: KeyMagicVirtualKey.KeyH, label: 'h', englishShiftedLabel: 'H', character: 'h', shiftedCharacter: 'H' },
    { keyCode: KeyMagicVirtualKey.KeyJ, label: 'j', englishShiftedLabel: 'J', character: 'j', shiftedCharacter: 'J' },
    { keyCode: KeyMagicVirtualKey.KeyK, label: 'k', englishShiftedLabel: 'K', character: 'k', shiftedCharacter: 'K' },
    { keyCode: KeyMagicVirtualKey.KeyL, label: 'l', englishShiftedLabel: 'L', character: 'l', shiftedCharacter: 'L' },
  ];
  private readonly englishNormalRow3: VirtualKeyDefinition[] = [
    { keyCode: KeyMagicVirtualKey.KeyZ, label: 'z', englishShiftedLabel: 'Z', character: 'z', shiftedCharacter: 'Z' },
    { keyCode: KeyMagicVirtualKey.KeyX, label: 'x', englishShiftedLabel: 'X', character: 'x', shiftedCharacter: 'X' },
    { keyCode: KeyMagicVirtualKey.KeyC, label: 'c', englishShiftedLabel: 'C', character: 'c', shiftedCharacter: 'C' },
    { keyCode: KeyMagicVirtualKey.KeyV, label: 'v', englishShiftedLabel: 'V', character: 'v', shiftedCharacter: 'V' },
    { keyCode: KeyMagicVirtualKey.KeyB, label: 'b', englishShiftedLabel: 'B', character: 'b', shiftedCharacter: 'B' },
    { keyCode: KeyMagicVirtualKey.KeyN, label: 'n', englishShiftedLabel: 'N', character: 'n', shiftedCharacter: 'N' },
    { keyCode: KeyMagicVirtualKey.KeyM, label: 'm', englishShiftedLabel: 'M', character: 'm', shiftedCharacter: 'M' },
  ];
  private readonly englishShiftRow1: VirtualKeyDefinition[] = [
    { keyCode: KeyMagicVirtualKey.KeyQ, label: 'Q', character: 'q', shiftedCharacter: 'Q', englishShiftedCharacter: 'Q', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyW, label: 'W', character: 'w', shiftedCharacter: 'W', englishShiftedCharacter: 'W', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyE, label: 'E', character: 'e', shiftedCharacter: 'E', englishShiftedCharacter: 'E', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyR, label: 'R', character: 'r', shiftedCharacter: 'R', englishShiftedCharacter: 'R', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyT, label: 'T', character: 't', shiftedCharacter: 'T', englishShiftedCharacter: 'T', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyY, label: 'Y', character: 'y', shiftedCharacter: 'Y', englishShiftedCharacter: 'Y', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyU, label: 'U', character: 'u', shiftedCharacter: 'U', englishShiftedCharacter: 'U', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyI, label: 'I', character: 'i', shiftedCharacter: 'I', englishShiftedCharacter: 'I', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyO, label: 'O', character: 'o', shiftedCharacter: 'O', englishShiftedCharacter: 'O', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyP, label: 'P', character: 'p', shiftedCharacter: 'P', englishShiftedCharacter: 'P', forceShift: true },
  ];
  private readonly englishShiftRow2: VirtualKeyDefinition[] = [
    { keyCode: KeyMagicVirtualKey.KeyA, label: 'A', character: 'a', shiftedCharacter: 'A', englishShiftedCharacter: 'A', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyS, label: 'S', character: 's', shiftedCharacter: 'S', englishShiftedCharacter: 'S', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyD, label: 'D', character: 'd', shiftedCharacter: 'D', englishShiftedCharacter: 'D', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyF, label: 'F', character: 'f', shiftedCharacter: 'F', englishShiftedCharacter: 'F', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyG, label: 'G', character: 'g', shiftedCharacter: 'G', englishShiftedCharacter: 'G', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyH, label: 'H', character: 'h', shiftedCharacter: 'H', englishShiftedCharacter: 'H', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyJ, label: 'J', character: 'j', shiftedCharacter: 'J', englishShiftedCharacter: 'J', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyK, label: 'K', character: 'k', shiftedCharacter: 'K', englishShiftedCharacter: 'K', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyL, label: 'L', character: 'l', shiftedCharacter: 'L', englishShiftedCharacter: 'L', forceShift: true },
  ];
  private readonly englishShiftRow3: VirtualKeyDefinition[] = [
    { keyCode: KeyMagicVirtualKey.KeyZ, label: 'Z', character: 'z', shiftedCharacter: 'Z', englishShiftedCharacter: 'Z', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyX, label: 'X', character: 'x', shiftedCharacter: 'X', englishShiftedCharacter: 'X', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyC, label: 'C', character: 'c', shiftedCharacter: 'C', englishShiftedCharacter: 'C', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyV, label: 'V', character: 'v', shiftedCharacter: 'V', englishShiftedCharacter: 'V', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyB, label: 'B', character: 'b', shiftedCharacter: 'B', englishShiftedCharacter: 'B', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyN, label: 'N', character: 'n', shiftedCharacter: 'N', englishShiftedCharacter: 'N', forceShift: true },
    { keyCode: KeyMagicVirtualKey.KeyM, label: 'M', character: 'm', shiftedCharacter: 'M', englishShiftedCharacter: 'M', forceShift: true },
  ];

  // Authoritative Burmese normal screen. These keycaps and positions are
  // intentionally static UI data; their KeyMagic actions are independent.
  private readonly burmeseNormalRow1: VirtualKeyDefinition[] = [
    withStackedConsonant('burmese-sa', { label: 'ဆ', keyCode: KeyMagicVirtualKey.KeyQ, character: 'q' }),
    withStackedConsonant('burmese-ta', { label: 'တ', keyCode: KeyMagicVirtualKey.KeyW, character: 'w' }),
    withStackedConsonant('burmese-na', { label: 'န', keyCode: KeyMagicVirtualKey.KeyE, character: 'e' }),
    withStackedConsonant('burmese-ma', { label: 'မ', keyCode: KeyMagicVirtualKey.KeyR, character: 'r' }),
    withStackedConsonant('burmese-a', { label: 'အ', keyCode: KeyMagicVirtualKey.KeyT, character: 't' }),
    withStackedConsonant('burmese-pa', { label: 'ပ', keyCode: KeyMagicVirtualKey.KeyY, character: 'y' }),
    withStackedConsonant('burmese-ka', { label: 'က', keyCode: KeyMagicVirtualKey.KeyU, character: 'u' }),
    withStackedConsonant('burmese-nga', { label: 'င', keyCode: KeyMagicVirtualKey.KeyI, character: 'i' }),
    withStackedConsonant('burmese-tha', { label: 'သ', keyCode: KeyMagicVirtualKey.KeyO, character: 'o' }),
    withStackedConsonant('burmese-ca', { label: 'စ', keyCode: KeyMagicVirtualKey.KeyP, character: 'p' }),
    withStackedConsonant('burmese-ha', { label: 'ဟ', keyCode: KeyMagicVirtualKey.Oem4, character: '[' }),
  ];
  private readonly burmeseNormalRow2: VirtualKeyDefinition[] = [
    { label: 'ေ', keyCode: KeyMagicVirtualKey.KeyA, character: 'a' },
    { label: 'ျ', keyCode: KeyMagicVirtualKey.KeyS, character: 's' },
    { label: 'ိ', keyCode: KeyMagicVirtualKey.KeyD, character: 'd' },
    { label: '်', keyCode: KeyMagicVirtualKey.KeyF, character: 'f' },
    { label: 'ါ', keyCode: KeyMagicVirtualKey.KeyG, character: 'g' },
    { label: '့', keyCode: KeyMagicVirtualKey.KeyH, character: 'h' },
    { label: 'ြ', keyCode: KeyMagicVirtualKey.KeyJ, character: 'j' },
    { label: 'ု', keyCode: KeyMagicVirtualKey.KeyK, character: 'k' },
    { label: 'ူ', keyCode: KeyMagicVirtualKey.KeyL, character: 'l' },
    { label: 'း', keyCode: KeyMagicVirtualKey.Oem1, character: ';' },
    withStackedConsonant('burmese-da', { label: 'ဒ', keyCode: KeyMagicVirtualKey.Oem7, character: '\'' }),
  ];
  private readonly burmeseNormalRow3: VirtualKeyDefinition[] = [
    withStackedConsonant('burmese-pha', { label: 'ဖ', keyCode: KeyMagicVirtualKey.KeyZ, character: 'z' }),
    withStackedConsonant('burmese-hta', { label: 'ထ', keyCode: KeyMagicVirtualKey.KeyX, character: 'x' }),
    withStackedConsonant('burmese-kha', { label: 'ခ', keyCode: KeyMagicVirtualKey.KeyC, character: 'c' }),
    withStackedConsonant('burmese-la', { label: 'လ', keyCode: KeyMagicVirtualKey.KeyV, character: 'v' }),
    withStackedConsonant('burmese-bha', { label: 'ဘ', keyCode: KeyMagicVirtualKey.KeyB, character: 'b' }),
    withStackedConsonant('burmese-nya', { label: 'ည', keyCode: KeyMagicVirtualKey.KeyN, character: 'n' }),
    { label: 'ာ', keyCode: KeyMagicVirtualKey.KeyM, character: 'm' },
    withStackedConsonant('burmese-ya', { label: 'ယ', keyCode: KeyMagicVirtualKey.OemComma, character: ',' }),
  ];

  // Authoritative Burmese Shift screen. This is a separate fixed UI layer,
  // never a transform of the Normal labels or a projection of KeyMagic data.
  private readonly burmeseShiftRow1: VirtualKeyDefinition[] = [
    withStackedConsonant('burmese-jha', { label: 'ဈ', keyCode: KeyMagicVirtualKey.OemPeriod, character: '.', shiftedCharacter: '>', forceShift: true }),
    withStackedConsonant('burmese-tta', { label: 'ဋ', keyCode: KeyMagicVirtualKey.Key3, character: '3', shiftedCharacter: '3', forceShift: true }),
    { label: 'ဤ', keyCode: KeyMagicVirtualKey.KeyT, character: 't', prefixActions: [{ keyCode: KeyMagicVirtualKey.Oem3, character: '`' }] },
    { label: 'ဋ္ဌ', keyCode: KeyMagicVirtualKey.Oem5, character: '\\', shiftedCharacter: '|', forceShift: true },
    { label: 'ဣ', keyCode: KeyMagicVirtualKey.Key4, character: '4', shiftedCharacter: '4', forceShift: true, prefixActions: [{ keyCode: KeyMagicVirtualKey.Oem3, character: '`' }] },
    { label: '၍', keyCode: KeyMagicVirtualKey.KeyI, character: 'i', prefixActions: [{ keyCode: KeyMagicVirtualKey.Oem3, character: '`' }] },
    { label: '၌', keyCode: KeyMagicVirtualKey.Key4, character: '4', shiftedCharacter: '4', forceShift: true },
    { label: 'ဿ', keyCode: KeyMagicVirtualKey.KeyO, character: 'o', prefixActions: [{ keyCode: KeyMagicVirtualKey.Oem3, character: '`' }] },
    { label: 'ဥ', keyCode: KeyMagicVirtualKey.KeyO, character: 'o', shiftedCharacter: 'O', forceShift: true },
    withStackedConsonant('burmese-nna', { label: 'ဏ', keyCode: KeyMagicVirtualKey.KeyP, character: 'p', shiftedCharacter: 'P', forceShift: true }),
    { label: 'ဧ', keyCode: KeyMagicVirtualKey.Oem4, character: '[', shiftedCharacter: '{', forceShift: true },
  ];
  private readonly burmeseShiftRow2: VirtualKeyDefinition[] = [
    withStackedConsonant('burmese-ba', { label: 'ဗ', keyCode: KeyMagicVirtualKey.KeyA, character: 'a', shiftedCharacter: 'A', forceShift: true }),
    { label: 'ှ', keyCode: KeyMagicVirtualKey.KeyS, character: 's', shiftedCharacter: 'S', forceShift: true },
    { label: 'ီ', keyCode: KeyMagicVirtualKey.KeyD, character: 'd', shiftedCharacter: 'D', forceShift: true },
    { label: 'င်္', keyCode: KeyMagicVirtualKey.KeyF, character: 'f', shiftedCharacter: 'F', forceShift: true },
    { label: 'ွ', keyCode: KeyMagicVirtualKey.KeyG, character: 'g', shiftedCharacter: 'G', forceShift: true },
    { label: 'ံ', keyCode: KeyMagicVirtualKey.KeyH, character: 'h', shiftedCharacter: 'H', forceShift: true },
    { label: 'ဲ', keyCode: KeyMagicVirtualKey.KeyJ, character: 'j', shiftedCharacter: 'J', forceShift: true },
    { label: '၎င်း', keyCode: KeyMagicVirtualKey.Key4, character: '4', prefixActions: [{ keyCode: KeyMagicVirtualKey.Oem3, character: '`' }] },
    withStackedConsonant('burmese-dda', { label: 'ဍ', keyCode: KeyMagicVirtualKey.Key1, character: '1', shiftedCharacter: '1', forceShift: true }),
    { label: 'ဩ', keyCode: KeyMagicVirtualKey.Key5, character: '5', prefixActions: [{ keyCode: KeyMagicVirtualKey.Oem3, character: '`' }] },
    withStackedConsonant('burmese-dha', { label: 'ဓ', keyCode: KeyMagicVirtualKey.Oem7, character: '\'', shiftedCharacter: '"', forceShift: true }),
  ];
  private readonly burmeseShiftRow3: VirtualKeyDefinition[] = [
    withStackedConsonant('burmese-ja', { label: 'ဇ', keyCode: KeyMagicVirtualKey.KeyZ, character: 'z', shiftedCharacter: 'Z', forceShift: true }),
    withStackedConsonant('burmese-ttha', { label: 'ဌ', keyCode: KeyMagicVirtualKey.KeyX, character: 'x', shiftedCharacter: 'X', forceShift: true }),
    withStackedConsonant('burmese-gha', { label: 'ဃ', keyCode: KeyMagicVirtualKey.KeyC, character: 'c', shiftedCharacter: 'C', forceShift: true }),
    withStackedConsonant('burmese-lla', { label: 'ဠ', keyCode: KeyMagicVirtualKey.KeyV, character: 'v', shiftedCharacter: 'V', forceShift: true }),
    withStackedConsonant('burmese-ddha', { label: 'ဎ', keyCode: KeyMagicVirtualKey.OemComma, character: ',', prefixActions: [{ keyCode: KeyMagicVirtualKey.Oem3, character: '`' }] }),
    withStackedConsonant('burmese-nnya', { label: 'ဉ', keyCode: KeyMagicVirtualKey.KeyN, character: 'n', prefixActions: [{ keyCode: KeyMagicVirtualKey.Oem3, character: '`' }] }),
    { label: '၏', keyCode: KeyMagicVirtualKey.Oem5, character: '\\' },
    withStackedConsonant('burmese-ga', { label: 'ဂ', keyCode: KeyMagicVirtualKey.Key8, character: '8', shiftedCharacter: '8', forceShift: true }),
  ];

  // Non-letter pages are fixed static layouts. English and Burmese deliberately
  // have their own arrays: screen language does not relabel the other language's
  // page, and Burmese actions retain their physical KeyMagic identities.
  private readonly englishNumberRows: VirtualKeyDefinition[][] = [
    [
      { keyCode: KeyMagicVirtualKey.Key1, label: '1', character: '1' },
      { keyCode: KeyMagicVirtualKey.Key2, label: '2', character: '2' },
      { keyCode: KeyMagicVirtualKey.Key3, label: '3', character: '3' },
      { keyCode: KeyMagicVirtualKey.Key4, label: '4', character: '4' },
      { keyCode: KeyMagicVirtualKey.Key5, label: '5', character: '5' },
      { keyCode: KeyMagicVirtualKey.Key6, label: '6', character: '6' },
      { keyCode: KeyMagicVirtualKey.Key7, label: '7', character: '7' },
      { keyCode: KeyMagicVirtualKey.Key8, label: '8', character: '8' },
      { keyCode: KeyMagicVirtualKey.Key9, label: '9', character: '9' },
      { keyCode: KeyMagicVirtualKey.Key0, label: '0', character: '0' },
    ],
    [
      { keyCode: KeyMagicVirtualKey.OemMinus, label: '-', character: '-' },
      { keyCode: KeyMagicVirtualKey.Oem2, label: '/', character: '/' },
      { keyCode: KeyMagicVirtualKey.Oem1, label: ':', character: ';', shiftedCharacter: ':', englishShiftedCharacter: ':', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem1, label: ';', character: ';' },
      { keyCode: KeyMagicVirtualKey.Key9, label: '(', character: '9', shiftedCharacter: '9', englishShiftedCharacter: '(', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key0, label: ')', character: '0', shiftedCharacter: '0', englishShiftedCharacter: ')', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key4, label: '$', character: '4', shiftedCharacter: '4', englishShiftedCharacter: '$', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key7, label: '&', character: '7', shiftedCharacter: '7', englishShiftedCharacter: '&', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key2, label: '@', character: '2', shiftedCharacter: '2', englishShiftedCharacter: '@', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem7, label: '"', character: '\'', shiftedCharacter: '"', englishShiftedCharacter: '"', forceShift: true },
    ],
    [
      { keyCode: KeyMagicVirtualKey.OemPeriod, label: '.', character: '.' },
      { keyCode: KeyMagicVirtualKey.OemComma, label: ',', character: ',' },
      { keyCode: KeyMagicVirtualKey.Oem2, label: '?', character: '/', shiftedCharacter: '?', englishShiftedCharacter: '?', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key1, label: '!', character: '1', shiftedCharacter: '1', englishShiftedCharacter: '!', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem7, label: '\'', character: '\'' },
    ],
  ];
  private readonly englishSymbolRows: VirtualKeyDefinition[][] = [
    [
      { keyCode: KeyMagicVirtualKey.Oem4, label: '[', character: '[' },
      { keyCode: KeyMagicVirtualKey.Oem6, label: ']', character: ']' },
      { keyCode: KeyMagicVirtualKey.Oem4, label: '{', character: '[', shiftedCharacter: '{', englishShiftedCharacter: '{', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem6, label: '}', character: ']', shiftedCharacter: '}', englishShiftedCharacter: '}', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key3, label: '#', character: '3', shiftedCharacter: '3', englishShiftedCharacter: '#', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key5, label: '%', character: '5', shiftedCharacter: '5', englishShiftedCharacter: '%', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key6, label: '^', character: '6', shiftedCharacter: '6', englishShiftedCharacter: '^', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key8, label: '*', character: '8', shiftedCharacter: '8', englishShiftedCharacter: '*', forceShift: true },
      { keyCode: KeyMagicVirtualKey.OemPlus, label: '+', character: '=', shiftedCharacter: '+', englishShiftedCharacter: '+', forceShift: true },
      { keyCode: KeyMagicVirtualKey.OemPlus, label: '=', character: '=' },
    ],
    [
      { keyCode: KeyMagicVirtualKey.OemMinus, label: '_', character: '-', shiftedCharacter: '_', englishShiftedCharacter: '_', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem5, label: '\\', character: '\\' },
      { keyCode: KeyMagicVirtualKey.Oem5, label: '|', character: '\\', shiftedCharacter: '|', englishShiftedCharacter: '|', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem3, label: '~', character: '`', shiftedCharacter: '~', englishShiftedCharacter: '~', forceShift: true },
      { keyCode: KeyMagicVirtualKey.OemComma, label: '<', character: ',', shiftedCharacter: '<', englishShiftedCharacter: '<', forceShift: true },
      { keyCode: KeyMagicVirtualKey.OemPeriod, label: '>', character: '.', shiftedCharacter: '>', englishShiftedCharacter: '>', forceShift: true },
      { keyCode: KeyMagicVirtualKey.KeyE, label: '€', character: '€' },
      { keyCode: KeyMagicVirtualKey.KeyL, label: '£', character: '£' },
      { keyCode: KeyMagicVirtualKey.KeyY, label: '¥', character: '¥' },
      { keyCode: KeyMagicVirtualKey.KeyB, label: '•', character: '•' },
    ],
    [
      { keyCode: KeyMagicVirtualKey.OemPeriod, label: '.', character: '.' },
      { keyCode: KeyMagicVirtualKey.OemComma, label: ',', character: ',' },
      { keyCode: KeyMagicVirtualKey.Oem2, label: '?', character: '/', shiftedCharacter: '?', englishShiftedCharacter: '?', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key1, label: '!', character: '1', shiftedCharacter: '1', englishShiftedCharacter: '!', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem7, label: '\'', character: '\'' },
    ],
  ];
  private readonly burmeseNumberRows: VirtualKeyDefinition[][] = [
    [
      { keyCode: KeyMagicVirtualKey.Key1, label: '၁', character: '1' },
      { keyCode: KeyMagicVirtualKey.Key2, label: '၂', character: '2' },
      { keyCode: KeyMagicVirtualKey.Key3, label: '၃', character: '3' },
      { keyCode: KeyMagicVirtualKey.Key4, label: '၄', character: '4' },
      { keyCode: KeyMagicVirtualKey.Key5, label: '၅', character: '5' },
      { keyCode: KeyMagicVirtualKey.Key6, label: '၆', character: '6' },
      { keyCode: KeyMagicVirtualKey.Key7, label: '၇', character: '7' },
      { keyCode: KeyMagicVirtualKey.Key8, label: '၈', character: '8' },
      { keyCode: KeyMagicVirtualKey.Key9, label: '၉', character: '9' },
      { keyCode: KeyMagicVirtualKey.Key0, label: '၀', character: '0' },
    ],
    [
      { keyCode: KeyMagicVirtualKey.OemMinus, label: '-', character: '-' },
      { keyCode: KeyMagicVirtualKey.Oem2, label: '/', character: '/' },
      { keyCode: KeyMagicVirtualKey.Oem1, label: ':', character: ';', shiftedCharacter: ':', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem1, label: ';', character: ';' },
      { keyCode: KeyMagicVirtualKey.Key9, label: '(', character: '9', shiftedCharacter: '9', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key0, label: ')', character: '0', shiftedCharacter: '0', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key4, label: '$', character: '4', shiftedCharacter: '4', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key7, label: '&', character: '7', shiftedCharacter: '7', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key2, label: '@', character: '2', shiftedCharacter: '2', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem7, label: '"', character: '\'', shiftedCharacter: '"', forceShift: true },
    ],
    [
      { keyCode: KeyMagicVirtualKey.OemPeriod, label: '.', character: '.' },
      { keyCode: KeyMagicVirtualKey.OemComma, label: ',', character: ',' },
      { keyCode: KeyMagicVirtualKey.Oem2, label: '?', character: '/', shiftedCharacter: '?', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key1, label: '!', character: '1', shiftedCharacter: '1', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem7, label: '\'', character: '\'' },
    ],
  ];
  private readonly burmeseSymbolRows: VirtualKeyDefinition[][] = [
    [
      { keyCode: KeyMagicVirtualKey.Oem4, label: '[', character: '[' },
      { keyCode: KeyMagicVirtualKey.Oem6, label: ']', character: ']' },
      { keyCode: KeyMagicVirtualKey.Oem4, label: '{', character: '[', shiftedCharacter: '{', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem6, label: '}', character: ']', shiftedCharacter: '}', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key3, label: '#', character: '3', shiftedCharacter: '3', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key5, label: '%', character: '5', shiftedCharacter: '5', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key6, label: '^', character: '6', shiftedCharacter: '6', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key8, label: '*', character: '8', shiftedCharacter: '8', forceShift: true },
      { keyCode: KeyMagicVirtualKey.OemPlus, label: '+', character: '=', shiftedCharacter: '+', forceShift: true },
      { keyCode: KeyMagicVirtualKey.OemPlus, label: '=', character: '=' },
    ],
    [
      { keyCode: KeyMagicVirtualKey.OemMinus, label: '_', character: '-', shiftedCharacter: '_', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem5, label: '\\', character: '\\' },
      { keyCode: KeyMagicVirtualKey.Oem5, label: '|', character: '\\', shiftedCharacter: '|', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem3, label: '~', character: '`', shiftedCharacter: '~', forceShift: true },
      { keyCode: KeyMagicVirtualKey.OemComma, label: '<', character: ',', shiftedCharacter: '<', forceShift: true },
      { keyCode: KeyMagicVirtualKey.OemPeriod, label: '>', character: '.', shiftedCharacter: '>', forceShift: true },
      { keyCode: KeyMagicVirtualKey.KeyE, label: '€', character: 'e' },
      { keyCode: KeyMagicVirtualKey.KeyL, label: '£', character: 'l' },
      { keyCode: KeyMagicVirtualKey.KeyY, label: '¥', character: 'y' },
      { keyCode: KeyMagicVirtualKey.KeyB, label: '•', character: 'b' },
    ],
    [
      { keyCode: KeyMagicVirtualKey.OemPeriod, label: '.', character: '.' },
      { keyCode: KeyMagicVirtualKey.OemComma, label: ',', character: ',' },
      { keyCode: KeyMagicVirtualKey.Oem2, label: '?', character: '/', shiftedCharacter: '?', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Key1, label: '!', character: '1', shiftedCharacter: '1', forceShift: true },
      { keyCode: KeyMagicVirtualKey.Oem7, label: '\'', character: '\'' },
    ],
  ];

  // Complete fixed Burmese bottom rows. Normal Space is the one wide control.
  private readonly burmeseNormalBottomRow: BurmeseBottomKeyDefinition[] = [
    { kind: 'numbers', label: '123', weight: 1.20 },
    { kind: 'language', label: '🌐', weight: 1.00 },
    {
      kind: 'logical', label: '၀', weight: 1.00,
      logicalKey: { label: '၀', keyCode: KeyMagicVirtualKey.Key0, character: '0', weight: 1.00 },
    },
    { kind: 'space', label: 'space', weight: 4.30 },
    {
      kind: 'logical', label: 'ရ', weight: 1.00,
      logicalKey: withStackedConsonant('burmese-ra', {
        label: 'ရ', keyCode: KeyMagicVirtualKey.Key7, character: '7', shiftedCharacter: '7', forceShift: true, weight: 1.00,
      }),
    },
    { kind: 'enter', label: '↵', weight: 1.20 },
  ];
  private readonly burmeseShiftBottomRow: BurmeseBottomKeyDefinition[] = [
    { kind: 'numbers', label: '123', weight: 1.20 },
    { kind: 'language', label: '🌐', weight: 1.00 },
    {
      kind: 'logical', label: '္', weight: 1.00,
      logicalKey: { label: '္', keyCode: KeyMagicVirtualKey.Oem3, character: '`', weight: 1.00 },
    },
    { kind: 'space', label: 'space', weight: 4.30 },
    {
      kind: 'logical', label: '။', weight: 1.00,
      logicalKey: {
        id: 'burmese-punctuation',
        label: '။',
        keyCode: KeyMagicVirtualKey.Oem2,
        character: '/',
        weight: 1.00,
        longPressOptions: [
          {
            id: 'burmese-comma',
            label: '၊',
            actions: [
              {
                keyCode: KeyMagicVirtualKey.OemComma,
                character: ',',
              },
            ],
          },
          {
            id: 'burmese-period',
            label: '။',
            actions: [
              {
                keyCode: KeyMagicVirtualKey.Oem2,
                character: '/',
              },
            ],
          },
        ],
      },
    },
    { kind: 'enter', label: '↵', weight: 1.20 },
  ];

  private readonly onKeyboardLanguageModeChanged = (nextMode: KeyboardLanguageMode): void => {
    const previousMode = this.languageMode;
    this.languageMode = nextMode;
    if (previousMode !== nextMode) {
      this.cancelBurmeseLongPress();
      // A language switch always returns to the alphabetic screen. This keeps
      // EN deterministic even when MM was last left on its number layer.
      this.keyboardLayer = KeyboardLayer.Letters;
      const previousName = previousMode === KeyboardLanguageMode.Burmese ? 'BURMESE' : 'ENGLISH';
      const nextName = nextMode === KeyboardLanguageMode.Burmese ? 'BURMESE' : 'ENGLISH';
      hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
        'KEYBOARD UI MODE changed old=' + previousName + ' new=' + nextName);
    }
  };

  aboutToAppear(): void {
    this.loadRecentEmojis();
    setVirtualKeyboardLanguageModeListener(this.onKeyboardLanguageModeChanged);
    hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
      `HAPTIC setting loaded enabled=${this.hapticEnabled} source=panel-appear`);
  }

  aboutToDisappear(): void {
    this.cancelBurmeseLongPress();
    this.stopBackspaceRepeat();
    this.releaseBackspace();
    clearVirtualKeyboardLanguageModeListener(this.onKeyboardLanguageModeChanged);
  }

  private onKeyboardPanelVisibilityChanged(): void {
    if (this.keyboardPanelVisible !== 'true') {
      this.cancelBurmeseLongPress();
      this.hideKeyPreview();
      this.stopBackspaceRepeat();
      this.releaseBackspace();
    }
  }

  private onHapticSettingChanged(): void {
    hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
      `HAPTIC setting loaded enabled=${this.hapticEnabled} source=storage-link`);
  }

  /** The one panel-side Backspace deletion dispatch used for DOWN and repeats. */
  private deleteOnce(isRepeat: boolean = false): void {
    dispatchVirtualKeyPress({
      keyCode: KeyMagicVirtualKey.Back,
      isBackspaceRepeat: isRepeat,
      label: '⌫',
    });
  }

  private describeHapticError(error: Object): string {
    const runtimeError = error as HapticRuntimeError;
    const code = runtimeError.code === undefined ? '<none>' : `${runtimeError.code}`;
    const message = runtimeError.message === undefined ? '<none>' : runtimeError.message;
    return `code=${code} message=${message}`;
  }

  /** Logs permission and hardware effect availability once without affecting typing. */
  private logHapticCapabilityOnce(): void {
    if (this.hapticCapabilityLogged) {
      return;
    }
    this.hapticCapabilityLogged = true;
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        hilog.warn(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
          'HAPTIC capability vibratorService=unknown permissionCheck skipped hostContext=undefined');
        return;
      }
      const accessTokenId = context.applicationInfo.accessTokenId;
      const atManager = abilityAccessCtrl.createAtManager();
      const grantStatus = atManager.checkAccessTokenSync(accessTokenId, 'ohos.permission.VIBRATE' as Permissions);
      const permissionGranted = grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      let softSupported = false;
      let sharpSupported = false;
      try {
        softSupported = vibrator.isSupportEffectSync(vibrator.HapticFeedback.EFFECT_SOFT);
        sharpSupported = vibrator.isSupportEffectSync(vibrator.HapticFeedback.EFFECT_SHARP);
      } catch (effectError) {
        hilog.warn(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
          `HAPTIC effect support query failure ${this.describeHapticError(effectError)}`);
      }
      hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
        `HAPTIC capability vibratorService=available permissionDeclared=true permissionGranted=${permissionGranted} ` +
          `permissionStatus=${grantStatus} softSupported=${softSupported} sharpSupported=${sharpSupported}`);
    } catch (error) {
      hilog.warn(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
        `HAPTIC capability vibratorService=unknown permissionCheck failure ${this.describeHapticError(error)}`);
    }
  }

  /**
   * Fire-and-forget keyboard haptic. The public time effect is available from
   * API 9 and avoids silently unsupported vendor semantic effect IDs. It is
   * deliberately short and never waits on the input path.
   */
  private triggerHaptic(kind: 'tap' | 'longPress' = 'tap'): void {
    if (!this.hapticEnabled) {
      hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
        `HAPTIC keypress skipped settingEnabled=false kind=${kind}`);
      return;
    }
    this.logHapticCapabilityOnce();
    const duration = kind === 'longPress' ? HAPTIC_LONG_PRESS_DURATION_MS : HAPTIC_TAP_DURATION_MS;
    hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
      `HAPTIC keypress requested effect=time durationMs=${duration} kind=${kind}`);
    try {
      hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
        `HAPTIC API begin type=time durationMs=${duration} usage=touch`);
      void vibrator.startVibration({ type: 'time', duration }, { usage: 'touch' }).then((): void => {
        hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
          `HAPTIC API success type=time durationMs=${duration}`);
      }).catch((error: Object): void => {
        hilog.warn(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
          `HAPTIC API failure type=time durationMs=${duration} ${this.describeHapticError(error)}`);
      });
    } catch (error) {
      hilog.warn(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
        `HAPTIC API failure type=time durationMs=${duration} ${this.describeHapticError(error)}`);
    }
  }

  /** Tells the transport queue that no coalesced hold-repeat delete may follow UP/CANCEL. */
  private releaseBackspace(): void {
    dispatchVirtualKeyPress({
      keyCode: KeyMagicVirtualKey.Back,
      command: VirtualKeyboardCommand.BackspaceRelease,
      label: '⌫ release',
    });
  }

  private handleBackspaceTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      if (this.backspacePressed) {
        return;
      }
      this.backspacePressed = true;
      hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s', 'BACKSPACE DOWN');
      // Only DOWN haptics: hold-repeat remains deliberately silent.
      this.triggerHaptic();
      this.deleteOnce();
      this.backspaceInitialTimer = setTimeout((): void => {
        this.backspaceInitialTimer = -1;
        if (!this.backspacePressed) {
          return;
        }
        hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s', 'BACKSPACE repeat start');
        this.sendBackspaceRepeatTick();
        this.backspaceRepeatTimer = setInterval((): void => {
          this.sendBackspaceRepeatTick();
        }, 65);
      }, 400);
      return;
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
        event.type === TouchType.Up ? 'BACKSPACE UP' : 'BACKSPACE CANCEL');
      this.stopBackspaceRepeat();
      this.releaseBackspace();
    }
  }

  private sendBackspaceRepeatTick(): void {
    if (!this.backspacePressed) {
      return;
    }
    hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s', 'BACKSPACE repeat tick');
    this.deleteOnce(true);
  }

  private stopBackspaceRepeat(): void {
    const shouldLogStop = this.backspacePressed || this.backspaceInitialTimer !== -1 || this.backspaceRepeatTimer !== -1;
    this.backspacePressed = false;
    if (this.backspaceInitialTimer !== -1) {
      clearTimeout(this.backspaceInitialTimer);
      this.backspaceInitialTimer = -1;
    }
    if (this.backspaceRepeatTimer !== -1) {
      clearInterval(this.backspaceRepeatTimer);
      this.backspaceRepeatTimer = -1;
    }
    if (shouldLogStop) {
      hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s', 'BACKSPACE repeat stop');
    }
  }

  private numericLength(value: Length | undefined): number {
    if (value === undefined) {
      return 0;
    }
    return typeof value === 'number' ? value : Number.parseFloat(`${value}`);
  }

  private recordKeyboardPageArea(_previous: Area, next: Area): void {
    this.keyboardPageGlobalLeft = this.numericLength(next.globalPosition.x);
    this.keyboardPageGlobalTop = this.numericLength(next.globalPosition.y);
    this.keyboardPageWidth = this.numericLength(next.width);
    this.keyboardPageHeight = this.numericLength(next.height);
    hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
      `HEIGHT root/content measured width=${this.keyboardPageWidth} height=${this.keyboardPageHeight}`);
  }

  private recordKeyPreviewAnchor(keyId: string, area: Area): void {
    this.keyPreviewAnchors.set(keyId, {
      globalLeft: this.numericLength(area.globalPosition.x),
      globalTop: this.numericLength(area.globalPosition.y),
      width: this.numericLength(area.width),
      height: this.numericLength(area.height),
    });
  }

  private recordLongPressAnchor(key: VirtualKeyDefinition, area: Area): void {
    if (key.id === undefined) {
      return;
    }
    this.longPressAnchors.set(key.id, {
      globalLeft: this.numericLength(area.globalPosition.x),
      globalTop: this.numericLength(area.globalPosition.y),
      width: this.numericLength(area.width),
      height: this.numericLength(area.height),
    });
  }

  private clampPreviewSize(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, Math.round(value)));
  }

  /** Keeps multi-codepoint Myanmar labels readable without inflating the bubble. */
  private previewBurmeseFontSize(label: string): number {
    const codePointCount = Array.from(label).length;
    if (codePointCount >= 4) {
      return 22;
    }
    if (codePointCount >= 3) {
      return 24;
    }
    return KEY_PREVIEW_BURMESE_FONT_SIZE;
  }

  /** Shows a visual-only character bubble. It never dispatches input. */
  private showKeyPreview(key: VirtualKeyDefinition, keyId: string): void {
    if (!this.keyPreviewEnabled || this.longPressPopupVisible || this.keyboardPageWidth <= 0) {
      return;
    }
    const anchor = this.keyPreviewAnchors.get(keyId);
    if (anchor === undefined) {
      return;
    }
    const isBurmese = this.isBurmeseMode();
    const previewWidth = this.clampPreviewSize(
      anchor.width * KEY_PREVIEW_WIDTH_RATIO,
      KEY_PREVIEW_MIN_WIDTH,
      KEY_PREVIEW_MAX_WIDTH,
    );
    const previewHeight = this.clampPreviewSize(
      anchor.height * KEY_PREVIEW_HEIGHT_RATIO,
      KEY_PREVIEW_MIN_HEIGHT,
      KEY_PREVIEW_MAX_HEIGHT,
    );
    const sourceLeft = anchor.globalLeft - this.keyboardPageGlobalLeft;
    const sourceTop = anchor.globalTop - this.keyboardPageGlobalTop;
    const desiredLeft = sourceLeft + (anchor.width - previewWidth) / 2;
    const maximumLeft = Math.max(KEY_PREVIEW_EDGE_MARGIN, this.keyboardPageWidth - previewWidth - KEY_PREVIEW_EDGE_MARGIN);
    this.keyPreviewLeft = Math.max(KEY_PREVIEW_EDGE_MARGIN, Math.min(desiredLeft, maximumLeft));
    this.keyPreviewTop = Math.max(KEY_PREVIEW_EDGE_MARGIN, sourceTop - previewHeight - KEY_PREVIEW_GAP);
    this.keyPreviewLabel = this.keyLabel(key);
    this.keyPreviewIsBurmese = isBurmese;
    this.keyPreviewWidth = previewWidth;
    this.keyPreviewHeight = previewHeight;
    this.keyPreviewFontSize = isBurmese ? this.previewBurmeseFontSize(this.keyPreviewLabel) : KEY_PREVIEW_ENGLISH_FONT_SIZE;
    this.keyPreviewLineHeight = isBurmese ? KEY_PREVIEW_BURMESE_LINE_HEIGHT : KEY_PREVIEW_ENGLISH_LINE_HEIGHT;
    this.keyPreviewVisible = true;
  }

  private hideKeyPreview(): void {
    this.keyPreviewVisible = false;
    this.keyPreviewLabel = '';
  }

  /** Normal character-key interaction: preview/haptic on DOWN, input on UP. */
  private handleLogicalKeyTouch(key: VirtualKeyDefinition, keyId: string, event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.triggerHaptic();
      this.showKeyPreview(key, keyId);
      return;
    }
    if (event.type === TouchType.Up) {
      this.hideKeyPreview();
      this.sendKey(key, false);
      return;
    }
    if (event.type === TouchType.Cancel) {
      this.hideKeyPreview();
    }
  }

  private isBurmeseLongPressEnabled(key: VirtualKeyDefinition): boolean {
    return this.isBurmeseMode() && this.isLettersLayer() && key.longPressOptions !== undefined &&
      key.longPressOptions.length > 0 && key.id !== undefined;
  }

  private touchPoint(event: TouchEvent): TouchObject | undefined {
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0];
    }
    return event.touches.length > 0 ? event.touches[0] : undefined;
  }

  private stopBurmeseLongPressTimer(): void {
    if (this.longPressTimer !== -1) {
      clearTimeout(this.longPressTimer);
      this.longPressTimer = -1;
    }
  }

  /** Closes the page-local overlay and prevents any delayed normal-key dispatch. */
  private cancelBurmeseLongPress(): void {
    this.stopBurmeseLongPressTimer();
    this.longPressTouchActive = false;
    this.longPressTriggered = false;
    this.longPressSelectionMoved = false;
    this.longPressKey = undefined;
    this.longPressOptions = [];
    this.longPressPopupVisible = false;
    this.longPressHighlightedOptionIndex = -1;
    this.hideKeyPreview();
  }

  private showBurmeseLongPressPopup(key: VirtualKeyDefinition): void {
    if (key.id === undefined || key.longPressOptions === undefined) {
      return;
    }
    const anchor = this.longPressAnchors.get(key.id);
    if (anchor === undefined || this.keyboardPageWidth <= 0) {
      hilog.warn(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
        'BURMESE LONG PRESS popup skipped: source geometry is unavailable.');
      return;
    }
    const popupWidth = key.longPressOptions.length * BURMESE_POPUP_OPTION_WIDTH +
      Math.max(0, key.longPressOptions.length - 1) * BURMESE_POPUP_GAP;
    const sourceLeft = anchor.globalLeft - this.keyboardPageGlobalLeft;
    const sourceTop = anchor.globalTop - this.keyboardPageGlobalTop;
    const desiredLeft = sourceLeft + (anchor.width - popupWidth) / 2;
    const maximumLeft = Math.max(BURMESE_POPUP_EDGE_MARGIN,
      this.keyboardPageWidth - popupWidth - BURMESE_POPUP_EDGE_MARGIN);
    this.longPressPopupLeft = Math.max(BURMESE_POPUP_EDGE_MARGIN, Math.min(desiredLeft, maximumLeft));
    this.longPressPopupTop = Math.max(BURMESE_POPUP_EDGE_MARGIN,
      sourceTop - BURMESE_POPUP_HEIGHT - BURMESE_POPUP_GAP);
    // The normal preview must never overlap the alternate popup.
    this.hideKeyPreview();
    this.longPressOptions = key.longPressOptions;
    // A hold-and-release selects the first option. Moving into or away from the
    // popup then changes this highlight, enabling safe drag-away cancellation.
    this.longPressHighlightedOptionIndex = 0;
    this.longPressPopupVisible = true;
    hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
      'BURMESE LONG PRESS popup shown key=' + key.label + ' optionCount=' + key.longPressOptions.length);
  }

  private updateBurmeseLongPressHighlight(touch: TouchObject): void {
    if (!this.longPressPopupVisible) {
      return;
    }
    const localX = touch.windowX - this.keyboardPageGlobalLeft;
    const localY = touch.windowY - this.keyboardPageGlobalTop;
    const popupWidth = this.longPressOptions.length * BURMESE_POPUP_OPTION_WIDTH +
      Math.max(0, this.longPressOptions.length - 1) * BURMESE_POPUP_GAP;
    let index = -1;
    if (localX >= this.longPressPopupLeft && localX <= this.longPressPopupLeft + popupWidth &&
      localY >= this.longPressPopupTop && localY <= this.longPressPopupTop + BURMESE_POPUP_HEIGHT) {
      index = Math.floor((localX - this.longPressPopupLeft) /
        (BURMESE_POPUP_OPTION_WIDTH + BURMESE_POPUP_GAP));
      if (index < 0 || index >= this.longPressOptions.length) {
        index = -1;
      }
    }
    if (this.longPressOptions.length === 1 && this.longPressKey !== undefined && this.longPressKey.id !== undefined) {
      const source = this.longPressAnchors.get(this.longPressKey.id);
      const insideExpandedPopup = localX >= this.longPressPopupLeft - BURMESE_LONG_PRESS_CANCEL_SLOP &&
        localX <= this.longPressPopupLeft + popupWidth + BURMESE_LONG_PRESS_CANCEL_SLOP &&
        localY >= this.longPressPopupTop - BURMESE_LONG_PRESS_CANCEL_SLOP &&
        localY <= this.longPressPopupTop + BURMESE_POPUP_HEIGHT + BURMESE_LONG_PRESS_CANCEL_SLOP;
      const sourceLeft = source === undefined ? 0 : source.globalLeft - this.keyboardPageGlobalLeft;
      const sourceTop = source === undefined ? 0 : source.globalTop - this.keyboardPageGlobalTop;
      const insideExpandedSource = source !== undefined &&
        localX >= sourceLeft - BURMESE_LONG_PRESS_CANCEL_SLOP &&
        localX <= sourceLeft + source.width + BURMESE_LONG_PRESS_CANCEL_SLOP &&
        localY >= sourceTop - BURMESE_LONG_PRESS_CANCEL_SLOP &&
        localY <= sourceTop + source.height + BURMESE_LONG_PRESS_CANCEL_SLOP;
      // A single option stays selected through natural finger jitter. Only a
      // deliberate movement away from both the source and popup cancels it.
      index = insideExpandedPopup || insideExpandedSource ? 0 : -1;
    }
    this.longPressHighlightedOptionIndex = index;
  }

  private dispatchBurmeseLongPressOption(option: PopupKeyOption): void {
    this.cancelBurmeseLongPress();
    option.actions.forEach((action: KeyMagicActionDefinition, index: number): void => {
      dispatchVirtualKeyPress({
        keyCode: action.keyCode,
        character: action.character,
        shiftedCharacter: action.shiftedCharacter,
        forceShift: action.forceShift,
        // The popup is a static Burmese-letter alternative. Preserve its
        // visible layer while each action enters the same KeyMagic pipeline.
        ignoreVirtualShift: true,
        preserveVirtualShift: true,
        label: `Long press ${option.label}: KeyMagic action ${index + 1}`,
      });
    });
    hilog.info(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
      'BURMESE LONG PRESS selected option=' + option.label + ' actionCount=' + option.actions.length);
  }

  private handleBurmeseLongPressTouch(key: VirtualKeyDefinition, keyId: string, event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.cancelBurmeseLongPress();
      this.triggerHaptic();
      this.showKeyPreview(key, keyId);
      this.longPressTouchActive = true;
      this.longPressKey = key;
      this.longPressTimer = setTimeout((): void => {
        this.longPressTimer = -1;
        if (!this.longPressTouchActive || this.longPressKey !== key || !this.isBurmeseLongPressEnabled(key)) {
          return;
        }
        this.longPressTriggered = true;
        this.triggerHaptic('longPress');
        this.showBurmeseLongPressPopup(key);
      }, BURMESE_LONG_PRESS_DELAY_MS);
      return;
    }

    if (event.type === TouchType.Move && this.longPressTriggered) {
      this.longPressSelectionMoved = true;
      const touch = this.touchPoint(event);
      if (touch !== undefined) {
        this.updateBurmeseLongPressHighlight(touch);
      }
      return;
    }

    if (event.type === TouchType.Up) {
      this.stopBurmeseLongPressTimer();
      if (!this.longPressTouchActive || this.longPressKey !== key) {
        return;
      }
      if (!this.longPressTriggered) {
        this.cancelBurmeseLongPress();
        this.sendKey(key, false);
        return;
      }
      if (this.longPressSelectionMoved) {
        const touch = this.touchPoint(event);
        if (touch !== undefined) {
          this.updateBurmeseLongPressHighlight(touch);
        }
      }
      const selectedIndex = this.longPressHighlightedOptionIndex;
      const selected = selectedIndex >= 0 && selectedIndex < this.longPressOptions.length ?
        this.longPressOptions[selectedIndex] : undefined;
      if (selected === undefined) {
        this.cancelBurmeseLongPress();
      } else {
        this.dispatchBurmeseLongPressOption(selected);
      }
      return;
    }

    if (event.type === TouchType.Cancel) {
      this.cancelBurmeseLongPress();
    }
  }

  private isBurmeseMode(): boolean {
    return this.languageMode === KeyboardLanguageMode.Burmese;
  }

  /** Existing controller-published composition presentation, never a second buffer. */
  private shouldShowBurmeseCompositionPopup(): boolean {
    return this.isBurmeseMode() && this.compositionPopupVisible === 'true' && this.composition.length > 0;
  }

  private isDarkMode(): boolean {
    if (this.keyboardTheme === 'dark') {
      return true;
    }
    if (this.keyboardTheme === 'light') {
      return false;
    }
    // System mode preserves the controller-published HarmonyOS color mode.
    return this.colorMode === 'dark';
  }

  private isShiftActive(): boolean {
    return this.shiftActive === 'true';
  }

  private isLettersLayer(): boolean {
    return this.keyboardLayer === KeyboardLayer.Letters;
  }

  private isNumbersLayer(): boolean {
    return this.keyboardLayer === KeyboardLayer.Numbers;
  }

  private isEmojiLayer(): boolean {
    return this.keyboardLayer === KeyboardLayer.Emoji;
  }

  private panelColor(): string {
    return this.isDarkMode() ? '#151617' : '#E7EAED';
  }

  private keyColor(): string {
    return this.isDarkMode() ? '#303235' : '#FFFFFF';
  }

  private commandKeyColor(): string {
    return this.isDarkMode() ? '#25272A' : '#D4D9DF';
  }

  private accentColor(): string {
    return this.isDarkMode() ? '#3D7EBF' : '#2D75BD';
  }

  private textColor(): string {
    return this.isDarkMode() ? '#F5F6F7' : '#1C1E20';
  }

  private secondaryTextColor(): string {
    return this.isDarkMode() ? '#C2C7CD' : '#58616C';
  }

  private keyGap(): number {
    // Every Myanmar page uses this same compact gap. Together with its
    // permanent composition strip this gives normal, Shift, number, and symbol
    // pages the identical four-row Burmese key height.
    return this.isBurmeseMode() ? 4 : 6;
  }

  private commandKeyWeight(): number {
    return this.isBurmeseMode() ? 1.32 : 1.25;
  }

  /** The shared iOS-style number/symbol template has English command widths. */
  private nonLetterCommandKeyWeight(): number {
    return 1.25;
  }

  private keyLabel(key: VirtualKeyDefinition): string {
    if (this.isBurmeseMode()) {
      return key.label;
    }
    if (this.isLettersLayer() && this.isShiftActive() && key.englishShiftedLabel !== undefined) {
      return key.englishShiftedLabel;
    }
    return key.englishLabel === undefined ? key.label : key.englishLabel;
  }

  /**
   * A fixed, always-mounted Myanmar composition area. Its dimensions are never
   * derived from composition text: updates replace only the one-line label.
   */
  @Builder
  private buildBurmeseCompositionStrip() {
    Row({ space: 6 }) {
      Text(this.isEmojiLayer() ? this.selectedEmojiCategory().label :
        (this.shouldShowBurmeseCompositionPopup() ? this.composition : ''))
        .fontSize(18)
        .lineHeight(34)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.textColor())
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 8, right: 8 })
        .layoutWeight(1)
      if (!this.isEmojiLayer()) {
        Button() {
          Text('😀')
            .width('100%')
            .fontSize(24)
            .lineHeight(34)
            .textAlign(TextAlign.Center)
        }
        .id('MM-composition-emoji')
        .width(48)
        .height(38)
        .padding({ left: 0, right: 0, top: 0, bottom: 0 })
        .backgroundColor(this.commandKeyColor())
        .borderRadius(9)
        .onClick(() => this.switchKeyboardLayer(KeyboardLayer.Emoji, 'emoji'))
      }
    }
    .width('100%')
    .height(BURMESE_COMPOSITION_STRIP_HEIGHT)
    .padding({ left: 4, right: 4 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.isDarkMode() ? '#1E2022' : '#DEE3E8')
    .borderRadius(8)
  }

  /**
   * English retains the existing header footprint without any visible product
   * label. Its sole action opens the shared Emoji layer used by Burmese too.
   */
  @Builder
  private buildEnglishHeaderStrip() {
    Row({ space: 6 }) {
      if (this.isEmojiLayer()) {
        Text(this.selectedEmojiCategory().label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.secondaryTextColor())
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
      } else {
        // Preserve the header geometry while deliberately rendering no text.
        Text('')
          .layoutWeight(1)
      }
      if (!this.isEmojiLayer()) {
        Button() {
          Text('😀')
            .width('100%')
            .fontSize(24)
            .lineHeight(34)
            .textAlign(TextAlign.Center)
        }
        .id('EN-header-emoji')
        .width(48)
        .height(34)
        .padding({ left: 0, right: 0, top: 0, bottom: 0 })
        .backgroundColor(this.commandKeyColor())
        .borderRadius(8)
        .onClick(() => this.switchKeyboardLayer(KeyboardLayer.Emoji, 'emoji'))
      }
    }
    .width('100%')
    .height(34)
    .padding({ left: 4, right: 4 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.isDarkMode() ? '#1E2022' : '#DEE3E8')
    .borderRadius(8)
  }

  private sendKey(key: VirtualKeyDefinition, triggerFeedback: boolean = true): void {
    if (triggerFeedback) {
      this.triggerHaptic();
    }
    if (key.prefixActions !== undefined) {
      key.prefixActions.forEach((action: KeyMagicActionDefinition, index: number): void => {
        dispatchVirtualKeyPress({
          keyCode: action.keyCode,
          character: action.character,
          shiftedCharacter: action.shiftedCharacter,
          forceShift: action.forceShift,
          // Burmese Shift selects a visible static layer. A state selector must
          // retain that UI state until its paired physical action consumes it.
          ignoreVirtualShift: true,
          preserveVirtualShift: true,
          label: `${key.label}: KeyMagic state ${index + 1}`,
        });
      });
    }
    dispatchVirtualKeyPress({
      keyCode: key.keyCode,
      character: key.character,
      shiftedCharacter: key.shiftedCharacter,
      englishShiftedCharacter: key.englishShiftedCharacter,
      forceShift: key.forceShift,
      // All Burmese labels select their explicitly declared KeyMagic identity.
      // The panel Shift changes only which fixed UI layer is visible.
      ignoreVirtualShift: this.isBurmeseMode(),
      label: this.keyLabel(key),
    });
  }

  private sendShift(): void {
    this.cancelBurmeseLongPress();
    this.triggerHaptic();
    dispatchVirtualKeyPress({ keyCode: KeyMagicVirtualKey.Shift, label: 'Shift' });
  }

  private toggleLanguage(): void {
    this.cancelBurmeseLongPress();
    this.triggerHaptic();
    dispatchVirtualKeyPress({
      keyCode: KeyMagicVirtualKey.Space,
      command: VirtualKeyboardCommand.ToggleLanguage,
      label: this.isBurmeseMode() ? 'မြန်မာ' : 'EN',
    });
  }

  /** Changes a visible layer only after the controller applies its established composition boundary. */
  private switchKeyboardLayer(targetLayer: KeyboardLayer, label: string): void {
    this.cancelBurmeseLongPress();
    if (this.keyboardLayer === targetLayer) {
      return;
    }
    this.triggerHaptic();
    dispatchVirtualKeyPress({
      keyCode: KeyMagicVirtualKey.Space,
      command: VirtualKeyboardCommand.CommitComposition,
      label: `keyboard layer ${label}`,
    });
    this.keyboardLayer = targetLayer;
  }

  private selectedEmojiCategory(): EmojiCategory {
    return emojiCategoryById(this.selectedEmojiCategoryId);
  }

  private selectedEmojiItems(): string[] {
    return this.selectedEmojiCategoryId === 'recent' ? this.recentEmojis :
      this.selectedEmojiCategory().emojis;
  }

  private selectEmojiCategory(categoryId: EmojiCategoryId): void {
    this.selectedEmojiCategoryId = categoryId;
  }

  private loadRecentEmojis(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      this.recentEmojis = EmojiRecentSettings.read(context);
    } catch (error) {
      this.recentEmojis = [];
      hilog.warn(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
        `EMOJI recent read failed error=${JSON.stringify(error)}`);
    }
  }

  /** Updates the panel instantly, then persists the small local MRU list after the touch callback. */
  private recordRecentEmoji(emoji: string): void {
    const next: string[] = [emoji];
    this.recentEmojis.forEach((candidate: string): void => {
      if (candidate !== emoji && next.length < EMOJI_RECENT_LIMIT) {
        next.push(candidate);
      }
    });
    this.recentEmojis = next;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    setTimeout((): void => {
      try {
        EmojiRecentSettings.write(context, next);
      } catch (error) {
        hilog.warn(KEYBOARD_UI_LOG_DOMAIN, KEYBOARD_UI_LOG_TAG, '%{public}s',
          `EMOJI recent write failed error=${JSON.stringify(error)}`);
      }
    }, 0);
  }

  /** Emoji has no KeyMagic identity; the controller queues it through the deferred editor FIFO. */
  private sendEmoji(emoji: string): void {
    this.cancelBurmeseLongPress();
    this.triggerHaptic();
    this.recordRecentEmoji(emoji);
    dispatchVirtualKeyPress({
      keyCode: KeyMagicVirtualKey.Space,
      character: emoji,
      command: VirtualKeyboardCommand.InsertEmoji,
      label: 'emoji',
    });
  }

  private bottomPunctuation(): VirtualKeyDefinition {
    return {
      keyCode: KeyMagicVirtualKey.OemComma,
      label: ',',
      character: ',',
      shiftedCharacter: '<',
      englishShiftedCharacter: '<',
      weight: 0.85,
    };
  }

  /** The English footer period remains a plain ASCII U+002E virtual key. */
  private bottomPeriod(): VirtualKeyDefinition {
    return {
      keyCode: KeyMagicVirtualKey.OemPeriod,
      label: '.',
      character: '.',
      shiftedCharacter: '>',
      englishShiftedCharacter: '>',
      weight: 0.85,
    };
  }

  @Builder
  private buildBurmeseKeyLabel(label: string) {
    Text(label)
      .width('100%')
      .fontSize(this.burmeseKeyFontSize(label))
      // Myanmar clusters use a generous, fixed line box. The small, uniform
      // top/bottom imbalance shifts the optical center down without any
      // per-glyph transform or character-specific exception.
      .lineHeight(BURMESE_KEY_LINE_HEIGHT)
      .fontColor(this.textColor())
      .textAlign(TextAlign.Center)
  }

  /** Reserve extra room for stacked labels without making ordinary Myanmar keys heavy. */
  private burmeseKeyFontSize(label: string): number {
    const codePointCount = Array.from(label).length;
    if (codePointCount >= 3) {
      return 18;
    }
    if (codePointCount === 2) {
      return 19;
    }
    return BURMESE_KEY_FONT_SIZE;
  }

  /** English letters need a slightly larger label than numbers and punctuation. */
  private nonBurmeseKeyFontSize(label: string, isSpecial: boolean): number {
    if (isSpecial) {
      return 23;
    }
    if (label.length === 1) {
      const codePoint = label.charCodeAt(0);
      if ((codePoint >= 65 && codePoint <= 90) || (codePoint >= 97 && codePoint <= 122)) {
        return 20;
      }
    }
    return 16;
  }

  @Builder
  private buildKeyLabel(label: string, isBurmese: boolean, isSpecial: boolean = false) {
    Column() {
      if (isBurmese && !isSpecial) {
        this.buildBurmeseKeyLabel(label)
      } else {
        Text(label)
          .width('100%')
          .fontSize(this.nonBurmeseKeyFontSize(label, isSpecial))
          .lineHeight(isSpecial ? 34 : 30)
          .fontColor(this.textColor())
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(isBurmese && !isSpecial ? {
      left: 2,
      right: 2,
      top: BURMESE_KEY_OPTICAL_TOP_PADDING,
      bottom: BURMESE_KEY_OPTICAL_BOTTOM_PADDING,
    } : { left: 2, right: 2, top: 4, bottom: 4 })
  }

  @Builder
  private buildLogicalKey(key: VirtualKeyDefinition, keyId: string) {
    if (this.isBurmeseLongPressEnabled(key)) {
      Button() {
        this.buildKeyLabel(this.keyLabel(key), true)
      }
      .id(keyId)
      .layoutWeight(key.weight === undefined ? 1 : key.weight)
      .height('100%')
      .padding({ left: 0, right: 0, top: 0, bottom: 0 })
      .backgroundColor(this.keyColor())
      .borderRadius(9)
      .onAreaChange((_previous: Area, next: Area) => {
        this.recordLongPressAnchor(key, next);
        this.recordKeyPreviewAnchor(keyId, next);
      })
      .onTouch((event: TouchEvent) => this.handleBurmeseLongPressTouch(key, keyId, event))
    } else {
      Button() {
        this.buildKeyLabel(this.keyLabel(key), this.isBurmeseMode())
      }
      .id(keyId)
      .layoutWeight(key.weight === undefined ? 1 : key.weight)
      .height('100%')
      .padding({ left: 0, right: 0, top: 0, bottom: 0 })
      .backgroundColor(this.keyColor())
      .borderRadius(9)
      .onAreaChange((_previous: Area, next: Area) => this.recordKeyPreviewAnchor(keyId, next))
      .onTouch((event: TouchEvent) => this.handleLogicalKeyTouch(key, keyId, event))
    }
  }

  @Builder
  private buildLogicalRow(keys: VirtualKeyDefinition[], rowId: string) {
    Row({ space: this.keyGap() }) {
      ForEach(keys, (key: VirtualKeyDefinition, index: number) => {
        this.buildLogicalKey(key, `${rowId}-${index}-${key.keyCode}`)
      }, (key: VirtualKeyDefinition, index: number): string => `${rowId}-${index}-${key.keyCode}-${key.label}`)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private buildLetterThirdRow(keys: VirtualKeyDefinition[], rowId: string) {
    Row({ space: this.keyGap() }) {
      Button() {
        this.buildKeyLabel('⇧', false, true)
      }
      .id(`${rowId}-shift`)
      .layoutWeight(this.commandKeyWeight())
      .height('100%')
      .padding({ left: 0, right: 0, top: 0, bottom: 0 })
      .backgroundColor(this.isShiftActive() ? this.accentColor() : this.commandKeyColor())
      .borderRadius(9)
      .onClick(() => this.sendShift())
      ForEach(keys, (key: VirtualKeyDefinition, index: number) => {
        this.buildLogicalKey(key, `${rowId}-${index}-${key.keyCode}`)
      }, (key: VirtualKeyDefinition, index: number): string => `${rowId}-${index}-${key.keyCode}-${key.label}`)
      Button() {
        this.buildKeyLabel('⌫', false, true)
      }
      .id(`${rowId}-backspace`)
      .layoutWeight(this.commandKeyWeight())
      .height('100%')
      .padding({ left: 0, right: 0, top: 0, bottom: 0 })
      .backgroundColor(this.commandKeyColor())
      .borderRadius(9)
      .onTouch((event: TouchEvent) => this.handleBackspaceTouch(event))
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private buildLayerSwitchKey(label: string, weight: number, keyId: string, targetLayer: KeyboardLayer) {
    Button() {
      this.buildKeyLabel(label, false, true)
    }
    .id(keyId)
    .layoutWeight(weight)
    .height('100%')
    .padding({ left: 0, right: 0, top: 0, bottom: 0 })
    .backgroundColor(this.commandKeyColor())
    .borderRadius(9)
    .onClick(() => this.switchKeyboardLayer(targetLayer, label))
  }

  /** iOS-style non-letter third row: selector on the left, existing Backspace on the right. */
  @Builder
  private buildNonLetterThirdRow(
    keys: VirtualKeyDefinition[],
    rowId: string,
    selectorLabel: string,
    selectorTarget: KeyboardLayer,
  ) {
    Row({ space: this.keyGap() }) {
      this.buildLayerSwitchKey(selectorLabel, this.nonLetterCommandKeyWeight(), `${rowId}-selector`, selectorTarget)
      ForEach(keys, (key: VirtualKeyDefinition, index: number) => {
        this.buildLogicalKey(key, `${rowId}-${index}-${key.keyCode}`)
      }, (key: VirtualKeyDefinition, index: number): string => `${rowId}-${index}-${key.keyCode}-${key.label}`)
      Button() {
        this.buildKeyLabel('⌫', false, true)
      }
      .id(`${rowId}-backspace`)
      .layoutWeight(this.nonLetterCommandKeyWeight())
      .height('100%')
      .padding({ left: 0, right: 0, top: 0, bottom: 0 })
      .backgroundColor(this.commandKeyColor())
      .borderRadius(9)
      // Keep all number/symbol Backspace presses on the existing tap and
      // hold-repeat implementation used by the letter screen.
      .onTouch((event: TouchEvent) => this.handleBackspaceTouch(event))
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private buildToggleNumbersKey(weight: number, keyId: string) {
    Button() {
      this.buildKeyLabel(this.isLettersLayer() ? '123' : 'ABC', false, true)
    }
    .id(keyId)
    .layoutWeight(weight)
    .height('100%')
    .padding({ left: 0, right: 0, top: 0, bottom: 0 })
    .backgroundColor(this.commandKeyColor())
    .borderRadius(9)
    .onClick(() => this.switchKeyboardLayer(
      this.isLettersLayer() ? KeyboardLayer.Numbers : KeyboardLayer.Letters,
      this.isLettersLayer() ? '123' : 'ABC',
    ))
  }

  @Builder
  private buildGlobeKey(weight: number, keyId: string) {
    Button() {
      this.buildKeyLabel('🌐', false, true)
    }
    .id(keyId)
    .layoutWeight(weight)
    .height('100%')
    .padding({ left: 0, right: 0, top: 0, bottom: 0 })
    // Globe is an action, not a selected-language indicator. Keep its
    // resting visual exactly the same in English and Burmese.
    .backgroundColor(this.commandKeyColor())
    .borderRadius(9)
    .onClick(() => this.toggleLanguage())
  }

  @Builder
  private buildSpaceKey(label: string, weight: number, keyId: string) {
    Button() {
      this.buildKeyLabel(label, this.isBurmeseMode(), true)
    }
    .id(keyId)
    .layoutWeight(weight)
    .height('100%')
    .padding({ left: 0, right: 0, top: 0, bottom: 0 })
    .backgroundColor(this.keyColor())
    .borderRadius(9)
    .onClick(() => this.sendKey({ keyCode: KeyMagicVirtualKey.Space, label: label, character: ' ' }))
  }

  @Builder
  private buildEnterKey(weight: number, keyId: string) {
    Button() {
      this.buildKeyLabel('↵', false, true)
    }
    .id(keyId)
    .layoutWeight(weight)
    .height('100%')
    .padding({ left: 0, right: 0, top: 0, bottom: 0 })
    .backgroundColor(this.commandKeyColor())
    .borderRadius(9)
    .onClick(() => this.sendKey({ keyCode: KeyMagicVirtualKey.Return, label: '↵' }))
  }

  @Builder
  private buildBurmeseBottomKey(key: BurmeseBottomKeyDefinition, keyId: string) {
    if (key.kind === 'numbers') {
      this.buildToggleNumbersKey(key.weight, keyId)
    } else if (key.kind === 'language') {
      this.buildGlobeKey(key.weight, keyId)
    } else if (key.kind === 'logical' && key.logicalKey !== undefined) {
      this.buildLogicalKey(key.logicalKey, keyId)
    } else if (key.kind === 'space') {
      this.buildSpaceKey(key.label, key.weight, keyId)
    } else {
      this.buildEnterKey(key.weight, keyId)
    }
  }

  @Builder
  private buildBurmeseBottomRow() {
    Row({ space: this.keyGap() }) {
      ForEach(this.burmeseBottomRow(), (key: BurmeseBottomKeyDefinition, index: number) => {
        this.buildBurmeseBottomKey(key, `${this.burmeseBottomRowId()}-${index}-${key.kind}`)
      }, (key: BurmeseBottomKeyDefinition, index: number): string =>
      `${this.burmeseBottomRowId()}-${index}-${key.kind}-${key.label}`)
    }
    .width('100%')
    .layoutWeight(1)
  }

  private burmeseBottomRow(): BurmeseBottomKeyDefinition[] {
    return this.isShiftActive() ? this.burmeseShiftBottomRow : this.burmeseNormalBottomRow;
  }

  private burmeseBottomRowId(): string {
    // The normal row removed two entries; force a fresh six-control tree.
    return this.isShiftActive() ? 'MM-shift-bottom-v3' : 'MM-normal-bottom-v3';
  }

  @Builder
  private buildEnglishBottomRow() {
    Row({ space: 6 }) {
      this.buildToggleNumbersKey(1.2, 'EN-bottom-numbers')
      this.buildGlobeKey(1.35, 'EN-bottom-globe')
      this.buildLogicalKey(this.bottomPunctuation(), 'EN-bottom-punctuation')
      this.buildSpaceKey('space', 3.7, 'EN-bottom-space')
      this.buildLogicalKey(this.bottomPeriod(), 'EN-bottom-period')
      this.buildEnterKey(1.25, 'EN-bottom-enter')
    }
    .width('100%')
    .layoutWeight(1)
  }

  /** Numbers and symbols share the compact iOS-style ABC / globe / space / return footer. */
  @Builder
  private buildNonLetterBottomRow() {
    Row({ space: this.keyGap() }) {
      this.buildToggleNumbersKey(1.35, 'layer-bottom-letters')
      this.buildGlobeKey(1.15, 'layer-bottom-globe')
      this.buildSpaceKey('space', 4.80, 'layer-bottom-space')
      this.buildEnterKey(1.45, 'layer-bottom-enter')
    }
    .width('100%')
    .layoutWeight(1)
  }

  /** Compact horizontally-scrollable selector; only one category grid is built at a time. */
  @Builder
  private buildEmojiCategorySelector() {
    Scroll() {
      Row({ space: 5 }) {
        ForEach(EMOJI_CATEGORIES, (category: EmojiCategory) => {
          Button() {
            Text(category.icon)
              .width('100%')
              .fontSize(20)
              .lineHeight(28)
              .textAlign(TextAlign.Center)
          }
          .id(`emoji-category-${category.id}`)
          .width(38)
          .height(32)
          .padding({ left: 0, right: 0, top: 0, bottom: 0 })
          .backgroundColor(this.selectedEmojiCategoryId === category.id ? this.accentColor() : this.commandKeyColor())
          .borderRadius(8)
          .onClick(() => this.selectEmojiCategory(category.id))
        }, (category: EmojiCategory): string => category.id)
      }
      .padding({ left: 2, right: 2 })
    }
    .width('100%')
    .height(36)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  /** Categorized Unicode emoji picker; each displayed grid remains bounded to one category. */
  @Builder
  private buildEmojiPage() {
    this.buildEmojiCategorySelector()
    if (this.selectedEmojiItems().length === 0) {
      Column({ space: 6 }) {
        Text('No recent emoji yet')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.secondaryTextColor())
        Text('Emoji you use will appear here.')
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
      }
      .width('100%')
      .layoutWeight(3)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      Grid() {
        ForEach(this.selectedEmojiItems(), (emoji: string, index: number) => {
          GridItem() {
            Button() {
              Text(emoji)
                .width('100%')
                .fontSize(26)
                .lineHeight(36)
                .textAlign(TextAlign.Center)
            }
            .id(`emoji-${this.selectedEmojiCategoryId}-${index}`)
            .width('100%')
            .height(52)
            .padding({ left: 0, right: 0, top: 0, bottom: 0 })
            .backgroundColor(this.keyColor())
            .borderRadius(9)
            .onClick(() => this.sendEmoji(emoji))
          }
        }, (emoji: string, index: number): string => `${this.selectedEmojiCategoryId}-${index}-${emoji}`)
      }
      .width('100%')
      .layoutWeight(3)
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .columnsGap(4)
      .rowsGap(4)
      .scrollBar(BarState.Auto)
    }

    Row({ space: this.keyGap() }) {
      this.buildLayerSwitchKey('ABC', 1.35, 'emoji-bottom-letters', KeyboardLayer.Letters)
      this.buildSpaceKey('space', 4.80, 'emoji-bottom-space')
      Button() {
        this.buildKeyLabel('⌫', false, true)
      }
      .id('emoji-bottom-backspace')
      .layoutWeight(1.25)
      .height('100%')
      .padding({ left: 0, right: 0, top: 0, bottom: 0 })
      .backgroundColor(this.commandKeyColor())
      .borderRadius(9)
      .onTouch((event: TouchEvent) => this.handleBackspaceTouch(event))
      this.buildEnterKey(1.25, 'emoji-bottom-enter')
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private buildBottomRow() {
    if (!this.isLettersLayer()) {
      this.buildNonLetterBottomRow()
    } else if (this.isBurmeseMode()) {
      this.buildBurmeseBottomRow()
    } else {
      this.buildEnglishBottomRow()
    }
  }

  /** A page-local overlay: it is positioned in the Stack and never consumes row space. */
  @Builder
  private buildBurmeseLongPressPopup() {
    if (this.longPressPopupVisible) {
      Row({ space: BURMESE_POPUP_GAP }) {
        ForEach(this.longPressOptions, (option: PopupKeyOption, index: number) => {
          Column() {
            this.buildKeyLabel(option.label, true)
          }
          .width(BURMESE_POPUP_OPTION_WIDTH)
          .height(BURMESE_POPUP_HEIGHT)
          .backgroundColor(index === this.longPressHighlightedOptionIndex ? this.accentColor() : this.keyColor())
          .border({ width: 1, color: this.isDarkMode() ? '#657385' : '#9BA8B7' })
          .borderRadius(12)
          .shadow({ radius: 8, offsetY: 3, color: this.isDarkMode() ? '#00000088' : '#53627355' })
        }, (option: PopupKeyOption): string => option.id)
      }
      .position({ x: this.longPressPopupLeft, y: this.longPressPopupTop })
      .zIndex(10)
    }
  }

  /** A page-local normal-key preview. It is purely visual and reserves no row space. */
  @Builder
  private buildKeyPreviewPopup() {
    if (this.keyPreviewVisible) {
      Column() {
        Text(this.keyPreviewLabel)
          .width('100%')
          .fontSize(this.keyPreviewFontSize)
          .lineHeight(this.keyPreviewLineHeight)
          .fontColor(this.textColor())
          .textAlign(TextAlign.Center)
      }
      .width(this.keyPreviewWidth)
      .height(this.keyPreviewHeight)
      .padding(this.keyPreviewIsBurmese ? { left: 3, right: 3, top: 3, bottom: 3 } : { left: 3, right: 3, top: 2, bottom: 2 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.keyColor())
      .border({ width: 1, color: this.isDarkMode() ? '#657385' : '#9BA8B7' })
      .borderRadius(10)
      .shadow({ radius: 5, offsetY: 2, color: this.isDarkMode() ? '#00000066' : '#53627344' })
      .position({ x: this.keyPreviewLeft, y: this.keyPreviewTop })
      .zIndex(9)
    }
  }

  @Builder
  private buildKeyboardContent() {
    Column({ space: this.keyGap() }) {
      // Burmese always reserves the same composition strip. The text can
      // change, but this child is never conditionally inserted or removed, so
      // no composition update can change key row positions or heights.
      if (this.isBurmeseMode()) {
        this.buildBurmeseCompositionStrip()
      } else {
        this.buildEnglishHeaderStrip()
      }

      if (this.isEmojiLayer()) {
        this.buildEmojiPage()
      } else if (this.isBurmeseMode()) {
        if (this.isNumbersLayer()) {
          this.buildLogicalRow(this.burmeseNumberRows[0], 'MM-number-r1')
          this.buildLogicalRow(this.burmeseNumberRows[1], 'MM-number-r2')
          this.buildNonLetterThirdRow(this.burmeseNumberRows[2], 'MM-number-r3', '#+=', KeyboardLayer.Symbols)
        } else if (!this.isLettersLayer()) {
          this.buildLogicalRow(this.burmeseSymbolRows[0], 'MM-symbol-r1')
          this.buildLogicalRow(this.burmeseSymbolRows[1], 'MM-symbol-r2')
          this.buildNonLetterThirdRow(this.burmeseSymbolRows[2], 'MM-symbol-r3', '123', KeyboardLayer.Numbers)
        } else if (this.isShiftActive()) {
          this.buildLogicalRow(this.burmeseShiftRow1, 'MM-shift-r1')
          this.buildLogicalRow(this.burmeseShiftRow2, 'MM-shift-r2')
          this.buildLetterThirdRow(this.burmeseShiftRow3, 'MM-shift-r3')
        } else {
          this.buildLogicalRow(this.burmeseNormalRow1, 'MM-normal-r1')
          // This is a distinct 11-key row. Versioning its identity removes any
          // stale twelfth child from a previously loaded panel tree.
          this.buildLogicalRow(this.burmeseNormalRow2, 'MM-normal-r2-v2')
          this.buildLetterThirdRow(this.burmeseNormalRow3, 'MM-normal-r3')
        }
      } else {
        if (this.isNumbersLayer()) {
          this.buildLogicalRow(this.englishNumberRows[0], 'EN-number-r1')
          this.buildLogicalRow(this.englishNumberRows[1], 'EN-number-r2')
          this.buildNonLetterThirdRow(this.englishNumberRows[2], 'EN-number-r3', '#+=', KeyboardLayer.Symbols)
        } else if (!this.isLettersLayer()) {
          this.buildLogicalRow(this.englishSymbolRows[0], 'EN-symbol-r1')
          this.buildLogicalRow(this.englishSymbolRows[1], 'EN-symbol-r2')
          this.buildNonLetterThirdRow(this.englishSymbolRows[2], 'EN-symbol-r3', '123', KeyboardLayer.Numbers)
        } else if (this.isShiftActive()) {
          this.buildLogicalRow(this.englishShiftRow1, 'EN-shift-r1')
          this.buildLogicalRow(this.englishShiftRow2, 'EN-shift-r2')
          this.buildLetterThirdRow(this.englishShiftRow3, 'EN-shift-r3')
        } else {
          this.buildLogicalRow(this.englishNormalRow1, 'EN-normal-r1')
          this.buildLogicalRow(this.englishNormalRow2, 'EN-normal-r2')
          this.buildLetterThirdRow(this.englishNormalRow3, 'EN-normal-r3')
        }
      }
      if (!this.isEmojiLayer()) {
        this.buildBottomRow()
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.isBurmeseMode() ? 4 : 6,
      right: this.isBurmeseMode() ? 4 : 6,
      top: this.isBurmeseMode() ? 4 : 6,
      bottom: this.isBurmeseMode() ? 4 : 6,
    })
    .backgroundColor(this.panelColor())
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildKeyboardContent()
      this.buildKeyPreviewPopup()
      this.buildBurmeseLongPressPopup()
    }
    .width('100%')
    .height('100%')
    .onAreaChange((previous: Area, next: Area) => this.recordKeyboardPageArea(previous, next))
  }
}

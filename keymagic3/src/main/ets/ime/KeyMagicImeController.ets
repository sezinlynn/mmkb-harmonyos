import { Action, KeyCode, KeyEvent as InputMethodKeyEvent } from '@kit.InputKit';
import { InputMethodExtensionContext, inputMethodEngine } from '@kit.IMEKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';
import MeasureText from '@ohos.measure';
import text from '@ohos.graphics.text';

import { keyMagicInputFromInputMethodEvent, KeyMagicVirtualKey } from '../common/KeyMagicKeyMap';
import { KeyMagicActionType, KeyMagicKeyInput, KeyMagicNative, KeyMagicProcessResult } from '../common/KeyMagicNative';
import { KeyboardInfo } from '../keyboard/KeyboardInfo';
import { KeyboardManager } from '../keyboard/KeyboardManager';
import { KeyboardSelection, KeyboardSelectionService } from '../keyboard/KeyboardSelectionService';

const IME_LOG_DOMAIN = 0x0000;
const IME_LOG_TAG = 'KeyMagicIme';
const IME_PANEL_PAGE = 'pages/KeyMagicImeStatus';
const KEYMAGIC_MODULE_NAME = 'keymagic3';
const IME_DIAGNOSTICS_PREFERENCES = 'keymagic_ime_diagnostics';
const DIAGNOSTIC_KEY = 'keymagicImeDiagnosticKey';
const DIAGNOSTIC_ENGINE_ACTION = 'keymagicImeDiagnosticEngineAction';
const DIAGNOSTIC_ENGINE_TEXT = 'keymagicImeDiagnosticEngineText';
const DIAGNOSTIC_ENGINE_DELETE_COUNT = 'keymagicImeDiagnosticEngineDeleteCount';
const DIAGNOSTIC_ENGINE_COMPOSITION = 'keymagicImeDiagnosticEngineComposition';
const DIAGNOSTIC_PREVIEW_TEXT = 'keymagicImeDiagnosticPreviewText';
const DIAGNOSTIC_PREVIEW_RANGE = 'keymagicImeDiagnosticPreviewRange';
const DIAGNOSTIC_TRANSPORT = 'keymagicImeDiagnosticTransport';
const DIAGNOSTIC_EDITOR_PREVIEW_SUPPORT = 'keymagicImeDiagnosticEditorPreviewSupport';
const DIAGNOSTIC_PREVIEW_RESULT = 'keymagicImeDiagnosticPreviewResult';
const DIAGNOSTIC_PREVIEW_ACTIVE = 'keymagicImeDiagnosticPreviewActive';
const DIAGNOSTIC_TEXT_SENT_TO_EDITOR = 'keymagicImeDiagnosticTextSentToEditor';
const DIAGNOSTIC_COUNTER = 'keymagicImeDiagnosticCounter';
const DIAGNOSTIC_TIMESTAMP = 'keymagicImeDiagnosticTimestamp';
const DIAGNOSTIC_SELECTION_CHANGE = 'keymagicImeDiagnosticSelectionChange';
const DIAGNOSTIC_EDITOR_IDENTITY = 'keymagicImeDiagnosticEditorIdentity';
const DIAGNOSTIC_SET_PREVIEW_ERROR_CODE = 'keymagicImeDiagnosticSetPreviewErrorCode';
const DIAGNOSTIC_FINISH_PREVIEW_RESULT = 'keymagicImeDiagnosticFinishPreviewResult';
const DIAGNOSTIC_FINISH_PREVIEW_ERROR_CODE = 'keymagicImeDiagnosticFinishPreviewErrorCode';
const DIAGNOSTIC_DIRECT_EDIT_RESULT = 'keymagicImeDiagnosticDirectEditResult';
const DIAGNOSTIC_DIRECT_EDIT_ERROR_CODE = 'keymagicImeDiagnosticDirectEditErrorCode';
const DIAGNOSTIC_DIRECT_TRACE = 'keymagicImeDiagnosticDirectTrace';
const COMPOSITION_POPUP_VISIBLE = 'keymagicImeCompositionPopupVisible';
const COMPOSITION_POPUP_TEXT = 'keymagicImeCompositionPopupText';
const COMPOSITION_POPUP_TRANSPORT = 'keymagicImeCompositionPopupTransport';
const COMPOSITION_POPUP_SESSION = 'keymagicImeCompositionPopupSession';
const COMPOSITION_POPUP_COLOR_MODE = 'keymagicImeCompositionPopupColorMode';
const DIRECT_TEXT_SNAPSHOT_LENGTH = 32;
const DIRECT_ENGINE_CONTEXT_LENGTH = 40;
const COMPOSITION_POPUP_MIN_WIDTH = 56;
// The panel width includes padding and a shaping safety allowance, leaving
// 420vp of actual composition content before ArkUI naturally wraps it.
const COMPOSITION_POPUP_PREFERRED_MAX_WIDTH = 460;
const COMPOSITION_POPUP_MIN_HEIGHT = 48;
// This value is used only before calling-window geometry is available. The
// panel is not shown in that state; once it can be shown, its height is bounded
// solely by the focused window's available screen area.
const COMPOSITION_POPUP_PREPOSITION_MAX_HEIGHT = 600;
const COMPOSITION_POPUP_FONT_SIZE = 17;
// ArkUI's public text measurement reports width but no matching panel-font
// ascent/descent metrics. Reserve this fixed Myanmar-safe line box from the
// first frame instead of letting individual glyph bounds resize the popup.
const COMPOSITION_POPUP_LINE_HEIGHT = 33;
const COMPOSITION_POPUP_HORIZONTAL_PADDING = 10;
const COMPOSITION_POPUP_VERTICAL_PADDING = 6;
const COMPOSITION_POPUP_HORIZONTAL_SAFETY_ALLOWANCE = 20;
const COMPOSITION_POPUP_BORDER_ALLOWANCE = 2;
const COMPOSITION_POPUP_RECT_EPSILON = 1;
const COMPOSITION_POPUP_CARET_GAP = 8;
const COMPOSITION_POPUP_WINDOW_MARGIN = 24;
const KEYBOARD_SWITCH_FEEDBACK_DURATION_MS = 1400;

interface DirectEditorSnapshot {
  cursor: number | undefined;
  selection: string;
  selectionBegin: number | undefined;
  selectionEnd: number | undefined;
  textBefore: string | undefined;
  textAfter: string | undefined;
  readErrors: string;
}

interface ExpectedDirectSelectionChange {
  operation: string;
  expectedBegin: number;
  expectedEnd: number;
}

interface ExpectedDirectTextChange {
  operation: string;
  expectedText: string | undefined;
}

interface DirectRawTextLeakProbe {
  rawKeyCode: number;
  character: string;
  expectedTextBeforeCursor: string | undefined;
}

interface HandledPhysicalKeyState {
  rawKeyCode: number;
  firstPressedTime: number;
  repeatCount: number;
}

type DirectTransactionKind = 'INSERT' | 'DELETE' | 'DELETE_AND_INSERT';
type DirectTransactionPhase = 'IDLE' | 'WAITING_INSERT_ACK' | 'WAITING_DELETE_ACK' |
  'WAITING_FINAL_INSERT_ACK';

interface PendingDirectTransaction {
  id: number;
  kind: DirectTransactionKind;
  phase: DirectTransactionPhase;
  expectedFinalSuffix: string;
  expectedCursor: number | undefined;
  expectedDeletedSuffix: string | undefined;
  expectedTextBeforeDelete: string | undefined;
  expectedTextAfterDelete: string | undefined;
  originalOutput: KeyMagicProcessResult;
  originatingRawKeyCode: number;
}

interface QueuedPhysicalDown {
  event: InputMethodKeyEvent;
}

interface CompositionPopupRect {
  // Panel/cursor/window geometry is expressed in window pixels. Logical ArkUI
  // values are converted before they enter this native panel rectangle.
  left: number;
  top: number;
  width: number;
  height: number;
}

interface CompositionPopupSize {
  width: number;
  height: number;
}

interface CompositionPopupLayout {
  measuredWidth: number;
  paragraphHeight: number;
  lineCount: number | undefined;
  contentHeightVp: number | undefined;
  requestedPanelHeightVp: number | undefined;
  targetSize: CompositionPopupSize;
}

/**
 * Owns the existing KeyMagic NAPI engine for one InputMethodExtensionAbility.
 * It deliberately has no virtual-keyboard logic: the KeyboardDelegate is the
 * sole input source in this physical-keyboard beta.
 */
export class KeyMagicImeController {
  private readonly native: KeyMagicNative = new KeyMagicNative();
  private readonly keyboardManager: KeyboardManager = new KeyboardManager();
  private readonly keyboardSelectionService: KeyboardSelectionService = new KeyboardSelectionService();
  private imeContext: InputMethodExtensionContext | undefined;
  /** System-IPC selection loaded into the current native engine. */
  private currentKeyboardSelection: KeyboardSelection | undefined;
  private loadedKeyboardId: string | undefined;
  private loadedKeyboardGeneration: number = -1;
  private inputMethodAbility: inputMethodEngine.InputMethodAbility | undefined;
  private keyboardDelegate: inputMethodEngine.KeyboardDelegate | undefined;
  private inputClient: inputMethodEngine.InputClient | undefined;
  private panel: inputMethodEngine.Panel | undefined;
  private keyboardLoaded: boolean = false;
  private started: boolean = false;

  // All editors use the same internal-composition transport. The focused
  // document changes only when the existing composition-boundary code commits
  // this buffer; the floating panel is a presentation-only observer.
  private lastSelectionBegin: number | undefined;
  private lastSelectionEnd: number | undefined;
  private directFallbackOperationInProgress: string | undefined;
  private directSelectionCallbackObserved: boolean = false;
  private directTextCallbackObserved: boolean = false;
  private expectedDirectSelectionChanges: ExpectedDirectSelectionChange[] = [];
  private expectedDirectTextChanges: ExpectedDirectTextChange[] = [];
  // The IME owns both sides of every KeyMagic-handled physical key press.
  // Raw codes are tracked independently so overlapping keys and repeated
  // DOWN events cannot leave an unpaired printable event path.
  private handledPhysicalKeys: HandledPhysicalKeyState[] = [];
  private directRawTextLeakProbe: DirectRawTextLeakProbe | undefined;
  private nextDirectTransactionId: number = 1;
  private pendingDirectTransaction: PendingDirectTransaction | undefined;
  // Normally this queue contains one key: an editor callback acknowledges the
  // preceding transaction before another key is pressed. Preserve order if a
  // client defers multiple acknowledgements rather than leaking printable input.
  private queuedPhysicalDowns: QueuedPhysicalDown[] = [];
  // Captured before native.processKey() by direct-mode synchronization. It is
  // the exact Rust composition that a delete-and-insert replacement is allowed
  // to remove from the editor, never a guessed delete-count conversion.
  private directEngineCompositionBeforeKey: string | undefined;
  private directEngineSynchronization: string = 'not run for this direct-fallback key';
  // Some API-20 editors acknowledge a text mutation through textChange but
  // report -1 for getTextIndexAtCursorSync()/getForwardSync().  This is still
  // an editor-originated acknowledgement of the exact suffix we inserted;
  // retain it only as fallback evidence for the immediately following guarded
  // direct replacement. It is never used to manufacture a delete count.
  private directAcknowledgedSuffix: string | undefined;
  // The document never receives this text while it is active. It is inserted
  // exactly once by commitInternalComposition() at a true boundary.
  private internalComposition: string = '';
  private directCommitInProgress: boolean = false;
  // The floating panel observes this state only. It never participates in
  // engine processing, composition boundaries, or document operations.
  private compositionPopupShown: boolean = false;
  private compositionPopupSession: number = 0;
  // Composition publication is authoritative and independent of native panel
  // geometry. Every revision is written to ArkUI immediately; asynchronous
  // geometry callbacks never publish text and therefore cannot make it stale.
  private compositionPopupGeneration: number = 0;
  private compositionPopupLatestComposition: string = '';
  private compositionPopupUiGeneration: number = 0;
  private compositionPopupUiComposition: string = '';
  private compositionPopupLastLayout: CompositionPopupLayout | undefined;
  private compositionPopupCursorX: number | undefined;
  private compositionPopupCursorY: number | undefined;
  private compositionPopupCursorHeight: number | undefined;
  private compositionPopupRect: CompositionPopupRect | undefined;
  private compositionPopupLastRequestedRect: CompositionPopupRect | undefined;
  private compositionPopupActualWidth: number | undefined;
  private compositionPopupActualHeight: number | undefined;
  private compositionPopupWindowRect: CompositionPopupRect | undefined;
  private compositionPopupWindowPositionRequested: boolean = false;
  // Presentation-only feedback shown after Ctrl+Shift+Z changes MyanKey's
  // active keyboard. It never becomes engine composition or editor text.
  private keyboardSwitchFeedback: string = '';
  private keyboardSwitchFeedbackToken: number = 0;
  private diagnosticsPreferences: preferences.Preferences | undefined;
  private diagnosticKey: string = 'No physical key-down event yet';
  private diagnosticEngineAction: string = '—';
  private diagnosticEngineText: string = '—';
  private diagnosticEngineDeleteCount: string = '—';
  private diagnosticEngineComposition: string = '—';
  private diagnosticPreviewText: string = '—';
  private diagnosticPreviewRange: string = '—';
  private diagnosticEditorPreviewSupport: string = 'unknown (waiting for editorAttributeChanged)';
  private diagnosticPreviewResult: string = 'not called';
  private diagnosticPreviewActive: string = 'false';
  private diagnosticTextSentToEditor: string = '—';
  private diagnosticCounter: string = '0';
  private diagnosticTimestamp: string = 'not yet written';
  private diagnosticSelectionChange: string = 'No selection change while preview active yet';
  private diagnosticEditorIdentity: string = 'unknown (waiting for editorAttributeChanged)';
  private diagnosticSetPreviewErrorCode: string = 'not called';
  private diagnosticFinishPreviewResult: string = 'not called';
  private diagnosticFinishPreviewErrorCode: string = 'not called';
  private diagnosticDirectEditResult: string = 'not used';
  private diagnosticDirectEditErrorCode: string = 'not used';
  private diagnosticDirectTrace: string = 'No direct-fallback transaction yet';
  private diagnosticsContextIdentity: string = 'not initialized';

  private readonly onKeyboardSelectionIpcChanged = (selection: KeyboardSelection): void => {
    this.currentKeyboardSelection = selection;
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `IME IPC GET activeKeyboardId=${selection.activeKeyboardId} ` +
        `keyboardGeneration=${selection.keyboardGeneration} source=dataProxy-change`);
    if (this.started && this.native.isCreated()) {
      this.ensureIpcKeyboardLoaded('keyboard selection IPC change');
    }
  };

  private readonly onInputStart = (
    _keyboardController: inputMethodEngine.KeyboardController,
    inputClient: inputMethodEngine.InputClient,
  ): void => {
    this.inputClient = inputClient;
    this.resetInputSessionState();
    this.resetTransportDiagnostics();
    this.resetForInputSession('inputStart');
    void this.refreshKeyboardSelectionFromIpc('inputStart');
    this.ensureIpcKeyboardLoaded('inputStart cached IPC selection');
    // Read-only geometry used only to position a panel if a composition starts
    // before the client publishes cursorContextChange.
    this.requestCompositionPopupWindowPosition();
  };

  private readonly onInputStop = (): void => {
    this.commitCompositionAndReset('inputStop');
    this.inputClient = undefined;
  };

  private readonly onKeyboardShow = (): void => {
    this.publishCompositionPopup();
  };

  private readonly onKeyboardHide = (): void => {
    this.hideCompositionPopup();
  };

  private readonly onKeyEvent = (event: InputMethodKeyEvent): boolean => {
    return this.handlePhysicalKeyEvent(event);
  };

  private readonly onCursorContextChange = (x: number, y: number, height: number): void => {
    this.compositionPopupCursorX = x;
    this.compositionPopupCursorY = y;
    this.compositionPopupCursorHeight = height;
    this.positionCompositionPopup();
  };

  // This is observation only. In particular, it never calls adjustPanelRect()
  // so a platform size acknowledgement cannot form a resize feedback loop.
  private readonly onCompositionPopupSizeChange: inputMethodEngine.SizeChangeCallback = (size) => {
    this.compositionPopupActualWidth = size.width;
    this.compositionPopupActualHeight = size.height;
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `Composition popup sizeChange actual=${size.width}x${size.height} ` +
        `requested=${this.describeCompositionPopupRect(this.compositionPopupLastRequestedRect)}`);
    this.logCompositionPopupRenderTrace(this.compositionPopupUiGeneration);
  };

  private readonly onEditorAttributeChanged = (attribute: inputMethodEngine.EditorAttribute): void => {
    this.diagnosticEditorPreviewSupport = 'ignored: universal internal composition';
    this.diagnosticEditorIdentity = this.describeEditor(attribute);
    this.diagnosticPreviewResult = 'disabled: universal popup composition';
    this.diagnosticSetPreviewErrorCode = 'not used';
    this.diagnosticPreviewActive = 'false';
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `EDITOR COMPATIBILITY editor=${this.diagnosticEditorIdentity} ` +
      `transport=${this.currentTransport()}`);
    this.publishCompositionPopup();
    this.publishTransportDiagnostics();
  };

  private readonly onSelectionChange = (
    oldBegin: number,
    oldEnd: number,
    newBegin: number,
    newEnd: number,
  ): void => {
    this.lastSelectionBegin = newBegin;
    this.lastSelectionEnd = newEnd;
    if (this.directCommitInProgress) {
      this.recordDirectFallbackCallback(
        'SELECTION',
        `old=${oldBegin},${oldEnd} new=${newBegin},${newEnd} classification=IME-generated ` +
          'operation=internal composition commit',
      );
      return;
    }
    this.recordDirectFallbackCallback(
      'SELECTION',
      `old=${oldBegin},${oldEnd} new=${newBegin},${newEnd} ` +
        'classification=external; action=commit internal composition/reset engine',
    );
    if (this.internalComposition.length > 0) {
      this.commitCompositionAndReset('direct editor selection change');
    }
  };

  private readonly onTextChange = (text: string): void => {
    if (this.directCommitInProgress) {
      this.recordDirectFallbackCallback(
        'TEXT',
        `text=${this.formatTextWithCodePoints(text)} classification=IME-generated ` +
          'operation=internal composition commit',
      );
      return;
    }
    this.recordDirectFallbackCallback(
      'TEXT',
      `text=${this.formatTextWithCodePoints(text)} ` +
        'classification=external; action=commit internal composition/reset engine',
    );
    if (this.internalComposition.length > 0) {
      this.commitCompositionAndReset('direct editor text change');
    }
  };

  start(context: InputMethodExtensionContext): void {
    if (this.started) {
      return;
    }
    this.started = true;
    this.imeContext = context;
    this.initializeTransportDiagnostics(context);
    try {
      this.inputMethodAbility = inputMethodEngine.getInputMethodAbility();
      this.keyboardDelegate = inputMethodEngine.getKeyboardDelegate();
      this.inputMethodAbility.on('inputStart', this.onInputStart);
      this.inputMethodAbility.on('inputStop', this.onInputStop);
      this.inputMethodAbility.on('keyboardShow', this.onKeyboardShow);
      this.inputMethodAbility.on('keyboardHide', this.onKeyboardHide);
      this.keyboardDelegate.on('keyEvent', this.onKeyEvent);
      this.keyboardDelegate.on('cursorContextChange', this.onCursorContextChange);
      this.keyboardDelegate.on('editorAttributeChanged', this.onEditorAttributeChanged);
      this.keyboardDelegate.on('selectionChange', this.onSelectionChange);
      this.keyboardDelegate.on('textChange', this.onTextChange);
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `Unable to subscribe to IME callbacks: ${JSON.stringify(error)}`);
      return;
    }

    this.initializeEngineAndPanel(context);
  }

  /** Updates panel-only color state; this has no IME transport side effects. */
  setCompositionPopupDarkMode(isDark: boolean): void {
    AppStorage.setOrCreate(COMPOSITION_POPUP_COLOR_MODE, isDark ? 'dark' : 'light');
  }

  stop(): void {
    this.commitCompositionAndReset('IME destroy');
    this.keyboardLoaded = false;
    this.currentKeyboardSelection = undefined;
    this.loadedKeyboardId = undefined;
    this.loadedKeyboardGeneration = -1;
    this.inputClient = undefined;
    this.started = false;
    this.imeContext = undefined;

    if (this.keyboardDelegate !== undefined) {
      this.keyboardDelegate.off('keyEvent', this.onKeyEvent);
      this.keyboardDelegate.off('cursorContextChange', this.onCursorContextChange);
      this.keyboardDelegate.off('editorAttributeChanged', this.onEditorAttributeChanged);
      this.keyboardDelegate.off('selectionChange', this.onSelectionChange);
      this.keyboardDelegate.off('textChange', this.onTextChange);
      this.keyboardDelegate = undefined;
    }
    if (this.inputMethodAbility !== undefined) {
      this.inputMethodAbility.off('inputStart', this.onInputStart);
      this.inputMethodAbility.off('inputStop', this.onInputStop);
      this.inputMethodAbility.off('keyboardShow', this.onKeyboardShow);
      this.inputMethodAbility.off('keyboardHide', this.onKeyboardHide);
      if (this.panel !== undefined) {
        this.panel.off('sizeChange', this.onCompositionPopupSizeChange);
        this.destroyPanel(this.inputMethodAbility, this.panel);
      }
      this.inputMethodAbility = undefined;
    }
    this.panel = undefined;
    this.native.destroyEngine();
  }

  private async initializeEngineAndPanel(context: InputMethodExtensionContext): Promise<void> {
    try {
      const selection = await this.keyboardSelectionService.startObserving(this.onKeyboardSelectionIpcChanged);
      this.currentKeyboardSelection = selection;
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME IPC GET activeKeyboardId=${selection.activeKeyboardId} ` +
          `keyboardGeneration=${selection.keyboardGeneration} source=IME-engine-initialization`);
      this.native.createEngine();
      if (!this.ensureIpcKeyboardLoaded('IME engine initialization')) {
        throw new Error('Unable to load the IPC-authoritative MyanKey keyboard selection.');
      }

      if (this.inputMethodAbility === undefined) {
        return;
      }
      const panel = await this.inputMethodAbility.createPanel(context, {
        type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
        flag: inputMethodEngine.PanelFlag.FLG_FLOATING,
      });
      await panel.setUiContent(IME_PANEL_PAGE);
      this.panel = panel;
      panel.on('sizeChange', this.onCompositionPopupSizeChange);
      this.publishCompositionPopup();
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        'Floating KeyMagic composition panel created.');
    } catch (error) {
      this.keyboardLoaded = false;
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `Unable to initialize KeyMagic IME: ${JSON.stringify(error)}`);
    }
  }

  private handlePhysicalKeyEvent(event: InputMethodKeyEvent, fromPendingQueue: boolean = false): boolean {
    const priorHandledKey = this.findHandledPhysicalKey(event.key.code);
    const repeatDown = event.action === Action.DOWN && priorHandledKey !== undefined;
    const repeatCount = priorHandledKey === undefined ? 0 : priorHandledKey.repeatCount + (repeatDown ? 1 : 0);
    const modifierOnly = this.isModifierOnlyPhysicalKey(event.key.code);

    // UP never reaches KeyMagic or an editor operation. It is consumed only
    // when it belongs to a successful direct-fallback DOWN we handled.
    if (event.action !== Action.DOWN) {
      this.logCompositionBoundaryCheck(
        event,
        keyMagicInputFromInputMethodEvent(event).keyCode,
        modifierOnly,
        'not-run',
        'PRESERVE',
        modifierOnly ? 'modifier-only UP' : 'UP events never process or commit composition',
      );
      const matchedHandledDown = event.action === Action.UP &&
        this.takeHandledPhysicalKeyUp(event.key.code) !== undefined;
      if (matchedHandledDown) {
        this.appendDirectFallbackTrace(
          `DIRECT FALLBACK EVENT: rawKeyCode=${event.key.code}; action=UP; ` +
          'processed=false; direct-transaction=not-run; returned-consumed=true; matched-handled-DOWN=true',
        );
      }
      return this.finishPhysicalKeyEvent(
        event,
        'false',
        'not-run',
        matchedHandledDown,
        matchedHandledDown,
        false,
        priorHandledKey === undefined ? 0 : priorHandledKey.repeatCount,
      );
    }
    // This runs before mapping, KeyMagic, or any editor transport. It is the
    // cross-process diagnostic proof that the IME received this physical DOWN.
    if (!fromPendingQueue) {
      this.recordPhysicalDownDiagnostic(event);
    }
    if (this.inputClient === undefined) {
      this.logCompositionBoundaryCheck(
        event,
        keyMagicInputFromInputMethodEvent(event).keyCode,
        modifierOnly,
        'not-run',
        'PRESERVE',
        'no active input session',
      );
      return this.finishPhysicalKeyEvent(event, 'not-run', 'not-run', false, priorHandledKey !== undefined,
        repeatDown, repeatCount);
    }

    // Modifier key transitions are state-only. In particular, Shift DOWN
    // must not reach the generic unhandled-key path before Shift+7 is
    // delivered as one shifted printable KeyMagic input.
    if (modifierOnly) {
      this.logCompositionBoundaryCheck(
        event,
        keyMagicInputFromInputMethodEvent(event).keyCode,
        true,
        'not-run',
        'PRESERVE',
        'modifier-only DOWN',
      );
      return this.finishPhysicalKeyEvent(event, 'not-run', 'not-run', false, priorHandledKey !== undefined,
        repeatDown, repeatCount);
    }

    // MyanKey owns internal KM2 selection. Intercept the development shortcut
    // before the ordinary Ctrl-shortcut pass-through path, so Z never reaches
    // KeyMagic or the focused editor.
    if (this.isKeyboardCycleHotkey(event)) {
      let switched = true;
      if (!repeatDown) {
        switched = this.cycleKeyboard();
        if (!fromPendingQueue) {
          this.markHandledPhysicalDown(event);
        }
      }
      this.logCompositionBoundaryCheck(
        event,
        keyMagicInputFromInputMethodEvent(event).keyCode,
        false,
        'not-run',
        'PRESERVE',
        switched ? 'MyanKey Ctrl+Shift+Z keyboard cycle' : 'MyanKey keyboard cycle failed',
      );
      return this.finishPhysicalKeyEvent(event, 'not-run', switched ? 'keyboard-cycle' : 'keyboard-cycle-failed',
        true, priorHandledKey !== undefined, repeatDown, repeatCount);
    }

    if (event.ctrlKey || event.altKey || event.logoKey || event.fnKey) {
      this.logCompositionBoundaryCheck(
        event,
        keyMagicInputFromInputMethodEvent(event).keyCode,
        false,
        'not-run',
        'COMMIT',
        'existing system-shortcut modifier policy for non-modifier key',
      );
      this.commitCompositionAndReset('system shortcut modifier');
      return this.finishPhysicalKeyEvent(event, 'not-run', 'not-run', false, priorHandledKey !== undefined,
        repeatDown, repeatCount);
    }

    const input = keyMagicInputFromInputMethodEvent(event);
    if (input.keyCode === 0) {
      this.logCompositionBoundaryCheck(event, input.keyCode, false, 'not-run', 'COMMIT', 'unmapped physical key');
      this.commitCompositionAndReset('unmapped physical key');
      return this.finishPhysicalKeyEvent(event, 'not-run', 'not-run', false, priorHandledKey !== undefined,
        repeatDown, repeatCount);
    }

    // Match the macOS adapter: Escape commits any active KeyMagic composition
    // before passing Escape itself through to the focused application.
    if (input.keyCode === KeyMagicVirtualKey.Escape) {
      this.logCompositionBoundaryCheck(event, input.keyCode, false, 'not-run', 'COMMIT', 'Escape');
      this.commitCompositionAndReset('Escape');
      return this.finishPhysicalKeyEvent(event, 'not-run', 'not-run', false, priorHandledKey !== undefined,
        repeatDown, repeatCount);
    }

    // The Data Proxy observer has already delivered the authoritative record
    // before this synchronous keyboard callback. Never read Preferences here.
    if (this.isPrintableKeyMagicInput(input) && !this.ensureIpcKeyboardLoaded('physical printable key')) {
      this.logCompositionBoundaryCheck(
        event,
        input.keyCode,
        false,
        'not-run',
        'PRESERVE',
        'IPC keyboard reload failed; printable key consumed without processing',
      );
      if (!fromPendingQueue) {
        this.markHandledPhysicalDown(event);
      }
      return this.finishPhysicalKeyEvent(event, 'not-run', 'keyboard-reload-failed', true,
        priorHandledKey !== undefined, repeatDown, repeatCount);
    }

    if (!this.keyboardLoaded) {
      this.logCompositionBoundaryCheck(
        event,
        input.keyCode,
        false,
        'not-run',
        'PRESERVE',
        'no loaded keyboard after IPC keyboard check',
      );
      return this.finishPhysicalKeyEvent(event, 'not-run', 'not-run', false, priorHandledKey !== undefined,
        repeatDown, repeatCount);
    }

    let processed = false;
    let directTransactionRan = false;
    try {
      const compositionBefore = this.internalComposition;
      const output = this.native.processKey(input, 'InputMethod KeyboardDelegate');
      processed = output.isProcessed;
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `PROCESS KEY keyboardId=${this.loadedKeyboardId === undefined ? '<none>' : this.loadedKeyboardId} ` +
          `generation=${this.loadedKeyboardGeneration} ` +
          `engineId=${output.engineId} runtimeKeyboardId=${output.runtimeKeyboardId} ` +
          `rawKeyCode=${event.key.code} key=${input.keyCode} shift=${input.shift === true} ` +
          `compositionBefore=${this.formatTextWithCodePoints(compositionBefore)} ` +
          `outputText=${this.formatTextWithCodePoints(output.text)} ` +
          `outputComposition=${this.formatTextWithCodePoints(output.composingText)} ` +
          `outputCodepoints=${this.formatTextWithCodePoints(output.text.length > 0 ? output.text : output.composingText)}`);
      this.recordEngineOutput(input, output);
      if (!output.isProcessed) {
        // This matches the Windows, macOS, and IBus adapters: first finish
        // the current composition, then let the original key reach the app.
        this.logCompositionBoundaryCheck(
          event,
          input.keyCode,
          false,
          'false',
          'COMMIT',
          'unhandled non-modifier KeyMagic key',
        );
        this.commitCompositionAndReset('unhandled KeyMagic key');
        return this.finishPhysicalKeyEvent(event, 'false', 'not-run', false, priorHandledKey !== undefined,
          repeatDown, repeatCount);
      }

      directTransactionRan = true;
      this.logCompositionBoundaryCheck(event, input.keyCode, false, 'true', 'PROCESS', 'KeyMagic handled printable key');
      this.applyEngineOutput(this.inputClient, output, event.key.code);
      if (this.shouldCommitProcessedComposition(input.keyCode, output)) {
        this.logCompositionBoundaryCheck(
          event,
          input.keyCode,
          false,
          'true',
          'COMMIT',
          'existing processed composition boundary',
        );
        this.commitCompositionAndReset('processed composition boundary');
      }
      const directTransactionStatus = directTransactionRan ?
        (this.internalComposition.length > 0 ? 'composition-held' : 'commit-or-immediate') : 'not-run';
      this.recordHandledPhysicalKey(event, input, this.inputClient, directTransactionStatus, fromPendingQueue);
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `Consumed physical key. returned-consumed=true transport=${this.currentTransport()} ` +
        `action=${output.actionType} delete_count=${output.deleteCount} composing=${output.composingText}`);
      return this.finishPhysicalKeyEvent(event, 'true', directTransactionStatus, true,
        priorHandledKey !== undefined, repeatDown, repeatCount);
    } catch (error) {
      // If the editor connection fails after the engine has advanced, discard
      // the composition so the next input session cannot apply a stale edit.
      this.resetForInputSession('editor operation failure');
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `KeyMagic IME key handling failed: ${JSON.stringify(error)}`);
      // KeyMagic has consumed this printable key logically even though its
      // document transaction failed. Keep it out of the client app, reset the
      // engine, and wait for the next physical key rather than leaking Latin.
      if (processed && !fromPendingQueue) {
        this.markHandledPhysicalDown(event);
      }
      return this.finishPhysicalKeyEvent(event, `${processed}`, directTransactionRan ? 'failure' : 'not-run', processed,
        priorHandledKey !== undefined, repeatDown, repeatCount);
    }
  }

  private isModifierOnlyPhysicalKey(rawKeyCode: number): boolean {
    switch (rawKeyCode) {
      case KeyCode.KEYCODE_SHIFT_LEFT:
      case KeyCode.KEYCODE_SHIFT_RIGHT:
      case KeyCode.KEYCODE_CTRL_LEFT:
      case KeyCode.KEYCODE_CTRL_RIGHT:
      case KeyCode.KEYCODE_ALT_LEFT:
      case KeyCode.KEYCODE_ALT_RIGHT:
      case KeyCode.KEYCODE_META_LEFT:
      case KeyCode.KEYCODE_META_RIGHT:
      case KeyCode.KEYCODE_CAPS_LOCK:
      case KeyCode.KEYCODE_FUNCTION:
      case KeyCode.KEYCODE_FN:
        return true;
      default:
        return false;
    }
  }

  private isPrintableKeyMagicInput(input: KeyMagicKeyInput): boolean {
    return input.character !== undefined && input.character.length > 0;
  }

  private isKeyboardCycleHotkey(event: InputMethodKeyEvent): boolean {
    return event.key.code === KeyCode.KEYCODE_Z && event.ctrlKey && event.shiftKey &&
      !event.altKey && !event.logoKey && !event.fnKey;
  }

  /**
   * Compares the latest Data Proxy record against the engine currently loaded
   * in this IME process. Data Proxy notifications refresh this snapshot before
   * the next physical printable key; this method stays synchronous because the
   * KeyboardDelegate callback must return a consumption decision immediately.
   */
  private ensureIpcKeyboardLoaded(reason: string): boolean {
    if (!this.started || this.imeContext === undefined || !this.native.isCreated()) {
      return false;
    }
    const selection = this.currentKeyboardSelection === undefined ?
      this.keyboardSelectionService.getCachedSelection() : this.currentKeyboardSelection;
    if (selection === undefined) {
      void this.refreshKeyboardSelectionFromIpc(`missing cached selection (${reason})`);
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME IPC GET activeKeyboardId=<unavailable> keyboardGeneration=<unavailable>`);
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME KEYBOARD CHECK activeKeyboardId=<unavailable> keyboardGeneration=<unavailable> ` +
          `loadedId=${this.loadedKeyboardId === undefined ? '<none>' : this.loadedKeyboardId} ` +
          `loadedGeneration=${this.loadedKeyboardGeneration} decision=RELOAD reason=${reason}`);
      return false;
    }

    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `IME IPC GET activeKeyboardId=${selection.activeKeyboardId} ` +
        `keyboardGeneration=${selection.keyboardGeneration} source=physical-key-check`);

    const needsReload = !this.keyboardLoaded ||
      selection.activeKeyboardId !== this.loadedKeyboardId ||
      selection.keyboardGeneration !== this.loadedKeyboardGeneration;
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `IME KEYBOARD CHECK activeKeyboardId=${selection.activeKeyboardId} ` +
        `keyboardGeneration=${selection.keyboardGeneration} ` +
        `loadedId=${this.loadedKeyboardId === undefined ? '<none>' : this.loadedKeyboardId} ` +
        `loadedGeneration=${this.loadedKeyboardGeneration} decision=${needsReload ? 'RELOAD' : 'KEEP'} ` +
        `reason=${reason}`);
    if (!needsReload) {
      return true;
    }
    return this.reloadSelectedKeyboard(selection, reason);
  }

  private async refreshKeyboardSelectionFromIpc(reason: string): Promise<void> {
    try {
      const selection = await this.keyboardSelectionService.getSelection();
      this.currentKeyboardSelection = selection;
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME IPC GET activeKeyboardId=${selection.activeKeyboardId} ` +
          `keyboardGeneration=${selection.keyboardGeneration} source=${reason}`);
      this.ensureIpcKeyboardLoaded(reason);
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME IPC GET failed reason=${reason} error=${JSON.stringify(error)}`);
    }
  }

  /** Shared MyanKey command used by Ctrl+Shift+Z; no Harmony subtype participates. */
  private cycleKeyboard(): boolean {
    if (this.imeContext === undefined) {
      return false;
    }
    this.commitCompositionAndReset('MyanKey Ctrl+Shift+Z keyboard cycle');
    void this.cycleKeyboardThroughIpc();
    return true;
  }

  private async cycleKeyboardThroughIpc(): Promise<void> {
    try {
      const current = await this.keyboardSelectionService.getSelection();
      this.currentKeyboardSelection = current;
      const nextKeyboardId = this.keyboardManager.getNextKeyboardId(current.activeKeyboardId);
      const nextKeyboard = this.keyboardManager.getKeyboardById(nextKeyboardId);
      const selection = await this.keyboardSelectionService.setSelection(nextKeyboardId);
      this.currentKeyboardSelection = selection;
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `KEYBOARD IPC SET requestedId=${nextKeyboardId} returnedId=${selection.activeKeyboardId} ` +
          `returnedGeneration=${selection.keyboardGeneration} success=true reason=Ctrl+Shift+Z ` +
          `previousId=${current.activeKeyboardId}`);
      if (!this.ensureIpcKeyboardLoaded('MyanKey Ctrl+Shift+Z keyboard cycle')) {
        return;
      }
      this.showKeyboardSwitchFeedback(nextKeyboard.name);
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `MyanKey Ctrl+Shift+Z keyboard cycle failed: ${JSON.stringify(error)}`);
    }
  }

  /**
   * Uses the existing NAPI bridge replacement primitive. The bridge creates
   * and validates a fresh core engine before atomically swapping it into this
   * wrapper, so a bad KM2 never destroys the previous working engine.
   */
  private reloadSelectedKeyboard(selection: KeyboardSelection, reason: string): boolean {
    if (this.imeContext === undefined || !this.native.isCreated()) {
      return false;
    }
    let keyboard: KeyboardInfo;
    try {
      keyboard = this.keyboardManager.getKeyboardById(selection.activeKeyboardId);
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME KEYBOARD RELOAD keyboardId=${selection.activeKeyboardId} ` +
          `keyboardGeneration=${selection.keyboardGeneration} ` +
          `loadedIdBefore=${this.loadedKeyboardId === undefined ? '<none>' : this.loadedKeyboardId} ` +
          `loadedGenerationBefore=${this.loadedKeyboardGeneration} ` +
          `resource=<unmapped> sha256=<none> oldEngineId=<reported by native bridge> newEngineId=<none> ` +
          `success=false error=${JSON.stringify(error)}`);
      return false;
    }

    const previouslyLoadedId = this.loadedKeyboardId;
    const previousGeneration = this.loadedKeyboardGeneration;
    try {
      if (this.keyboardLoaded) {
        this.commitCompositionAndReset('keyboard generation change');
      } else {
        this.hideCompositionPopup();
      }
      const resource = this.keyboardManager.readBundledKeyboardResourceSync(this.imeContext, keyboard);
      this.native.loadKeyboardData(resource.data, selection.activeKeyboardId);
      this.native.resetEngine();
      this.loadedKeyboardId = resource.keyboard.id;
      this.loadedKeyboardGeneration = selection.keyboardGeneration;
      this.keyboardLoaded = true;
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME KEYBOARD RELOAD keyboardId=${selection.activeKeyboardId} ` +
          `keyboardGeneration=${selection.keyboardGeneration} ` +
          `loadedIdBefore=${previouslyLoadedId === undefined ? '<none>' : previouslyLoadedId} ` +
          `loadedGenerationBefore=${previousGeneration} ` +
          `resource=${resource.keyboard.resourcePath} sha256=${resource.sha256} ` +
          'oldEngineId=<reported by native bridge> newEngineId=<reported by native bridge> ' +
          `success=true reason=${reason}`);
      return true;
    } catch (error) {
      this.loadedKeyboardId = previouslyLoadedId;
      this.loadedKeyboardGeneration = previousGeneration;
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME KEYBOARD RELOAD keyboardId=${selection.activeKeyboardId} ` +
          `keyboardGeneration=${selection.keyboardGeneration} ` +
          `loadedIdBefore=${previouslyLoadedId === undefined ? '<none>' : previouslyLoadedId} ` +
          `loadedGenerationBefore=${previousGeneration} ` +
          `resource=${keyboard.resourcePath} sha256=<unavailable> ` +
          `oldEngineId=<reported by native bridge> newEngineId=<none> ` +
          `success=false error=${JSON.stringify(error)}`);
      return false;
    }
  }

  private logCompositionBoundaryCheck(
    event: InputMethodKeyEvent,
    keyCode: number,
    modifierOnly: boolean,
    processed: string,
    decision: string,
    reason: string,
  ): void {
    const action = event.action === Action.DOWN ? 'DOWN' : event.action === Action.UP ? 'UP' : 'CANCEL';
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `COMPOSITION BOUNDARY CHECK: rawKeyCode=${event.key.code} key=${keyCode} action=${action} ` +
      `modifierOnly=${modifierOnly} processed=${processed} ` +
      `compositionBefore=${this.formatTextWithCodePoints(this.internalComposition)} ` +
      `decision=${decision} reason=${reason}`);
  }

  private applyEngineOutput(
    inputClient: inputMethodEngine.InputClient,
    output: KeyMagicProcessResult,
    rawKeyCode: number,
  ): void {
    this.applyEngineOutputDirect(inputClient, output, rawKeyCode);
  }

  private applyEngineOutputDirect(
    inputClient: inputMethodEngine.InputClient,
    output: KeyMagicProcessResult,
    _rawKeyCode: number,
  ): void {
    // This is deliberately composition-first. No editor receives the live
    // KeyMagic buffer as ordinary document text.
    try {
      this.diagnosticPreviewActive = 'false';
      this.diagnosticTextSentToEditor =
        `internal composition: ${this.formatTextWithCodePoints(output.composingText)}`;
      this.diagnosticDirectEditResult = `internal composition ${this.formatTextWithCodePoints(output.composingText)}`;
      this.diagnosticDirectEditErrorCode = 'none';
      if (output.composingText.length > 0) {
        // Actual KeyMagic composition immediately takes precedence over a
        // transient layout-name notification in the same IME-owned panel.
        this.keyboardSwitchFeedback = '';
        this.keyboardSwitchFeedbackToken++;
        this.internalComposition = output.composingText;
        this.diagnosticDirectEditResult =
          `held: ${this.formatTextWithCodePoints(this.internalComposition)}`;
        this.appendDirectFallbackTrace(
          `INTERNAL COMPOSITION UPDATE: ${this.formatTextWithCodePoints(this.internalComposition)}; ` +
            'editor-mutation=none',
        );
      } else {
        // There is no active KeyMagic composition. Only these genuinely
        // non-composing results use the normal immediate editor primitives.
        this.internalComposition = '';
        this.applyNonComposingDirectOutput(inputClient, output);
      }
      this.publishCompositionPopup();
      this.publishTransportDiagnostics();
    } catch (error) {
      this.diagnosticDirectEditResult = `error: ${JSON.stringify(error)}`;
      this.diagnosticDirectEditErrorCode = this.errorCode(error);
      this.appendDirectFallbackTrace(
        `INTERNAL COMPOSITION ERROR: error=${JSON.stringify(error)} ` +
          `errorCode=${this.diagnosticDirectEditErrorCode}`,
      );
      this.internalComposition = '';
      this.publishCompositionPopup();
      this.publishTransportDiagnostics();
      throw new Error(`Unable to apply KeyMagic output to the active editor: ${JSON.stringify(error)}`);
    }
  }

  /** Direct behavior retained only when the engine has no composing buffer. */
  private applyNonComposingDirectOutput(
    inputClient: inputMethodEngine.InputClient,
    output: KeyMagicProcessResult,
  ): void {
    switch (output.actionType) {
      case KeyMagicActionType.None:
        return;
      case KeyMagicActionType.Insert:
        if (output.text.length > 0) {
          inputClient.insertTextSync(output.text);
        }
        return;
      case KeyMagicActionType.BackspaceDelete:
        if (output.deleteCount > 0) {
          inputClient.deleteBackwardSync(output.deleteCount);
        }
        return;
      case KeyMagicActionType.BackspaceDeleteAndInsert:
        if (output.deleteCount > 0) {
          inputClient.deleteBackwardSync(output.deleteCount);
        }
        if (output.text.length > 0) {
          inputClient.insertTextSync(output.text);
        }
        return;
      default:
        throw new Error(`Unsupported KeyMagic action ${output.actionType}.`);
    }
  }

  /**
   * Starts a synchronous direct editor transaction. The editor snapshot and
   * preceding engine synchronization establish the exact state from which a
   * macOS-style range replacement is attempted. There are no timing delays.
   */
  private beginDirectFallbackTransaction(
    inputClient: inputMethodEngine.InputClient,
    output: KeyMagicProcessResult,
  ): void {
    const before = this.captureDirectEditorSnapshot(inputClient);
    this.diagnosticDirectTrace =
      `DIRECT FALLBACK BEFORE:\n` +
      `editor=${this.diagnosticEditorIdentity}\n` +
      `last-reported-selection=${before.selection}; cursor=${this.describeCursor(before.cursor)}\n` +
      `text-before-cursor=${this.describeSnapshotText(before.textBefore)}\n` +
      `text-after-cursor=${this.describeSnapshotText(before.textAfter)}\n` +
      `Myanmar-artifacts-before-cursor=${this.describeMyanmarArtifacts(before.textBefore)}\n` +
      `Myanmar-artifacts-after-cursor=${this.describeMyanmarArtifacts(before.textAfter)}\n` +
      `snapshot-read-errors=${before.readErrors}\n` +
      `ENGINE/EDITOR SYNCHRONIZATION=${this.directEngineSynchronization}\n` +
      `ENGINE COMPOSITION BEFORE KEY=${this.describeSnapshotText(this.directEngineCompositionBeforeKey)}\n` +
      `EngineOutput.action=${this.actionName(output.actionType)}\n` +
      `EngineOutput.text=${this.formatTextWithCodePoints(output.text)}\n` +
      `EngineOutput.delete_count=${output.deleteCount}\n` +
      `EngineOutput.composition=${this.formatTextWithCodePoints(output.composingText)}`;
    this.expectedDirectSelectionChanges = [];
    this.expectedDirectTextChanges = [];
    this.publishDirectFallbackTrace('direct fallback before');
  }

  /**
   * Mirrors the macOS direct-mode preflight: compare Rust's composition with
   * the text immediately before the editor cursor before the next engine key.
   * A verified suffix keeps state; a mismatch seeds the existing engine FFI
   * with editor context; an unavailable context resets it. This is never run
   * for preview-capable editors.
   */
  private synchronizeDirectEngineWithEditor(inputClient: inputMethodEngine.InputClient): void {
    let engineComposition: string;
    this.directEngineCompositionBeforeKey = undefined;
    try {
      engineComposition = this.native.getComposition();
    } catch (error) {
      this.directEngineSynchronization = `failed to read engine composition: ${JSON.stringify(error)}`;
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `DIRECT ENGINE SYNC ${this.directEngineSynchronization}`);
      throw new Error(this.directEngineSynchronization);
    }
    this.directEngineCompositionBeforeKey = engineComposition;

    if (engineComposition.length === 0) {
      this.directEngineSynchronization = 'engine-composition=<empty>; action=kept-empty';
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `DIRECT ENGINE SYNC ${this.directEngineSynchronization}`);
      return;
    }

    let cursor: number;
    let editorBefore: string;
    try {
      cursor = inputClient.getTextIndexAtCursorSync();
      if (cursor < 0) {
        // Device evidence shows API-20 may use -1 to mean that this editor
        // does not expose its cursor through InputClient. It is not cursor 0
        // and must not reset a live KeyMagic composition between two keys.
        this.directEngineSynchronization =
          `engine-composition=${this.formatTextWithCodePoints(engineComposition)} cursor=${cursor} ` +
          'action=kept (cursor unavailable from editor)';
        hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
          `DIRECT ENGINE SYNC ${this.directEngineSynchronization}`);
        return;
      }
      if (cursor === 0) {
        this.native.resetEngine();
        this.directEngineCompositionBeforeKey = '';
        this.directEngineSynchronization =
          `engine-composition=${this.formatTextWithCodePoints(engineComposition)} cursor=${cursor} ` +
          'action=reset (no text before cursor)';
        hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
          `DIRECT ENGINE SYNC ${this.directEngineSynchronization}`);
        return;
      }
      editorBefore = inputClient.getForwardSync(DIRECT_ENGINE_CONTEXT_LENGTH);
    } catch (error) {
      this.native.resetEngine();
      this.directEngineCompositionBeforeKey = '';
      this.directEngineSynchronization =
        `engine-composition=${this.formatTextWithCodePoints(engineComposition)} action=reset ` +
        `because editor context is unavailable: ${JSON.stringify(error)}`;
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `DIRECT ENGINE SYNC ${this.directEngineSynchronization}`);
      return;
    }

    if (editorBefore.length > 0 &&
      (editorBefore.endsWith(engineComposition) || engineComposition.endsWith(editorBefore))) {
      this.directEngineSynchronization =
        `engine-composition=${this.formatTextWithCodePoints(engineComposition)} ` +
        `editor-before-cursor=${this.formatTextWithCodePoints(editorBefore)} ` +
        `cursor=${cursor} action=kept (suffix match)`;
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `DIRECT ENGINE SYNC ${this.directEngineSynchronization}`);
      return;
    }

    try {
      this.native.setComposition(editorBefore);
      this.directEngineCompositionBeforeKey = editorBefore;
      this.directEngineSynchronization =
        `engine-composition=${this.formatTextWithCodePoints(engineComposition)} ` +
        `editor-before-cursor=${this.formatTextWithCodePoints(editorBefore)} ` +
        `cursor=${cursor} action=seeded-from-editor-context`;
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `DIRECT ENGINE SYNC ${this.directEngineSynchronization}`);
    } catch (error) {
      this.native.resetEngine();
      this.directEngineCompositionBeforeKey = '';
      this.directEngineSynchronization =
        `engine-composition=${this.formatTextWithCodePoints(engineComposition)} action=reset ` +
        `because seeding editor context failed: ${JSON.stringify(error)}`;
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `DIRECT ENGINE SYNC ${this.directEngineSynchronization}`);
    }
  }

  /**
   * API-20 exposes no atomic range-replace primitive. This is the one direct
   * replacement transaction: two synchronous calls with immediate readback.
   */
  private applyDirectVerifiedDeleteAndInsert(
    inputClient: inputMethodEngine.InputClient,
    output: KeyMagicProcessResult,
    rawKeyCode: number,
  ): boolean {
    const deleteCount = output.deleteCount;
    const text = output.text;
    const before = this.captureDirectEditorSnapshot(inputClient);
    const textBefore = before.textBefore;
    const expectedComposition = this.directEngineCompositionBeforeKey;
    const targetText = this.targetTextFromBeforeCursor(textBefore, deleteCount);
    const expectedCursorAfterDelete = before.cursor === undefined ? undefined : before.cursor - deleteCount;
    const selectionIsSafe = before.selectionBegin === undefined || before.selectionEnd === undefined ||
      (before.selectionBegin === before.selectionEnd &&
        (before.cursor === undefined || before.selectionEnd === before.cursor));
    const compositionContextMatches = expectedComposition !== undefined && expectedComposition.length > 0 &&
      targetText !== undefined && expectedComposition.endsWith(targetText);
    const acknowledgedTargetText = expectedComposition === undefined || expectedComposition.length < deleteCount ?
      undefined : expectedComposition.slice(expectedComposition.length - deleteCount);
    const callbackAcknowledgementMatches = acknowledgedTargetText !== undefined &&
      acknowledgedTargetText.length === deleteCount && this.directAcknowledgedSuffix !== undefined &&
      this.directAcknowledgedSuffix.endsWith(acknowledgedTargetText);
    const readbackContextVerified = before.cursor !== undefined && before.cursor >= deleteCount &&
      textBefore !== undefined && compositionContextMatches;
    // When an editor explicitly returns the API-20 unavailable cursor sentinel,
    // use the preceding textChange acknowledgement rather than falsely treating
    // -1 as the start of the document. The later delete and insert callbacks
    // must still acknowledge their exact expected text before this transaction
    // completes.
    const contextVerified = selectionIsSafe && (readbackContextVerified || callbackAcknowledgementMatches);
    const contextEvidence = readbackContextVerified ? 'InputClient readback' :
      callbackAcknowledgementMatches ? 'IME textChange acknowledgement' : 'none';

    this.appendDirectFallbackTrace(
      `DIRECT DELETE BEFORE:\n` +
        `API=deleteBackwardSync; requested-delete-count=${deleteCount}; ` +
        `cursor=${this.describeCursor(before.cursor)}; last-reported-selection=${before.selection}; ` +
        `engine-composition-before-key=${this.describeSnapshotText(expectedComposition)}; ` +
        `target-text-before-cursor=${this.describeSnapshotText(targetText)}; ` +
        `text-before-cursor=${this.describeSnapshotText(textBefore)}; ` +
        `acknowledged-direct-suffix=${this.describeSnapshotText(this.directAcknowledgedSuffix)}; ` +
        `context-evidence=${contextEvidence}; context-verified=${contextVerified}; ` +
        `snapshot-read-errors=${before.readErrors}`,
    );
    if (!contextVerified) {
      throw new Error(
        'Refusing direct delete: the editor suffix does not exactly match the pre-key KeyMagic composition.',
      );
    }
    const verifiedTextBeforeDelete = textBefore !== undefined && textBefore.length >= deleteCount ?
      textBefore : this.directAcknowledgedSuffix;
    if (verifiedTextBeforeDelete === undefined || verifiedTextBeforeDelete.length < deleteCount) {
      throw new Error('Refusing direct delete: text-before-cursor became unavailable after preflight.');
    }
    const expectedTextAfterDelete = verifiedTextBeforeDelete.slice(0, verifiedTextBeforeDelete.length - deleteCount);
    const transaction = this.beginPendingDirectTransaction(
      'DELETE_AND_INSERT',
      'WAITING_DELETE_ACK',
      output,
      rawKeyCode,
      text,
      expectedCursorAfterDelete === undefined ? undefined : expectedCursorAfterDelete + text.length,
      targetText === undefined ? acknowledgedTargetText : targetText,
      verifiedTextBeforeDelete,
      expectedTextAfterDelete,
    );
    const afterDelete = this.applyDirectDelete(inputClient, deleteCount, 'deleteBackwardSync direct replacement');
    if (!this.acknowledgeDeleteIfVisible(transaction, afterDelete, 'immediate readback')) {
      this.appendDirectFallbackTrace(`DIRECT TX IMMEDIATE: id=${transaction.id} phase=${transaction.phase} result=pending`);
      return false;
    }
    return this.pendingDirectTransaction === undefined;
  }

  private applyDirectVerifiedInsert(
    inputClient: inputMethodEngine.InputClient,
    output: KeyMagicProcessResult,
    rawKeyCode: number,
    operation: string,
  ): boolean {
    const text = output.text;
    const before = this.captureDirectEditorSnapshot(inputClient);
    const transaction = this.beginPendingDirectTransaction(
      'INSERT',
      'WAITING_INSERT_ACK',
      output,
      rawKeyCode,
      text,
      before.cursor === undefined ? undefined : before.cursor + text.length,
      undefined,
      before.textBefore,
      undefined,
    );
    const after = this.applyDirectInsert(inputClient, text, operation);
    if (this.acknowledgeFinalInsertIfVisible(transaction, after, 'immediate readback')) {
      return true;
    }
    this.appendDirectFallbackTrace(`DIRECT TX IMMEDIATE: id=${transaction.id} phase=${transaction.phase} result=pending`);
    return false;
  }

  private applyDirectVerifiedDelete(
    inputClient: inputMethodEngine.InputClient,
    output: KeyMagicProcessResult,
    rawKeyCode: number,
    operation: string,
  ): boolean {
    const deleteCount = output.deleteCount;
    const before = this.captureDirectEditorSnapshot(inputClient);
    const textBefore = before.textBefore;
    if (before.cursor === undefined || textBefore === undefined || before.cursor < deleteCount ||
      textBefore.length < deleteCount) {
      throw new Error('Refusing direct delete: cursor/text-before-cursor cannot verify the requested delete count.');
    }
    const expectedTextAfterDelete = textBefore.slice(0, textBefore.length - deleteCount);
    const transaction = this.beginPendingDirectTransaction(
      'DELETE',
      'WAITING_DELETE_ACK',
      output,
      rawKeyCode,
      '',
      before.cursor - deleteCount,
      textBefore.slice(textBefore.length - deleteCount),
      textBefore,
      expectedTextAfterDelete,
    );
    const after = this.applyDirectDelete(inputClient, deleteCount, operation);
    if (this.acknowledgeDeleteIfVisible(transaction, after, 'immediate readback')) {
      return true;
    }
    this.appendDirectFallbackTrace(`DIRECT TX IMMEDIATE: id=${transaction.id} phase=${transaction.phase} result=pending`);
    return false;
  }

  private beginPendingDirectTransaction(
    kind: DirectTransactionKind,
    phase: DirectTransactionPhase,
    output: KeyMagicProcessResult,
    rawKeyCode: number,
    expectedFinalSuffix: string,
    expectedCursor: number | undefined,
    expectedDeletedSuffix: string | undefined,
    expectedTextBeforeDelete: string | undefined,
    expectedTextAfterDelete: string | undefined,
  ): PendingDirectTransaction {
    if (this.pendingDirectTransaction !== undefined) {
      throw new Error('Cannot begin a direct transaction while another transaction is pending.');
    }
    const transaction: PendingDirectTransaction = {
      id: this.nextDirectTransactionId++,
      kind,
      phase,
      expectedFinalSuffix,
      expectedCursor,
      expectedDeletedSuffix,
      expectedTextBeforeDelete,
      expectedTextAfterDelete,
      originalOutput: output,
      originatingRawKeyCode: rawKeyCode,
    };
    this.pendingDirectTransaction = transaction;
    this.appendDirectFallbackTrace(
      `DIRECT TX BEGIN: id=${transaction.id}; kind=${kind}; phase=${phase}; rawKeyCode=${rawKeyCode}; ` +
        `expected-final-suffix=${this.formatTextWithCodePoints(expectedFinalSuffix)}; ` +
        `expected-cursor=${this.describeCursor(expectedCursor)}; ` +
        `expected-deleted-suffix=${this.describeSnapshotText(expectedDeletedSuffix)}`,
    );
    return transaction;
  }

  private acknowledgeDeleteIfVisible(
    transaction: PendingDirectTransaction,
    snapshot: DirectEditorSnapshot,
    source: string,
    callbackText?: string,
  ): boolean {
    if (this.pendingDirectTransaction === undefined || this.pendingDirectTransaction.id !== transaction.id ||
      transaction.phase !== 'WAITING_DELETE_ACK' || !this.isExpectedDeleteStateVisible(transaction, snapshot, callbackText)) {
      return false;
    }
    this.appendDirectFallbackTrace(
      `DIRECT TX ACK: id=${transaction.id}; phase=WAITING_DELETE_ACK; source=${source}; ` +
        `observed-text-before-cursor=${this.describeSnapshotText(snapshot.textBefore)}; ` +
        `observed-cursor=${this.describeCursor(snapshot.cursor)}`,
    );
    if (transaction.kind === 'DELETE') {
      this.completePendingDirectTransaction(transaction, 'delete acknowledged');
      return true;
    }

    this.changePendingDirectTransactionPhase(transaction, 'WAITING_FINAL_INSERT_ACK', 'delete acknowledged');
    const client = this.inputClient;
    if (client === undefined) {
      this.contradictPendingDirectTransaction('input client disappeared before final insert');
      return false;
    }
    const afterInsert = this.applyDirectInsert(client, transaction.expectedFinalSuffix,
      'insertTextSync after acknowledged direct delete');
    if (this.acknowledgeFinalInsertIfVisible(transaction, afterInsert, 'immediate readback after acknowledged delete')) {
      return true;
    }
    this.appendDirectFallbackTrace(
      `DIRECT TX IMMEDIATE: id=${transaction.id}; phase=WAITING_FINAL_INSERT_ACK; result=pending`,
    );
    return true;
  }

  private acknowledgeFinalInsertIfVisible(
    transaction: PendingDirectTransaction,
    snapshot: DirectEditorSnapshot,
    source: string,
    callbackText?: string,
  ): boolean {
    if (this.pendingDirectTransaction === undefined || this.pendingDirectTransaction.id !== transaction.id ||
      (transaction.phase !== 'WAITING_INSERT_ACK' && transaction.phase !== 'WAITING_FINAL_INSERT_ACK') ||
      !this.isExpectedFinalInsertStateVisible(transaction, snapshot, callbackText)) {
      return false;
    }
    this.appendDirectFallbackTrace(
      `DIRECT TX ACK: id=${transaction.id}; phase=${transaction.phase}; source=${source}; ` +
        `observed-text-before-cursor=${this.describeSnapshotText(snapshot.textBefore)}; ` +
        `observed-cursor=${this.describeCursor(snapshot.cursor)}`,
    );
    this.directAcknowledgedSuffix = transaction.expectedFinalSuffix;
    this.completePendingDirectTransaction(transaction, 'final insert acknowledged');
    return true;
  }

  private isExpectedDeleteStateVisible(
    transaction: PendingDirectTransaction,
    snapshot: DirectEditorSnapshot,
    callbackText: string | undefined,
  ): boolean {
    const observed = callbackText === undefined ? snapshot.textBefore : callbackText;
    if (observed === undefined || transaction.expectedDeletedSuffix === undefined ||
      transaction.expectedTextAfterDelete === undefined) {
      return false;
    }
    if (observed.endsWith(transaction.expectedDeletedSuffix)) {
      return false;
    }
    if (transaction.expectedTextAfterDelete.length > 0 && !observed.endsWith(transaction.expectedTextAfterDelete)) {
      return false;
    }
    // A callback's text is authoritative even if an editor's synchronous
    // cursor query is still stale. Cursor remains logged for diagnosis but
    // cannot turn an acknowledged document edit into a false failure.
    return true;
  }

  private isExpectedFinalInsertStateVisible(
    transaction: PendingDirectTransaction,
    snapshot: DirectEditorSnapshot,
    callbackText: string | undefined,
  ): boolean {
    const observed = callbackText === undefined ? snapshot.textBefore : callbackText;
    return observed !== undefined && observed.endsWith(transaction.expectedFinalSuffix);
  }

  private changePendingDirectTransactionPhase(
    transaction: PendingDirectTransaction,
    phase: DirectTransactionPhase,
    reason: string,
  ): void {
    if (this.pendingDirectTransaction === undefined || this.pendingDirectTransaction.id !== transaction.id) {
      return;
    }
    transaction.phase = phase;
    this.appendDirectFallbackTrace(`DIRECT TX PHASE: id=${transaction.id}; phase=${phase}; reason=${reason}`);
  }

  private reconcilePendingDirectTransaction(source: string, callbackText?: string): void {
    const transaction = this.pendingDirectTransaction;
    const client = this.inputClient;
    if (transaction === undefined) {
      return;
    }
    if (client === undefined) {
      this.contradictPendingDirectTransaction(`no input client during ${source}`);
      return;
    }
    const snapshot = this.captureDirectEditorSnapshot(client);
    if (transaction.phase === 'WAITING_DELETE_ACK') {
      this.acknowledgeDeleteIfVisible(transaction, snapshot, source, callbackText);
      return;
    }
    this.acknowledgeFinalInsertIfVisible(transaction, snapshot, source, callbackText);
  }

  private completePendingDirectTransaction(transaction: PendingDirectTransaction, reason: string): void {
    if (this.pendingDirectTransaction === undefined || this.pendingDirectTransaction.id !== transaction.id) {
      return;
    }
    this.pendingDirectTransaction = undefined;
    this.appendDirectFallbackTrace(`DIRECT TX COMPLETE: id=${transaction.id}; kind=${transaction.kind}; reason=${reason}`);
    this.drainQueuedPhysicalDowns();
  }

  private contradictPendingDirectTransaction(reason: string): void {
    const transaction = this.pendingDirectTransaction;
    if (transaction === undefined) {
      return;
    }
    this.pendingDirectTransaction = undefined;
    this.queuedPhysicalDowns = [];
    this.appendDirectFallbackTrace(
      `DIRECT TX CONTRADICTION: id=${transaction.id}; phase=${transaction.phase}; reason=${reason}`,
    );
    this.resetForInputSession(`direct transaction contradiction: ${reason}`);
  }

  private queuePhysicalDownForPendingTransaction(event: InputMethodKeyEvent): void {
    this.queuedPhysicalDowns.push({ event });
    this.markHandledPhysicalDown(event);
    const transactionId = this.pendingDirectTransaction === undefined ? '<none>' : `${this.pendingDirectTransaction.id}`;
    this.appendDirectFallbackTrace(
      `DIRECT TX QUEUED KEY: tx=${transactionId}; rawKeyCode=${event.key.code}; ` +
        `queue-depth=${this.queuedPhysicalDowns.length}; action=DOWN; returned-consumed=true`,
    );
  }

  private drainQueuedPhysicalDowns(): void {
    while (this.pendingDirectTransaction === undefined && this.queuedPhysicalDowns.length > 0) {
      const queued = this.queuedPhysicalDowns.shift();
      if (queued === undefined) {
        return;
      }
      this.handlePhysicalKeyEvent(queued.event, true);
    }
  }

  private applyDirectDelete(
    inputClient: inputMethodEngine.InputClient,
    deleteCount: number,
    operation: string,
  ): DirectEditorSnapshot {
    this.directFallbackOperationInProgress = operation;
    this.directSelectionCallbackObserved = false;
    this.directTextCallbackObserved = false;
    this.diagnosticDirectEditResult = `calling ${operation}: count=${deleteCount}`;
    this.appendDirectFallbackTrace(
      `DIRECT DELETE:\nAPI=${operation}; requested-delete-count=${deleteCount}; result=pending`,
    );
    try {
      inputClient.deleteBackwardSync(deleteCount);
      const after = this.captureDirectEditorSnapshot(inputClient);
      this.queueExpectedDirectCallbacks(operation, after);
      this.directFallbackOperationInProgress = undefined;
      this.diagnosticDirectEditResult = `success: ${operation} count=${deleteCount}`;
      this.appendDirectFallbackTrace(
        `DIRECT DELETE RESULT:\nAPI=${operation}; requested-delete-count=${deleteCount}; ` +
          `result=success; selection=${after.selection}; cursor=${this.describeCursor(after.cursor)}; ` +
          `text-before-cursor=${this.describeSnapshotText(after.textBefore)}; ` +
          `text-after-cursor=${this.describeSnapshotText(after.textAfter)}; ` +
          `snapshot-read-errors=${after.readErrors}`,
      );
      return after;
    } catch (error) {
      this.directFallbackOperationInProgress = undefined;
      this.appendDirectFallbackTrace(
        `DIRECT DELETE RESULT:\nAPI=${operation}; requested-delete-count=${deleteCount}; ` +
          `result=error; error=${JSON.stringify(error)}; errorCode=${this.errorCode(error)}`,
      );
      throw new Error(JSON.stringify(error));
    }
  }

  private applyDirectInsert(
    inputClient: inputMethodEngine.InputClient,
    text: string,
    operation: string,
  ): DirectEditorSnapshot {
    this.directFallbackOperationInProgress = operation;
    this.directSelectionCallbackObserved = false;
    this.directTextCallbackObserved = false;
    this.diagnosticDirectEditResult = `calling ${operation}: ${this.formatTextWithCodePoints(text)}`;
    this.appendDirectFallbackTrace(
      `DIRECT INSERT:\nAPI=${operation}; text=${this.formatTextWithCodePoints(text)}; result=pending`,
    );
    try {
      inputClient.insertTextSync(text);
      const after = this.captureDirectEditorSnapshot(inputClient);
      this.queueExpectedDirectCallbacks(operation, after);
      this.directFallbackOperationInProgress = undefined;
      this.diagnosticDirectEditResult = `success: ${operation} ${this.formatTextWithCodePoints(text)}`;
      this.appendDirectFallbackTrace(
        `DIRECT INSERT RESULT:\nAPI=${operation}; text=${this.formatTextWithCodePoints(text)}; ` +
          `result=success; last-reported-selection=${after.selection}; cursor=${this.describeCursor(after.cursor)}; ` +
          `text-before-cursor=${this.describeSnapshotText(after.textBefore)}; ` +
          `text-after-cursor=${this.describeSnapshotText(after.textAfter)}; ` +
          `Myanmar-artifacts-before-cursor=${this.describeMyanmarArtifacts(after.textBefore)}; ` +
          `Myanmar-artifacts-after-cursor=${this.describeMyanmarArtifacts(after.textAfter)}; ` +
          `snapshot-read-errors=${after.readErrors}`,
      );
      return after;
    } catch (error) {
      this.directFallbackOperationInProgress = undefined;
      this.appendDirectFallbackTrace(
        `DIRECT INSERT RESULT:\nAPI=${operation}; text=${this.formatTextWithCodePoints(text)}; ` +
          `result=error; error=${JSON.stringify(error)}; errorCode=${this.errorCode(error)}`,
      );
      throw new Error(JSON.stringify(error));
    }
  }

  private finishDirectFallbackTransaction(inputClient: inputMethodEngine.InputClient): void {
    const after = this.captureDirectEditorSnapshot(inputClient);
    this.appendDirectFallbackTrace(
      `DIRECT FALLBACK AFTER:\nselection=${after.selection}; cursor=${this.describeCursor(after.cursor)}; ` +
        `text-before-cursor=${this.describeSnapshotText(after.textBefore)}; ` +
        `text-after-cursor=${this.describeSnapshotText(after.textAfter)}; ` +
        `Myanmar-artifacts-before-cursor=${this.describeMyanmarArtifacts(after.textBefore)}; ` +
        `Myanmar-artifacts-after-cursor=${this.describeMyanmarArtifacts(after.textAfter)}; ` +
        `snapshot-read-errors=${after.readErrors}; ` +
        `selection-callback-during-transaction=${this.directSelectionCallbackObserved}; ` +
        `text-callback-during-transaction=${this.directTextCallbackObserved}`,
    );
  }

  private findHandledPhysicalKey(rawKeyCode: number): HandledPhysicalKeyState | undefined {
    for (let index = 0; index < this.handledPhysicalKeys.length; index++) {
      const candidate = this.handledPhysicalKeys[index];
      if (candidate.rawKeyCode === rawKeyCode) {
        return candidate;
      }
    }
    return undefined;
  }

  /** Removes and returns only the exact successfully handled DOWN state. */
  private takeHandledPhysicalKeyUp(rawKeyCode: number): HandledPhysicalKeyState | undefined {
    for (let index = 0; index < this.handledPhysicalKeys.length; index++) {
      const candidate = this.handledPhysicalKeys[index];
      if (candidate.rawKeyCode === rawKeyCode) {
        this.handledPhysicalKeys.splice(index, 1);
        return candidate;
      }
    }
    return undefined;
  }

  private markHandledPhysicalDown(event: InputMethodKeyEvent): void {
    const existing = this.findHandledPhysicalKey(event.key.code);
    if (existing !== undefined) {
      existing.repeatCount++;
      return;
    }
    this.handledPhysicalKeys.push({
      rawKeyCode: event.key.code,
      firstPressedTime: event.key.pressedTime,
      repeatCount: 0,
    });
  }

  /**
   * API-20 KeyEvent exposes actionTime and key.pressedTime but no documented
   * repeat flag/count. Repeat is therefore reported only as an explicit
   * inference from an outstanding handled DOWN with the same raw key code.
   */
  private finishPhysicalKeyEvent(
    event: InputMethodKeyEvent,
    processed: string,
    directTransaction: string,
    consumed: boolean,
    matchedHandledDown: boolean,
    repeat: boolean,
    repeatCount: number,
  ): boolean {
    const action = event.action === Action.DOWN ? 'DOWN' : event.action === Action.UP ? 'UP' : 'CANCEL';
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `IME PHYSICAL EVENT: action=${action} rawKeyCode=${event.key.code} ` +
      `pressedTime=${event.key.pressedTime} actionTime=${event.actionTime} ` +
      `repeat=${repeat} repeatCount=${repeatCount} repeatSource=inferred-no-api20-repeat-field ` +
      `processed=${processed} direct-transaction=${directTransaction} ` +
      `returned-consumed=${consumed} matched-handled-DOWN=${matchedHandledDown}`);
    return consumed;
  }

  private recordHandledPhysicalKey(
    event: InputMethodKeyEvent,
    input: KeyMagicKeyInput,
    inputClient: inputMethodEngine.InputClient,
    directTransactionStatus: string,
    fromPendingQueue: boolean,
  ): void {
    const snapshot = this.captureDirectEditorSnapshot(inputClient);
    const character = input.character === undefined ? '' : input.character;
    if (!fromPendingQueue) {
      this.markHandledPhysicalDown(event);
    }
    if (directTransactionStatus !== 'not-run') {
      this.directRawTextLeakProbe = {
        rawKeyCode: event.key.code,
        character,
        expectedTextBeforeCursor: snapshot.textBefore,
      };
    }
    this.appendDirectFallbackTrace(
      `IME HANDLED PHYSICAL DOWN: rawKeyCode=${event.key.code}; ` +
      `action=DOWN; mappedKeyMagicCode=${input.keyCode}; ` +
      `character=${this.formatTextWithCodePoints(character)}; returned-consumed=true; ` +
        `direct-transaction=${directTransactionStatus}; paired-UP=will-consume; ` +
        `expected-ime-text-before-cursor=${this.describeSnapshotText(snapshot.textBefore)}`,
    );
  }

  /**
   * The keyboard delegate only reports a text string, not its source event.
   * An observed post-transaction string containing
   * the exact handled Latin character but differing from our synchronous
   * editor readback is strong evidence that the original raw event reached
   * the editor. This is diagnostics only; it never mutates editor text.
   */
  private takeDirectRawTextLeak(text: string): DirectRawTextLeakProbe | undefined {
    const probe = this.directRawTextLeakProbe;
    if (probe === undefined) {
      return undefined;
    }
    if (probe.character.length === 0 || text === probe.expectedTextBeforeCursor ||
      text.indexOf(probe.character) < 0) {
      return undefined;
    }
    this.directRawTextLeakProbe = undefined;
    return probe;
  }

  private captureDirectEditorSnapshot(inputClient: inputMethodEngine.InputClient): DirectEditorSnapshot {
    let cursor: number | undefined;
    let textBefore: string | undefined;
    let textAfter: string | undefined;
    const errors: string[] = [];
    try {
      const reportedCursor = inputClient.getTextIndexAtCursorSync();
      if (reportedCursor >= 0) {
        cursor = reportedCursor;
      } else {
        errors.push(`getTextIndexAtCursorSync=unavailable(${reportedCursor})`);
      }
    } catch (error) {
      errors.push(`getTextIndexAtCursorSync=${this.errorCode(error)}`);
    }
    try {
      textBefore = inputClient.getForwardSync(DIRECT_TEXT_SNAPSHOT_LENGTH);
    } catch (error) {
      errors.push(`getForwardSync=${this.errorCode(error)}`);
    }
    try {
      textAfter = inputClient.getBackwardSync(DIRECT_TEXT_SNAPSHOT_LENGTH);
    } catch (error) {
      errors.push(`getBackwardSync=${this.errorCode(error)}`);
    }
    return {
      cursor,
      selection: this.describeLastSelection(),
      selectionBegin: this.lastSelectionBegin,
      selectionEnd: this.lastSelectionEnd,
      textBefore,
      textAfter,
      readErrors: errors.length === 0 ? 'none' : errors.join(', '),
    };
  }

  private queueExpectedDirectCallbacks(operation: string, after: DirectEditorSnapshot): void {
    if (!this.directSelectionCallbackObserved && after.cursor !== undefined) {
      this.expectDirectSelectionChange(operation, after.cursor, after.cursor);
    }
    if (!this.directTextCallbackObserved) {
      this.expectedDirectTextChanges.push({ operation, expectedText: after.textBefore });
    }
  }

  private takeExpectedDirectSelectionChange(newBegin: number, newEnd: number): ExpectedDirectSelectionChange | undefined {
    for (let index = 0; index < this.expectedDirectSelectionChanges.length; index++) {
      const candidate = this.expectedDirectSelectionChanges[index];
      if (candidate.expectedBegin === newBegin && candidate.expectedEnd === newEnd) {
        this.expectedDirectSelectionChanges.splice(index, 1);
        return candidate;
      }
    }
    return undefined;
  }

  private expectDirectSelectionChange(operation: string, expectedBegin: number, expectedEnd: number): void {
    this.expectedDirectSelectionChanges.push({ operation, expectedBegin, expectedEnd });
  }

  private takeExpectedDirectTextChange(observedText: string): ExpectedDirectTextChange | undefined {
    // Delete and insert are synchronous, but their callbacks may be deferred
    // and coalesced. Match any readback state from this transaction instead
    // of assuming the delete callback arrives before the insert callback.
    // This still refuses to hide a raw Latin leak behind a guessed callback.
    for (let index = 0; index < this.expectedDirectTextChanges.length; index++) {
      const candidate = this.expectedDirectTextChanges[index];
      if (candidate.expectedText !== undefined && candidate.expectedText === observedText) {
        this.expectedDirectTextChanges.splice(index, 1);
        return candidate;
      }
    }
    return undefined;
  }

  private describeLastSelection(): string {
    if (this.lastSelectionBegin === undefined || this.lastSelectionEnd === undefined) {
      return '<unavailable: no selectionChange callback received>';
    }
    return `${this.lastSelectionBegin},${this.lastSelectionEnd}`;
  }

  private describeCursor(cursor: number | undefined): string {
    return cursor === undefined ? '<unavailable>' : `${cursor}`;
  }

  private describeSnapshotText(text: string | undefined): string {
    return text === undefined ? '<unavailable>' : this.formatTextWithCodePoints(text);
  }

  private describeMyanmarArtifacts(text: string | undefined): string {
    if (text === undefined) {
      return '<unavailable>';
    }
    const hasHairSpace = text.indexOf('\u200A') >= 0;
    const hasEeVowel = text.indexOf('\u1031') >= 0;
    const hasDottedCircle = text.indexOf('\u25CC') >= 0;
    return `U+200A=${hasHairSpace}; U+1031=${hasEeVowel}; U+25CC=${hasDottedCircle}`;
  }

  private targetTextFromBeforeCursor(textBefore: string | undefined, deleteCount: number): string | undefined {
    if (textBefore === undefined || textBefore.length < deleteCount) {
      return undefined;
    }
    return textBefore.slice(textBefore.length - deleteCount);
  }

  private recordDirectFallbackCallback(type: string, detail: string): void {
    this.appendDirectFallbackTrace(`DIRECT FALLBACK CALLBACK ${type}: ${detail}`);
  }

  private appendDirectFallbackTrace(line: string): void {
    this.diagnosticDirectTrace = `${this.diagnosticDirectTrace}\n${line}`;
    this.publishDirectFallbackTrace('direct fallback trace');
    // Keep HiLog useful on device: the diagnostic panel retains the cumulative
    // trace, while each log record contains only the newly appended event.
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s', line);
  }

  private publishDirectFallbackTrace(reason: string): void {
    AppStorage.setOrCreate(DIAGNOSTIC_DIRECT_TRACE, this.diagnosticDirectTrace);
    this.publishTransportDiagnostics(reason);
  }

  /**
   * Publishes the IME-owned composition to the floating panel. This observer
   * deliberately contains no KeyMagic or InputClient document operation.
   */
  private publishCompositionPopup(): void {
    const presentationText = this.popupPresentationText();
    const visible = this.inputClient !== undefined && presentationText.length > 0;
    const generation = ++this.compositionPopupGeneration;
    const composition = visible ? presentationText : '';
    this.compositionPopupLatestComposition = composition;

    // Text is authoritative. Publish this exact EngineOutput composition before
    // any panel measurement or native resize request, including the first
    // character. Geometry may complete later, but it may never hold back UI.
    this.publishCompositionPopupState(visible, composition, generation);
    this.logCompositionPopupPublication(generation, composition);
    this.logCompositionPopupRenderTrace(generation);

    if (visible) {
      this.showCompositionPopup(generation);
    } else {
      this.hideCompositionPopup();
    }
  }

  private popupPresentationText(): string {
    return this.keyboardSwitchFeedback.length > 0 ? this.keyboardSwitchFeedback : this.internalComposition;
  }

  private hasPopupPresentationText(): boolean {
    return this.popupPresentationText().length > 0;
  }

  /** Brief IME-owned notification after a successful internal keyboard cycle. */
  private showKeyboardSwitchFeedback(keyboardName: string): void {
    const token = ++this.keyboardSwitchFeedbackToken;
    this.keyboardSwitchFeedback = keyboardName;
    this.publishCompositionPopup();
    setTimeout(() => {
      if (token !== this.keyboardSwitchFeedbackToken) {
        return;
      }
      this.keyboardSwitchFeedback = '';
      this.publishCompositionPopup();
    }, KEYBOARD_SWITCH_FEEDBACK_DURATION_MS);
  }

  private showCompositionPopup(generation: number = this.compositionPopupGeneration): void {
    if (this.panel === undefined || this.inputClient === undefined ||
      this.compositionPopupLatestComposition.length === 0) {
      return;
    }
    // Panel geometry is eventually consistent presentation work. It receives
    // the latest composition but never publishes or replaces popup text.
    if (!this.positionCompositionPopup()) {
      return;
    }
    this.logCompositionPopupRenderTrace(generation);
    const rect = this.compositionPopupRect;
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `POPUP SHOW generation=${generation} targetWidth=${rect === undefined ? '<unknown>' : rect.width} ` +
        `targetHeight=${rect === undefined ? '<unknown>' : rect.height} ` +
        `x=${rect === undefined ? '<unknown>' : rect.left} ` +
        `y=${rect === undefined ? '<unknown>' : rect.top}`);
    if (!this.compositionPopupShown) {
      this.compositionPopupShown = true;
      this.showPanel();
    }
  }

  /** Publishes an immutable composition revision to ArkUI immediately. */
  private publishCompositionPopupState(
    visible: boolean,
    composition: string,
    generation: number,
  ): void {
    if (generation < this.compositionPopupUiGeneration) {
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `POPUP COMPOSITION discardedGeneration=${generation} ` +
          `uiGeneration=${this.compositionPopupUiGeneration}`);
      return;
    }
    this.compositionPopupUiGeneration = generation;
    this.compositionPopupUiComposition = composition;
    AppStorage.setOrCreate(COMPOSITION_POPUP_VISIBLE, visible ? 'true' : 'false');
    AppStorage.setOrCreate(COMPOSITION_POPUP_TEXT, composition);
    AppStorage.setOrCreate(COMPOSITION_POPUP_TRANSPORT, this.currentTransport());
    AppStorage.setOrCreate(COMPOSITION_POPUP_SESSION, `${this.compositionPopupSession}`);
  }

  private logCompositionPopupPublication(generation: number, engineComposition: string): void {
    const exactMatch = engineComposition === this.compositionPopupUiComposition &&
      generation === this.compositionPopupUiGeneration;
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `POPUP COMPOSITION generation=${generation} ` +
        `engineComposition=${this.formatTextWithCodePoints(engineComposition)} ` +
        `uiComposition=${this.formatTextWithCodePoints(this.compositionPopupUiComposition)} ` +
        `exactMatch=${exactMatch}`);
  }

  /**
   * Separates authoritative published text from eventual native panel size.
   * A missing actual size merely means the system has not acknowledged the
   * presentation request yet; it never changes the text revision.
   */
  private logCompositionPopupRenderTrace(generation: number): void {
    const layout = this.compositionPopupLastLayout;
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `POPUP RENDER TRACE generation=${generation} ` +
        `engineComposition=${this.formatTextWithCodePoints(this.compositionPopupLatestComposition)} ` +
        `publishedComposition=${this.formatTextWithCodePoints(this.compositionPopupUiComposition)} ` +
        `publishedCodepointCount=${this.compositionPopupCodePointCount(this.compositionPopupUiComposition)} ` +
        `desiredWidthPx=${layout === undefined ? '<pending>' : layout.targetSize.width} ` +
        `desiredHeightPx=${layout === undefined ? '<pending>' : layout.targetSize.height} ` +
        `actualPanelWidthPx=${this.compositionPopupActualWidth === undefined ? '<pending>' : this.compositionPopupActualWidth} ` +
        `actualPanelHeightPx=${this.compositionPopupActualHeight === undefined ? '<pending>' : this.compositionPopupActualHeight} ` +
        `lineCount=${layout === undefined || layout.lineCount === undefined ? '<pending>' : layout.lineCount}`);
  }

  private hideCompositionPopup(): void {
    this.compositionPopupShown = false;
    if (this.panel !== undefined) {
      this.hidePanel();
    }
  }

  /** Positions below the public cursor-context position, when one is available. */
  private positionCompositionPopup(): boolean {
    if (this.panel === undefined || this.inputClient === undefined ||
      this.compositionPopupLatestComposition.length === 0) {
      return false;
    }

    const popupSize = this.compositionPopupSize(this.compositionPopupLatestComposition);
    if (this.compositionPopupCursorX !== undefined && this.compositionPopupCursorY !== undefined &&
      this.compositionPopupCursorHeight !== undefined) {
      // A cursor point alone has no public display bounds. Wait for the
      // calling-window rectangle so the caret-relative panel can be clamped
      // instead of briefly appearing outside the focused window.
      if (this.compositionPopupWindowRect === undefined) {
        this.requestCompositionPopupWindowPosition();
        return false;
      }
      const caretGap = this.compositionPopupVpToPx(COMPOSITION_POPUP_CARET_GAP);
      const below = this.compositionPopupCursorY + Math.max(1, this.compositionPopupCursorHeight) +
        caretGap;
      let left = this.compositionPopupCursorX;
      let top = below;
      const windowRect = this.compositionPopupWindowRect;
      const right = windowRect.left + windowRect.width;
      const bottom = windowRect.top + windowRect.height;
      left = this.clampCompositionPopupCoordinate(left, windowRect.left, right - popupSize.width);
      const above = this.compositionPopupCursorY - caretGap - popupSize.height;
      top = below + popupSize.height <= bottom ? below : above;
      top = this.clampCompositionPopupCoordinate(top, windowRect.top, bottom - popupSize.height);
      this.compositionPopupRect = {
        left,
        top,
        width: popupSize.width,
        height: popupSize.height,
      };
    } else if (this.compositionPopupRect !== undefined) {
      this.compositionPopupRect = this.clampCompositionPopupRectToWindow({
        left: this.compositionPopupRect.left,
        top: this.compositionPopupRect.top,
        width: popupSize.width,
        height: popupSize.height,
      });
    } else if (this.compositionPopupWindowRect !== undefined) {
      // No caret geometry has arrived yet. Use the public calling-window
      // fallback, but still apply the fully measured incoming size before the
      // panel is shown for the first composition character.
      this.compositionPopupRect = this.defaultCompositionPopupRect(popupSize);
    } else {
      this.requestCompositionPopupWindowPosition();
      return false;
    }

    this.applyCompositionPopupRect(this.compositionPopupRect);
    return true;
  }

  /**
   * `cursorContextChange` is the preferred public caret geometry source. If a
   * client has not published it yet, the public calling-window rectangle gives
   * the native generic lower-window fallback without inventing coordinates.
   */
  private requestCompositionPopupWindowPosition(): void {
    if (this.compositionPopupWindowPositionRequested || this.inputClient === undefined) {
      return;
    }
    this.compositionPopupWindowPositionRequested = true;
    const session = this.compositionPopupSession;
    const inputClient = this.inputClient;
    inputClient.getCallingWindowInfo().then((windowInfo) => {
      if (session !== this.compositionPopupSession) {
        return;
      }
      this.compositionPopupWindowPositionRequested = false;
      this.compositionPopupWindowRect = {
        left: windowInfo.rect.left,
        top: windowInfo.rect.top,
        width: windowInfo.rect.width,
        height: windowInfo.rect.height,
      };
      if (!this.hasPopupPresentationText()) {
        return;
      }
      // showCompositionPopup() will calculate the new composition rect before
      // it publishes the text to ArkUI. Do not pre-render into a default size.
      this.showCompositionPopup();
    }).catch((error: Object) => {
      this.compositionPopupWindowPositionRequested = false;
      if (session !== this.compositionPopupSession || !this.hasPopupPresentationText() ||
        this.panel === undefined) {
        return;
      }
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `Unable to obtain calling-window geometry for composition panel: ${JSON.stringify(error)}`);
      // The system keeps its native floating-panel placement when the focused
      // client declines geometry. No application-specific coordinate is used.
      if (!this.compositionPopupShown) {
        this.compositionPopupShown = true;
        this.showPanel();
      }
    });
  }

  /**
   * Measures the panel's requested size from the exact composition text. The
   * width keeps normal syllables compact, while full-height line boxes keep
   * every wrapped Myanmar line inside the focused application's available area.
   */
  private compositionPopupSize(composition: string): CompositionPopupSize {
    const maxWidth = this.compositionPopupMaxWidth();
    const horizontalPadding = this.compositionPopupVpToPx(COMPOSITION_POPUP_HORIZONTAL_PADDING);
    const horizontalSafetyAllowance = this.compositionPopupVpToPx(
      COMPOSITION_POPUP_HORIZONTAL_SAFETY_ALLOWANCE,
    );
    const lineHeight = this.compositionPopupVpToPx(COMPOSITION_POPUP_LINE_HEIGHT);
    const minWidth = Math.min(this.compositionPopupVpToPx(COMPOSITION_POPUP_MIN_WIDTH), maxWidth);
    const maxContentWidth = Math.max(1, maxWidth - horizontalPadding * 2 - horizontalSafetyAllowance);
    const maxHeight = this.compositionPopupMaxHeight();
    const minHeight = Math.min(this.compositionPopupVpToPx(COMPOSITION_POPUP_MIN_HEIGHT), maxHeight);

    try {
      const singleLineWidth = MeasureText.measureText({
        textContent: composition,
        fontSize: `${COMPOSITION_POPUP_FONT_SIZE}fp`,
        fontWeight: 500,
        lineHeight: `${COMPOSITION_POPUP_LINE_HEIGHT}vp`,
        maxLines: 1,
      });
      const contentWidth = this.clampCompositionPopupCoordinate(
        Math.ceil(singleLineWidth),
        1,
        maxContentWidth,
      );
      // Ask the public paragraph typesetter for its actual constrained lines.
      // Its line list, rather than paragraph height, is authoritative here: a
      // partially reported glyph bounds height must never reduce the 33vp box
      // reserved for a newly wrapped Myanmar line.
      const paragraph = new text.ParagraphBuilder({
        textStyle: {
          fontSize: fp2px(COMPOSITION_POPUP_FONT_SIZE),
          fontWeight: text.FontWeight.W500,
        },
        wordBreak: text.WordBreak.BREAK_WORD,
        breakStrategy: text.BreakStrategy.GREEDY,
      }, text.FontCollection.getGlobalInstance());
      paragraph.addText(composition);
      const wrappedParagraph = paragraph.build();
      wrappedParagraph.layoutSync(maxContentWidth);
      const lineCount = Math.max(1, wrappedParagraph.getTextLines().length);
      const contentHeightVp = lineCount * COMPOSITION_POPUP_LINE_HEIGHT;
      const requestedPanelHeightVp = contentHeightVp + COMPOSITION_POPUP_VERTICAL_PADDING * 2 +
        COMPOSITION_POPUP_BORDER_ALLOWANCE;
      const targetSize: CompositionPopupSize = {
        width: this.clampCompositionPopupCoordinate(
          contentWidth + horizontalPadding * 2 + horizontalSafetyAllowance,
          minWidth,
          maxWidth,
        ),
        height: this.clampCompositionPopupCoordinate(
          this.compositionPopupVpToPx(requestedPanelHeightVp),
          minHeight,
          maxHeight,
        ),
      };
      this.compositionPopupLastLayout = {
        measuredWidth: singleLineWidth,
        paragraphHeight: wrappedParagraph.getHeight(),
        lineCount,
        contentHeightVp,
        requestedPanelHeightVp,
        targetSize,
      };
      this.logCompositionPopupLayout(this.compositionPopupLastLayout, maxWidth, lineHeight);
      return targetSize;
    } catch (error) {
      // Measurement is presentation-only. If a device declines it, reserve the
      // complete available panel height rather than guessing a line count and
      // clipping a partially measured Myanmar line.
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `Unable to measure composition popup text; using full visible height: ${JSON.stringify(error)}`);
      const targetSize: CompositionPopupSize = {
        width: maxWidth,
        height: maxHeight,
      };
      this.compositionPopupLastLayout = {
        measuredWidth: maxContentWidth,
        paragraphHeight: maxHeight,
        lineCount: undefined,
        contentHeightVp: undefined,
        requestedPanelHeightVp: undefined,
        targetSize,
      };
      this.logCompositionPopupLayout(this.compositionPopupLastLayout, maxWidth, lineHeight);
      return targetSize;
    }
  }

  private logCompositionPopupLayout(
    layout: CompositionPopupLayout,
    maxWidth: number,
    lineHeight: number,
  ): void {
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `POPUP LAYOUT compositionLength=${this.compositionPopupCodePointCount(this.compositionPopupLatestComposition)} ` +
        `measuredWidth=${Math.ceil(layout.measuredWidth)} paragraphHeight=${Math.ceil(layout.paragraphHeight)} ` +
        `maxWidth=${maxWidth} lineCount=${layout.lineCount === undefined ? '<unavailable>' : layout.lineCount} ` +
        `targetWidth=${layout.targetSize.width} targetHeight=${layout.targetSize.height} ` +
        `fontSize=${COMPOSITION_POPUP_FONT_SIZE}fp lineHeight=${COMPOSITION_POPUP_LINE_HEIGHT}vp ` +
        `lineHeightPx=${Math.ceil(lineHeight)}`);
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `POPUP WRAP TRACE generation=${this.compositionPopupGeneration} ` +
        `lineCount=${layout.lineCount === undefined ? '<unavailable>' : layout.lineCount} ` +
        `lineHeightVp=${COMPOSITION_POPUP_LINE_HEIGHT} ` +
        `contentHeightVp=${layout.contentHeightVp === undefined ? '<unavailable>' : layout.contentHeightVp} ` +
        `requestedPanelHeightVp=${layout.requestedPanelHeightVp === undefined ? '<unavailable>' : layout.requestedPanelHeightVp} ` +
        `requestedPanelHeightPx=${layout.targetSize.height} ` +
        `actualPanelHeightPx=${this.compositionPopupActualHeight === undefined ? '<pending>' : this.compositionPopupActualHeight}`);
  }

  private compositionPopupCodePointCount(composition: string): number {
    let count = 0;
    for (let index = 0; index < composition.length; index++) {
      const point = composition.codePointAt(index);
      if (point === undefined) {
        continue;
      }
      count++;
      if (point > 0xFFFF) {
        index++;
      }
    }
    return count;
  }

  private compositionPopupMaxWidth(): number {
    if (this.compositionPopupWindowRect === undefined) {
      return this.compositionPopupVpToPx(COMPOSITION_POPUP_PREFERRED_MAX_WIDTH);
    }
    return Math.max(1, Math.min(
      this.compositionPopupVpToPx(COMPOSITION_POPUP_PREFERRED_MAX_WIDTH),
      this.compositionPopupWindowRect.width - this.compositionPopupVpToPx(COMPOSITION_POPUP_WINDOW_MARGIN) * 2,
    ));
  }

  private compositionPopupMaxHeight(): number {
    if (this.compositionPopupWindowRect === undefined) {
      return this.compositionPopupVpToPx(COMPOSITION_POPUP_PREPOSITION_MAX_HEIGHT);
    }
    return Math.max(1, this.compositionPopupWindowRect.height -
      this.compositionPopupVpToPx(COMPOSITION_POPUP_WINDOW_MARGIN) * 2);
  }

  private defaultCompositionPopupRect(popupSize: CompositionPopupSize): CompositionPopupRect {
    const windowRect = this.compositionPopupWindowRect;
    const windowMargin = this.compositionPopupVpToPx(COMPOSITION_POPUP_WINDOW_MARGIN);
    if (windowRect === undefined) {
      return {
        left: windowMargin,
        top: windowMargin,
        width: popupSize.width,
        height: popupSize.height,
      };
    }
    return {
      left: this.clampCompositionPopupCoordinate(
        windowRect.left + windowMargin,
        windowRect.left,
        windowRect.left + windowRect.width - popupSize.width,
      ),
      top: this.clampCompositionPopupCoordinate(
        windowRect.top + Math.max(
          windowMargin,
          windowRect.height - popupSize.height - windowMargin,
        ),
        windowRect.top,
        windowRect.top + windowRect.height - popupSize.height,
      ),
      width: popupSize.width,
      height: popupSize.height,
    };
  }

  private clampCompositionPopupRectToWindow(rect: CompositionPopupRect): CompositionPopupRect {
    if (this.compositionPopupWindowRect === undefined) {
      return rect;
    }
    const windowRect = this.compositionPopupWindowRect;
    return {
      left: this.clampCompositionPopupCoordinate(
        rect.left,
        windowRect.left,
        windowRect.left + windowRect.width - rect.width,
      ),
      top: this.clampCompositionPopupCoordinate(
        rect.top,
        windowRect.top,
        windowRect.top + windowRect.height - rect.height,
      ),
      width: rect.width,
      height: rect.height,
    };
  }

  /** Requests a native resize only when the requested bounds actually change. */
  private applyCompositionPopupRect(rect: CompositionPopupRect): void {
    if (this.panel === undefined) {
      return;
    }
    if (this.isSameCompositionPopupRect(this.compositionPopupLastRequestedRect, rect)) {
      return;
    }
    try {
      this.panel.adjustPanelRect(inputMethodEngine.PanelFlag.FLG_FLOATING, {
        landscapeRect: rect,
        portraitRect: rect,
      });
      this.compositionPopupLastRequestedRect = {
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
      };
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `Unable to position floating composition panel: ${JSON.stringify(error)}`);
    }
  }

  private isSameCompositionPopupRect(
    first: CompositionPopupRect | undefined,
    second: CompositionPopupRect,
  ): boolean {
    return first !== undefined &&
      Math.abs(first.left - second.left) <= COMPOSITION_POPUP_RECT_EPSILON &&
      Math.abs(first.top - second.top) <= COMPOSITION_POPUP_RECT_EPSILON &&
      Math.abs(first.width - second.width) <= COMPOSITION_POPUP_RECT_EPSILON &&
      Math.abs(first.height - second.height) <= COMPOSITION_POPUP_RECT_EPSILON;
  }

  private describeCompositionPopupRect(rect: CompositionPopupRect | undefined): string {
    if (rect === undefined) {
      return '<none>';
    }
    return `${rect.left},${rect.top} ${rect.width}x${rect.height}`;
  }

  private clampCompositionPopupCoordinate(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(Math.max(minimum, maximum), value));
  }

  /** Converts ArkUI logical popup dimensions to the physical window-rect unit. */
  private compositionPopupVpToPx(value: number): number {
    return vp2px(value);
  }

  private commitCompositionAndReset(reason: string): void {
    this.commitInternalComposition(reason);
    this.resetForInputSession(reason);
  }

  private cancelCompositionAndReset(reason: string): void {
    this.cancelInternalComposition(reason);
    this.resetForInputSession(reason);
  }

  private commitInternalComposition(reason: string): void {
    if (this.internalComposition.length === 0 || this.inputClient === undefined) {
      return;
    }
    const text = this.internalComposition;
    // Clear first: any synchronous callback is observational and cannot cause
    // this final composition to be committed a second time.
    this.internalComposition = '';
    this.publishCompositionPopup();
    this.directCommitInProgress = true;
    try {
      this.inputClient.insertTextSync(text);
      this.diagnosticTextSentToEditor = `committed: ${this.formatTextWithCodePoints(text)}`;
      this.appendDirectFallbackTrace(
        `INTERNAL COMPOSITION COMMIT: text=${this.formatTextWithCodePoints(text)}; reason=${reason}; count=1`,
      );
    } catch (error) {
      this.appendDirectFallbackTrace(
        `INTERNAL COMPOSITION COMMIT ERROR: reason=${reason}; error=${JSON.stringify(error)}`,
      );
    } finally {
      this.directCommitInProgress = false;
    }
  }

  private cancelInternalComposition(reason: string): void {
    if (this.internalComposition.length > 0) {
      this.appendDirectFallbackTrace(
        `INTERNAL COMPOSITION CANCEL: text=${this.formatTextWithCodePoints(this.internalComposition)}; reason=${reason}`,
      );
    }
    this.internalComposition = '';
    this.directCommitInProgress = false;
    this.publishCompositionPopup();
  }

  private shouldCommitProcessedComposition(keyCode: number, output: KeyMagicProcessResult): boolean {
    if (keyCode === KeyMagicVirtualKey.Space) {
      return output.composingText.endsWith(' ');
    }
    return keyCode === KeyMagicVirtualKey.Return || keyCode === KeyMagicVirtualKey.Tab ||
      keyCode === KeyMagicVirtualKey.Escape;
  }

  private describeEditor(attribute: inputMethodEngine.EditorAttribute): string {
    const bundle = attribute.bundleName === undefined ? '<unknown>' : attribute.bundleName;
    const ability = attribute.abilityName === undefined ? '<unknown>' : attribute.abilityName;
    const windowId = attribute.windowId === undefined ? '<unknown>' : `${attribute.windowId}`;
    const displayId = attribute.displayId === undefined ? '<unknown>' : `${attribute.displayId}`;
    return `bundle=${bundle} ability=${ability} windowId=${windowId} displayId=${displayId} ` +
      `inputPattern=${attribute.inputPattern} enterKeyType=${attribute.enterKeyType}`;
  }

  private errorCode(error: Object): string {
    const serialized = JSON.stringify(error);
    const structuredCode = serialized.match(/"code"\s*:\s*(-?\d+)/);
    if (structuredCode !== null && structuredCode[1] !== undefined) {
      return structuredCode[1];
    }
    const numericCode = error.toString().match(/\b(\d{5,})\b/);
    if (numericCode !== null && numericCode[1] !== undefined) {
      return numericCode[1];
    }
    return 'unavailable';
  }

  private currentTransport(): string {
    return 'INTERNAL_COMPOSITION_POPUP';
  }

  /** Records the exact NAPI result before the internal-composition update. */
  private recordEngineOutput(input: KeyMagicKeyInput, output: KeyMagicProcessResult): void {
    const character = input.character === undefined || input.character.length === 0 ? '<empty>' : input.character;
    const keyLabel = `KEY ${character} (KeyMagic key_code=${input.keyCode})`;
    const action = this.actionName(output.actionType);
    const engineText = this.formatTextWithCodePoints(output.text);
    const engineComposition = this.formatTextWithCodePoints(output.composingText);

    this.diagnosticKey = keyLabel;
    this.diagnosticEngineAction = action;
    this.diagnosticEngineText = engineText;
    this.diagnosticEngineDeleteCount = `${output.deleteCount}`;
    this.diagnosticEngineComposition = engineComposition;

    AppStorage.setOrCreate(DIAGNOSTIC_KEY, keyLabel);
    AppStorage.setOrCreate(DIAGNOSTIC_ENGINE_ACTION, action);
    AppStorage.setOrCreate(DIAGNOSTIC_ENGINE_TEXT, engineText);
    AppStorage.setOrCreate(DIAGNOSTIC_ENGINE_DELETE_COUNT, `${output.deleteCount}`);
    AppStorage.setOrCreate(DIAGNOSTIC_ENGINE_COMPOSITION, engineComposition);
    AppStorage.setOrCreate(DIAGNOSTIC_TRANSPORT, this.currentTransport());
    this.publishTransportDiagnostics();

    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `PHYSICAL DOWN ${keyLabel} | EngineOutput.action=${action} | ` +
      `EngineOutput.text=${engineText} | EngineOutput.delete_count=${output.deleteCount} | ` +
      `EngineOutput.composition=${engineComposition} | processed=${output.isProcessed}`);
  }

  private actionName(action: KeyMagicActionType): string {
    switch (action) {
      case KeyMagicActionType.Insert:
        return 'Insert';
      case KeyMagicActionType.BackspaceDelete:
        return 'BackspaceDelete';
      case KeyMagicActionType.BackspaceDeleteAndInsert:
        return 'BackspaceDeleteAndInsert';
      default:
        return 'None';
    }
  }

  private formatTextWithCodePoints(text: string): string {
    return `${text.length === 0 ? '<empty>' : text} [${this.codePoints(text)}]`;
  }

  private codePoints(text: string): string {
    if (text.length === 0) {
      return '<none>';
    }
    const points: string[] = [];
    for (let index = 0; index < text.length; index++) {
      const point = text.codePointAt(index);
      if (point === undefined) {
        continue;
      }
      points.push(`U+${point.toString(16).toUpperCase().padStart(4, '0')}`);
      if (point > 0xFFFF) {
        index++;
      }
    }
    return points.join(' ');
  }

  private resetInputSessionState(): void {
    this.lastSelectionBegin = undefined;
    this.lastSelectionEnd = undefined;
    this.directFallbackOperationInProgress = undefined;
    this.directSelectionCallbackObserved = false;
    this.directTextCallbackObserved = false;
    this.expectedDirectSelectionChanges = [];
    this.expectedDirectTextChanges = [];
    this.handledPhysicalKeys = [];
    this.directRawTextLeakProbe = undefined;
    this.pendingDirectTransaction = undefined;
    this.queuedPhysicalDowns = [];
    this.directEngineCompositionBeforeKey = undefined;
    this.directEngineSynchronization = 'not run for this direct-fallback key';
    this.directAcknowledgedSuffix = undefined;
    this.internalComposition = '';
    this.keyboardSwitchFeedback = '';
    this.keyboardSwitchFeedbackToken++;
    this.directCommitInProgress = false;
    this.compositionPopupSession++;
    this.compositionPopupCursorX = undefined;
    this.compositionPopupCursorY = undefined;
    this.compositionPopupCursorHeight = undefined;
    this.compositionPopupRect = undefined;
    this.compositionPopupLastRequestedRect = undefined;
    this.compositionPopupActualWidth = undefined;
    this.compositionPopupActualHeight = undefined;
    this.compositionPopupWindowRect = undefined;
    this.compositionPopupWindowPositionRequested = false;
    this.publishCompositionPopup();
  }

  /**
   * The IME extension and the ordinary test page can run in different
   * processes. API-20 Preferences plus multiProcessChange is therefore used
   * for device diagnostics instead of process-local AppStorage alone.
   */
  private initializeTransportDiagnostics(context: InputMethodExtensionContext): void {
    try {
      this.diagnosticsContextIdentity = this.describeDiagnosticsContext(context);
      this.diagnosticsPreferences = preferences.getPreferencesSync(context, {
        name: IME_DIAGNOSTICS_PREFERENCES,
      });
      const persistedCounter = this.diagnosticsPreferences.getSync(DIAGNOSTIC_COUNTER, '0');
      const persistedTimestamp = this.diagnosticsPreferences.getSync(DIAGNOSTIC_TIMESTAMP, 'not yet written');
      this.diagnosticCounter = typeof persistedCounter === 'string' ? persistedCounter : '0';
      this.diagnosticTimestamp = typeof persistedTimestamp === 'string' ? persistedTimestamp : 'not yet written';
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME DIAGNOSTICS OPEN store=${IME_DIAGNOSTICS_PREFERENCES} ${this.diagnosticsContextIdentity}`);
      this.publishTransportDiagnostics('IME diagnostics initialization');
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `Unable to initialize IME transport diagnostics: ${JSON.stringify(error)}`);
    }
  }

  private resetTransportDiagnostics(): void {
    this.diagnosticKey = 'No physical key-down event yet';
    this.diagnosticEngineAction = '—';
    this.diagnosticEngineText = '—';
    this.diagnosticEngineDeleteCount = '—';
    this.diagnosticEngineComposition = '—';
    this.diagnosticPreviewText = '—';
    this.diagnosticPreviewRange = '—';
    this.diagnosticPreviewResult = 'not called';
    this.diagnosticPreviewActive = 'false';
    this.diagnosticTextSentToEditor = '—';
    this.diagnosticSelectionChange = 'No selection change while preview active yet';
    this.diagnosticSetPreviewErrorCode = 'not called';
    this.diagnosticFinishPreviewResult = 'not called';
    this.diagnosticFinishPreviewErrorCode = 'not called';
    this.diagnosticDirectEditResult = 'not used';
    this.diagnosticDirectEditErrorCode = 'not used';
    this.diagnosticDirectTrace = 'No direct-fallback transaction yet';
    this.publishTransportDiagnostics('input-session diagnostic reset');
  }

  /**
   * The counter is intentionally independent of KeyMagic. It proves that a
   * physical DOWN reached the extension and was durably flushed before any
   * engine or editor work can hide a transport failure.
   */
  private recordPhysicalDownDiagnostic(event: InputMethodKeyEvent): void {
    if (this.diagnosticsPreferences === undefined) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME DIAGNOSTICS COUNTER FAILED: no Preferences instance for rawKeyCode=${event.key.code}.`);
      return;
    }

    try {
      const storedCounter = this.diagnosticsPreferences.getSync(DIAGNOSTIC_COUNTER, '0');
      const previousCounter = typeof storedCounter === 'string' ? Number(storedCounter) : 0;
      this.diagnosticCounter = `${Number.isFinite(previousCounter) ? previousCounter + 1 : 1}`;
      this.diagnosticTimestamp = `${Date.now()}`;
      this.diagnosticKey = `raw DOWN keyCode=${event.key.code}`;
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME PHYSICAL DOWN store=${IME_DIAGNOSTICS_PREFERENCES} ${this.diagnosticsContextIdentity} ` +
        `diagnosticCounter=${this.diagnosticCounter} lastDiagnosticTimestamp=${this.diagnosticTimestamp} ` +
        `rawKeyCode=${event.key.code}`);
      this.publishTransportDiagnostics(`physical DOWN rawKeyCode=${event.key.code}`);
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME DIAGNOSTICS COUNTER FAILED store=${IME_DIAGNOSTICS_PREFERENCES} ` +
        `${this.diagnosticsContextIdentity}: ${JSON.stringify(error)}`);
    }
  }

  private describeDiagnosticsContext(context: InputMethodExtensionContext): string {
    return `bundle=${context.applicationInfo.name} module=${KEYMAGIC_MODULE_NAME} ` +
      `process=${context.processName} area=${context.area} preferencesDir=${context.preferencesDir}`;
  }

  private publishTransportDiagnostics(reason: string = 'state update'): void {
    if (this.diagnosticsPreferences === undefined) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME DIAGNOSTICS WRITE SKIPPED store=${IME_DIAGNOSTICS_PREFERENCES} reason=${reason}: no Preferences instance.`);
      return;
    }
    try {
      this.writeTransportDiagnostic(DIAGNOSTIC_KEY, this.diagnosticKey, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_ENGINE_ACTION, this.diagnosticEngineAction, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_ENGINE_TEXT, this.diagnosticEngineText, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_ENGINE_DELETE_COUNT, this.diagnosticEngineDeleteCount, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_ENGINE_COMPOSITION, this.diagnosticEngineComposition, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_PREVIEW_TEXT, this.diagnosticPreviewText, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_PREVIEW_RANGE, this.diagnosticPreviewRange, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_TRANSPORT, this.currentTransport(), reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_EDITOR_PREVIEW_SUPPORT, this.diagnosticEditorPreviewSupport, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_PREVIEW_RESULT, this.diagnosticPreviewResult, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_PREVIEW_ACTIVE, this.diagnosticPreviewActive, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_TEXT_SENT_TO_EDITOR, this.diagnosticTextSentToEditor, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_COUNTER, this.diagnosticCounter, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_TIMESTAMP, this.diagnosticTimestamp, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_SELECTION_CHANGE, this.diagnosticSelectionChange, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_EDITOR_IDENTITY, this.diagnosticEditorIdentity, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_SET_PREVIEW_ERROR_CODE, this.diagnosticSetPreviewErrorCode, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_FINISH_PREVIEW_RESULT, this.diagnosticFinishPreviewResult, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_FINISH_PREVIEW_ERROR_CODE, this.diagnosticFinishPreviewErrorCode, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_DIRECT_EDIT_RESULT, this.diagnosticDirectEditResult, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_DIRECT_EDIT_ERROR_CODE, this.diagnosticDirectEditErrorCode, reason);
      this.writeTransportDiagnostic(DIAGNOSTIC_DIRECT_TRACE, this.diagnosticDirectTrace, reason);
      this.diagnosticsPreferences.flushSync();
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME DIAGNOSTICS FLUSH SUCCESS store=${IME_DIAGNOSTICS_PREFERENCES} ` +
        `${this.diagnosticsContextIdentity} reason=${reason}`);
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `Unable to publish IME transport diagnostics store=${IME_DIAGNOSTICS_PREFERENCES} ` +
        `${this.diagnosticsContextIdentity} reason=${reason}: ${JSON.stringify(error)}`);
    }
  }

  private writeTransportDiagnostic(key: string, value: string, reason: string): void {
    if (this.diagnosticsPreferences === undefined) {
      return;
    }
    try {
      this.diagnosticsPreferences.putSync(key, value);
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME DIAGNOSTICS WRITE store=${IME_DIAGNOSTICS_PREFERENCES} ${this.diagnosticsContextIdentity} ` +
        `reason=${reason} key=${key} value=${value}`);
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `IME DIAGNOSTICS WRITE FAILED store=${IME_DIAGNOSTICS_PREFERENCES} ` +
        `${this.diagnosticsContextIdentity} reason=${reason} key=${key}: ${JSON.stringify(error)}`);
      throw new Error(`Unable to write diagnostic key ${key}: ${JSON.stringify(error)}`);
    }
  }

  private resetForInputSession(reason: string): void {
    this.internalComposition = '';
    this.directCommitInProgress = false;
    this.publishCompositionPopup();
    if (!this.keyboardLoaded || !this.native.isCreated()) {
      return;
    }
    try {
      this.native.resetEngine();
      hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s', `Engine reset for ${reason}.`);
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `Unable to reset KeyMagic IME engine: ${JSON.stringify(error)}`);
    }
  }

  private async showPanel(): Promise<void> {
    if (this.panel === undefined) {
      return;
    }
    try {
      await this.panel.show();
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s', `Unable to show IME panel: ${JSON.stringify(error)}`);
    }
  }

  private async hidePanel(): Promise<void> {
    if (this.panel === undefined) {
      return;
    }
    try {
      await this.panel.hide();
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s', `Unable to hide IME panel: ${JSON.stringify(error)}`);
    }
  }

  private async destroyPanel(
    inputMethodAbility: inputMethodEngine.InputMethodAbility,
    panel: inputMethodEngine.Panel,
  ): Promise<void> {
    try {
      await inputMethodAbility.destroyPanel(panel);
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `Unable to destroy IME panel: ${JSON.stringify(error)}`);
    }
  }
}

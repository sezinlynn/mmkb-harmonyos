import { KeyMagicActionType, KeyMagicKeyInput, KeyMagicNative, KeyMagicProcessResult } from '../common/KeyMagicNative';
import { keyMagicInputFromHarmonyEvent, keyMagicVirtualKeyFromHarmonyKeyCode, KeyMagicVirtualKey } from '../common/KeyMagicKeyMap';
import { ExpectedEngineOutput, _VALIDATION_VECTORS } from '../common/KeyMagicValidationVectors';
import { KeyCode } from '@kit.InputKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';

const STANDARD_BUTTON_ID = 'keymagic-standard-focus-diagnostic';
const PHYSICAL_CAPTURE_ID = 'keymagic-custom-capture-diagnostic';
const PHYSICAL_KEY_LOG_DOMAIN = 0x0000;
const PHYSICAL_KEY_LOG_TAG = 'KeyMagicPhysical';
const IME_DIAGNOSTICS_PREFERENCES = 'keymagic_ime_diagnostics';
const KEYMAGIC_MODULE_NAME = 'keymagic3';
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
const IME_DIAGNOSTIC_LOG_DOMAIN = 0x0000;
const IME_DIAGNOSTIC_LOG_TAG = 'KeyMagicImeDiagUi';

@Entry
@Component
struct Index {
  private native: KeyMagicNative = new KeyMagicNative();

  @State engineCreated: boolean = false;
  @State keyboardLoaded: boolean = false;
  @State status: string = 'Create an engine, then load the bundled .km2 keyboard.';
  @State keyCodeInput: string = `${KeyMagicVirtualKey.KeyA}`;
  @State characterInput: string = 'a';
  @State shift: boolean = false;
  @State ctrl: boolean = false;
  @State alt: boolean = false;
  @State capsLock: boolean = false;
  @State zawCodeCompositionTestText: string = '';
  @State imeDiagnosticConnection: string = 'Connecting to the KeyMagic IME diagnostic channel…';
  @State imeEditorPreviewSupport: string = 'unknown';
  @State imePreviewResult: string = 'not called';
  @State imeTransport: string = 'unknown';
  @State imePreviewActive: string = 'false';
  @State imeEngineAction: string = '—';
  @State imeEngineText: string = '—';
  @State imeEngineDeleteCount: string = '—';
  @State imeEngineComposition: string = '—';
  @State imePreviewText: string = '—';
  @State imeTextSentToEditor: string = '—';
  @State imePreviewRange: string = '—';
  @State imePhysicalDown: string = 'No physical key-down event yet';
  @State imeDiagnosticCounter: string = '0';
  @State imeDiagnosticTimestamp: string = 'not yet written';
  @State imeSelectionChange: string = 'No selection change while preview active yet';
  @State imeEditorIdentity: string = 'unknown (waiting for editorAttributeChanged)';
  @State imeSetPreviewErrorCode: string = 'not called';
  @State imeFinishPreviewResult: string = 'not called';
  @State imeFinishPreviewErrorCode: string = 'not called';
  @State imeDirectEditResult: string = 'not used';
  @State imeDirectEditErrorCode: string = 'not used';
  @State imeDirectTrace: string = 'No direct-fallback transaction yet';
  @State inputKey: string = 'No key processed yet';
  @State harmonyKeyCode: string = 'Not captured';
  @State engineKeyCode: string = 'Not captured';
  @State modifiers: string = 'Not captured';
  @State action: string = 'Not captured';
  @State outputText: string = '';
  @State deleteCount: string = '0';
  @State composingText: string = '';
  @State isProcessed: string = 'false';
  @State validationSummary: string = 'No deterministic validation has run on this device.';
  @State validationTrace: string = '';
  @State standardButtonFocused: boolean = false;
  @State standardPreImeCount: number = 0;
  @State standardKeyEventCount: number = 0;
  @State standardLastCallback: string = 'NONE';
  @State standardLastEvent: string = 'NONE';
  @State standardRawKeyCode: string = 'Not received';
  @State standardKeyText: string = 'Not received';
  @State standardShift: boolean = false;
  @State standardCtrl: boolean = false;
  @State standardAlt: boolean = false;
  @State standardFocusRequest: string = 'Use TAB or the request-focus action to target the standard button.';
  @State physicalCaptureFocused: boolean = false;
  @State physicalPreImeCount: number = 0;
  @State physicalKeyEventCount: number = 0;
  @State physicalLastCallback: string = 'NONE';
  @State physicalLastEvent: string = 'NONE';
  @State physicalRawKeyCode: string = 'Not received';
  @State physicalMappedKeyCode: string = 'Not received';
  @State physicalKeyText: string = 'Not received';
  @State physicalShift: boolean = false;
  @State physicalCtrl: boolean = false;
  @State physicalAlt: boolean = false;
  @State physicalFocusRequest: string = 'Tap the capture surface to request focus.';
  @State deterministicProcessArguments: string = 'Run the deterministic u baseline to display its native-call arguments.';
  @State physicalProcessArguments: string = 'Press a physical key in focused Test B after loading .km2.';
  @State characterPassedToRust: string = '(no native processKey call yet)';
  @State characterBytePassedToRust: string = 'n/a';
  private imeDiagnosticsPreferences: preferences.Preferences | undefined;
  private readonly onImeDiagnosticsChanged = (_key: string): void => {
    // This automatic callback is convenience only. The Refresh button below
    // deliberately drops and reopens the local cache for a durable-read test.
    this.refreshImeTransportDiagnostics(false);
  };

  private createEngine(): void {
    try {
      this.native.createEngine();
      this.engineCreated = true;
      this.keyboardLoaded = false;
      this.status = 'Engine created. Load .km2 next.';
    } catch (error) {
      this.status = `Create engine failed: ${JSON.stringify(error)}`;
    }
  }

  private async loadKeyboard(): Promise<void> {
    try {
      await this.native.loadBundledKeyboard(this.applicationContext(), 'keyboards/.km2');
      this.keyboardLoaded = true;
      this.status = 'Bundled .km2 loaded through Rust C FFI.';
    } catch (error) {
      this.status = `Load keyboard failed: ${JSON.stringify(error)}`;
    }
  }

  private async reloadKeyboard(): Promise<void> {
    try {
      await this.native.loadBundledKeyboard(this.applicationContext(), 'keyboards/.km2');
      this.keyboardLoaded = true;
      this.composingText = '';
      this.status = 'Bundled .km2 reloaded into a fresh Rust engine state.';
    } catch (error) {
      this.status = `Reload keyboard failed: ${JSON.stringify(error)}`;
    }
  }

  private resetEngine(): void {
    try {
      this.native.resetEngine();
      this.composingText = '';
      this.status = 'Engine state reset.';
    } catch (error) {
      this.status = `Reset failed: ${JSON.stringify(error)}`;
    }
  }

  private destroyEngine(): void {
    try {
      this.native.destroyEngine();
      this.engineCreated = false;
      this.keyboardLoaded = false;
      this.composingText = '';
      this.status = 'Engine destroyed. Create a new engine to continue.';
    } catch (error) {
      this.status = `Destroy failed: ${JSON.stringify(error)}`;
    }
  }

  private processDebugInput(): void {
    const keyCode = Number.parseInt(this.keyCodeInput);
    if (Number.isNaN(keyCode) || keyCode < 0) {
      this.status = 'Enter a non-negative KeyMagic virtual-key value.';
      return;
    }

    this.processInput({
      keyCode: keyCode,
      character: this.characterInput,
      shift: this.shift,
      ctrl: this.ctrl,
      alt: this.alt,
      capsLock: this.capsLock,
    }, 'Debug input', undefined);
  }

  private runDeterministicUBaseline(): void {
    try {
      this.native.resetEngine();
      const input: KeyMagicKeyInput = { keyCode: KeyMagicVirtualKey.KeyU, character: 'u' };
      const result = this.callNativeProcessKey(input, 'DETERMINISTIC u baseline');
      this.showResult(input, result, 'DETERMINISTIC u baseline', undefined);
    } catch (error) {
      this.status = `Deterministic u baseline failed: ${JSON.stringify(error)}`;
    }
  }

  private runDeterministicAuBaseline(): void {
    try {
      this.native.resetEngine();
      const aInput: KeyMagicKeyInput = { keyCode: KeyMagicVirtualKey.KeyA, character: 'a' };
      const uInput: KeyMagicKeyInput = { keyCode: KeyMagicVirtualKey.KeyU, character: 'u' };
      this.callNativeProcessKey(aInput, 'DETERMINISTIC a,u baseline: a');
      const result = this.callNativeProcessKey(uInput, 'DETERMINISTIC a,u baseline: u');
      this.showResult(uInput, result, 'DETERMINISTIC a,u baseline: u', undefined);
    } catch (error) {
      this.status = `Deterministic a,u baseline failed: ${JSON.stringify(error)}`;
    }
  }

  /** Test A: standard Button callbacks. Events intentionally never reach KeyMagic. */
  private onStandardPreIme(event: KeyEvent): boolean {
    this.recordStandardEvent(event, 'onKeyPreIme');
    return false;
  }

  private onStandardKeyEvent(event: KeyEvent): boolean {
    this.recordStandardEvent(event, 'onKeyEvent');
    return false;
  }

  /** Test B: custom capture callbacks. Events intentionally never reach KeyMagic. */
  private onCustomCapturePreIme(event: KeyEvent): boolean {
    this.recordPhysicalKeyEvent(event, 'onKeyPreIme');
    return false;
  }

  private onCustomCaptureKeyEvent(event: KeyEvent): boolean {
    this.recordPhysicalKeyEvent(event, 'onKeyEvent');
    this.forwardCustomCaptureEventToKeyMagic(event);
    return false;
  }

  private recordStandardEvent(event: KeyEvent, callback: string): void {
    if (callback === 'onKeyPreIme') {
      this.standardPreImeCount++;
    } else {
      this.standardKeyEventCount++;
    }
    this.standardLastCallback = callback;
    this.standardLastEvent = event.type === KeyType.Down ? 'DOWN' : 'UP';
    this.standardRawKeyCode = `${event.keyCode}`;
    this.standardKeyText = event.keyText.length === 0 ? '(empty)' : event.keyText;
    this.standardShift = this.physicalModifierPressed(event, 'shift');
    this.standardCtrl = this.physicalModifierPressed(event, 'ctrl');
    this.standardAlt = this.physicalModifierPressed(event, 'alt');
    hilog.info(
      PHYSICAL_KEY_LOG_DOMAIN,
      PHYSICAL_KEY_LOG_TAG,
      '%{public}s',
      `test=A callback=${callback} event=${this.standardLastEvent} keyCode=${this.standardRawKeyCode} keyText=${this.standardKeyText} shift=${this.standardShift} ctrl=${this.standardCtrl} alt=${this.standardAlt}`,
    );
  }

  /** Records Test B raw events before any mapping or KeyMagic engine call. */
  private recordPhysicalKeyEvent(event: KeyEvent, callback: string): void {
    if (callback === 'onKeyPreIme') {
      this.physicalPreImeCount++;
    } else {
      this.physicalKeyEventCount++;
    }
    this.physicalLastCallback = callback;
    this.physicalLastEvent = event.type === KeyType.Down ? 'DOWN' : 'UP';
    this.physicalRawKeyCode = `${event.keyCode}`;
    this.physicalKeyText = event.keyText.length === 0 ? '(empty)' : event.keyText;
    this.physicalShift = this.physicalModifierPressed(event, 'shift');
    this.physicalCtrl = this.physicalModifierPressed(event, 'ctrl');
    this.physicalAlt = this.physicalModifierPressed(event, 'alt');
    hilog.info(
      PHYSICAL_KEY_LOG_DOMAIN,
      PHYSICAL_KEY_LOG_TAG,
      '%{public}s',
      `test=B callback=${callback} event=${this.physicalLastEvent} keyCode=${this.physicalRawKeyCode} keyText=${this.physicalKeyText} shift=${this.physicalShift} ctrl=${this.physicalCtrl} alt=${this.physicalAlt}`,
    );
  }

  /**
   * Called only from Test B onKeyEvent, after the raw event has been displayed
   * and logged. Pre-IME callbacks remain raw-only so a key is never processed
   * twice by the engine.
   */
  private forwardCustomCaptureEventToKeyMagic(event: KeyEvent): void {
    const input = keyMagicInputFromHarmonyEvent(event);
    this.physicalMappedKeyCode = `${input.keyCode}`;
    hilog.info(
      PHYSICAL_KEY_LOG_DOMAIN,
      PHYSICAL_KEY_LOG_TAG,
      '%{public}s',
      `test=B mapped keyCode=${event.keyCode} keyMagic=${input.keyCode} keyText=${event.keyText}`,
    );

    if (!this.keyboardLoaded || event.type !== KeyType.Down) {
      return;
    }
    if (input.keyCode === 0 && (input.character === undefined || input.character.length === 0)) {
      this.status = `Unsupported physical key code ${event.keyCode}; raw event recorded and passed through.`;
      return;
    }

    // This smoke test observes the result but does not consume the ArkUI event.
    this.processInput(input, 'Physical key (Test B)', event.keyCode);
  }

  private physicalModifierPressed(event: KeyEvent, modifier: string): boolean {
    return event.getModifierKeyState !== undefined && event.getModifierKeyState([modifier]);
  }

  private requestPhysicalCaptureFocus(): void {
    try {
      const focusController = this.getUIContext().getFocusController();
      focusController.activate(true, false);
      focusController.requestFocus(PHYSICAL_CAPTURE_ID);
      this.physicalFocusRequest = 'Focus requested for the physical-key capture surface; waiting for onFocus.';
      hilog.info(PHYSICAL_KEY_LOG_DOMAIN, PHYSICAL_KEY_LOG_TAG, '%{public}s', 'Focus requested for physical-key capture surface.');
    } catch (error) {
      this.physicalFocusRequest = `Focus request failed: ${JSON.stringify(error)}`;
      hilog.error(PHYSICAL_KEY_LOG_DOMAIN, PHYSICAL_KEY_LOG_TAG, '%{public}s', this.physicalFocusRequest);
    }
  }

  private requestStandardButtonFocus(): void {
    try {
      const focusController = this.getUIContext().getFocusController();
      focusController.activate(true, false);
      focusController.requestFocus(STANDARD_BUTTON_ID);
      this.standardFocusRequest = 'Focus requested for Test A standard button; waiting for onFocus.';
      hilog.info(PHYSICAL_KEY_LOG_DOMAIN, PHYSICAL_KEY_LOG_TAG, '%{public}s', 'Test A standard button focus requested.');
    } catch (error) {
      this.standardFocusRequest = `Focus request failed: ${JSON.stringify(error)}`;
      hilog.error(PHYSICAL_KEY_LOG_DOMAIN, PHYSICAL_KEY_LOG_TAG, '%{public}s', this.standardFocusRequest);
    }
  }

  /** Records the complete ArkTS argument set immediately before the NAPI call. */
  private callNativeProcessKey(input: KeyMagicKeyInput, source: string): KeyMagicProcessResult {
    const character = input.character === undefined ? '' : input.character;
    const characterByte = character.length === 0 ? 0 : character.charCodeAt(0);
    const argumentSummary =
      `key_code = ${input.keyCode}\n` +
      `character = ${character.length === 0 ? '<empty>' : character}\n` +
      `character byte = ${characterByte}\n` +
      `shift = ${input.shift === true}\n` +
      `ctrl = ${input.ctrl === true}\n` +
      `alt = ${input.alt === true}\n` +
      `caps_lock = ${input.capsLock === true}`;

    this.characterPassedToRust = character.length === 0 ? '<empty>' : character;
    this.characterBytePassedToRust = `${characterByte}`;
    if (source.startsWith('Physical key')) {
      this.physicalProcessArguments = argumentSummary;
    } else if (source.startsWith('DETERMINISTIC')) {
      this.deterministicProcessArguments = argumentSummary;
    }
    hilog.info(
      PHYSICAL_KEY_LOG_DOMAIN,
      PHYSICAL_KEY_LOG_TAG,
      '%{public}s',
      `Index before native processKey source=${source} ${argumentSummary.replace(/\n/g, ' ')}`,
    );
    return this.native.processKey(input, source);
  }

  private processInput(input: KeyMagicKeyInput, source: string, harmonyKeyCode: number | undefined): boolean {
    try {
      const result = this.callNativeProcessKey(input, source);
      this.showResult(input, result, source, harmonyKeyCode);
      return result.isProcessed;
    } catch (error) {
      this.status = `Process key failed: ${JSON.stringify(error)}`;
      return false;
    }
  }

  private showResult(
    input: KeyMagicKeyInput,
    result: KeyMagicProcessResult,
    source: string,
    harmonyKeyCode: number | undefined
  ): void {
    this.inputKey = `${source}: ${input.character === undefined || input.character.length === 0 ? '(no character)' : input.character}`;
    this.harmonyKeyCode = harmonyKeyCode === undefined ? 'Debug input' : `${harmonyKeyCode}`;
    this.engineKeyCode = `${input.keyCode}`;
    this.modifiers = `shift=${input.shift === true}, ctrl=${input.ctrl === true}, alt=${input.alt === true}, capsLock=${input.capsLock === true}`;
    this.action = this.actionLabel(result.actionType);
    this.outputText = result.text;
    this.deleteCount = `${result.deleteCount}`;
    this.composingText = result.composingText;
    this.isProcessed = `${result.isProcessed}`;
    this.status = 'Key processed through ArkTS -> NAPI -> C FFI -> Rust.';
  }

  private applicationContext(): Context {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('Unable to obtain the application context for bundled resources.');
    }
    return context;
  }

  private async runAllVectors(): Promise<void> {
    const trace: string[] = [];
    let passed = true;

    try {
      for (const vector of _VALIDATION_VECTORS) {
        this.native.resetEngine();
        trace.push(`\u2713 ${vector.name}`);
        for (const step of vector.steps) {
          const result = this.callNativeProcessKey(step.input, `DETERMINISTIC vector: ${vector.name} / ${step.name}`);
          const mismatch = this.outputMismatch(result, step.expected);
          if (mismatch.length > 0) {
            passed = false;
            trace.push(`  FAIL ${step.name}: ${mismatch}`);
          } else {
            trace.push(`  PASS ${step.name}: ${this.resultSummary(result)}`);
          }
          this.showResult(step.input, result, `Vector: ${vector.name} / ${step.name}`, undefined);
        }
      }
      this.validationSummary = passed ?
        `PASS: ${_VALIDATION_VECTORS.length}  vectors matched the bundled .km2.` :
        'FAIL: inspect the step trace below before proceeding.';
      this.status = passed ?
        'All deterministic  vectors passed through ArkTS -> NAPI -> Rust.' :
        'One or more deterministic  vectors failed.';
    } catch (error) {
      passed = false;
      this.validationSummary = `FAIL: vector runner threw ${JSON.stringify(error)}`;
      this.status = this.validationSummary;
      trace.push(this.validationSummary);
    }

    this.validationTrace = trace.join('\n');
  }

  private async validateReset(): Promise<void> {
    const trace: string[] = [];
    try {
      this.native.resetEngine();
      this.callNativeProcessKey({ keyCode: KeyMagicVirtualKey.KeyA, character: 'a' }, 'DETERMINISTIC reset validation: a');
      this.callNativeProcessKey({ keyCode: KeyMagicVirtualKey.KeyU, character: 'u' }, 'DETERMINISTIC reset validation: u');
      this.native.resetEngine();
      const result = this.callNativeProcessKey({ keyCode: KeyMagicVirtualKey.KeyU, character: 'u' }, 'DETERMINISTIC reset validation: u after reset');
      const expected: ExpectedEngineOutput = {
        actionType: KeyMagicActionType.Insert,
        text: '\u1000',
        deleteCount: 0,
        composingText: '\u1000',
        isProcessed: true,
      };
      const mismatch = this.outputMismatch(result, expected);
      this.showResult({ keyCode: KeyMagicVirtualKey.KeyU, character: 'u' }, result, 'Reset validation: u after reset', undefined);
      this.validationSummary = mismatch.length === 0 ?
        'PASS: reset cleared the a,u composition before u was processed.' :
        `FAIL: reset validation: ${mismatch}`;
      trace.push('Before reset: a, u produced the vowel-e composition.');
      trace.push(`After reset, u: ${this.resultSummary(result)}`);
    } catch (error) {
      this.validationSummary = `FAIL: reset validation threw ${JSON.stringify(error)}`;
      trace.push(this.validationSummary);
    }
    this.validationTrace = trace.join('\n');
  }

  private async validateReload(): Promise<void> {
    const trace: string[] = [];
    try {
      this.native.resetEngine();
      this.callNativeProcessKey({ keyCode: KeyMagicVirtualKey.KeyA, character: 'a' }, 'DETERMINISTIC reload validation: a');
      await this.native.loadBundledKeyboard(this.applicationContext(), 'keyboards/.km2');
      const result = this.callNativeProcessKey({ keyCode: KeyMagicVirtualKey.KeyU, character: 'u' }, 'DETERMINISTIC reload validation: u after reload');
      const expected: ExpectedEngineOutput = {
        actionType: KeyMagicActionType.Insert,
        text: '\u1000',
        deleteCount: 0,
        composingText: '\u1000',
        isProcessed: true,
      };
      const mismatch = this.outputMismatch(result, expected);
      this.showResult({ keyCode: KeyMagicVirtualKey.KeyU, character: 'u' }, result, 'Reload validation: u after reload', undefined);
      this.keyboardLoaded = true;
      this.validationSummary = mismatch.length === 0 ?
        'PASS: reloading .km2 replaced prior engine state.' :
        `FAIL: reload validation: ${mismatch}`;
      trace.push('Before reload: a created the temporary vowel-e composition.');
      trace.push(`After reload, u: ${this.resultSummary(result)}`);
    } catch (error) {
      this.validationSummary = `FAIL: reload validation threw ${JSON.stringify(error)}`;
      trace.push(this.validationSummary);
    }
    this.validationTrace = trace.join('\n');
  }

  private async validateRecreate(): Promise<void> {
    const trace: string[] = [];
    let passed = true;
    try {
      for (let cycle = 1; cycle <= 5; cycle++) {
        this.native.destroyEngine();
        this.native.createEngine();
        await this.native.loadBundledKeyboard(this.applicationContext(), 'keyboards/.km2');
        const result = this.callNativeProcessKey({ keyCode: KeyMagicVirtualKey.KeyU, character: 'u' }, `DETERMINISTIC lifecycle validation cycle ${cycle}: u`);
        const expected: ExpectedEngineOutput = {
          actionType: KeyMagicActionType.Insert,
          text: '\u1000',
          deleteCount: 0,
          composingText: '\u1000',
          isProcessed: true,
        };
        const mismatch = this.outputMismatch(result, expected);
        if (mismatch.length > 0) {
          passed = false;
          trace.push(`Cycle ${cycle}: FAIL ${mismatch}`);
        } else {
          trace.push(`Cycle ${cycle}: PASS create -> load -> u`);
        }
        this.showResult({ keyCode: KeyMagicVirtualKey.KeyU, character: 'u' }, result, `Lifecycle validation cycle ${cycle}`, undefined);
      }
      this.engineCreated = true;
      this.keyboardLoaded = true;
      this.validationSummary = passed ?
        'PASS: five destroy -> create -> load cycles completed without a mismatch.' :
        'FAIL: lifecycle validation has a mismatch; inspect the trace.';
    } catch (error) {
      this.validationSummary = `FAIL: lifecycle validation threw ${JSON.stringify(error)}`;
      trace.push(this.validationSummary);
    }
    this.validationTrace = trace.join('\n');
  }

  private validateHarmonyKeyMap(): void {
    const checks: Array<[string, number, number]> = [
      ['A', KeyCode.KEYCODE_A, KeyMagicVirtualKey.KeyA],
      ['4', KeyCode.KEYCODE_4, KeyMagicVirtualKey.Key4],
      ['Backspace', KeyCode.KEYCODE_DEL, KeyMagicVirtualKey.Back],
      ['Enter', KeyCode.KEYCODE_ENTER, KeyMagicVirtualKey.Return],
      ['Left Shift', KeyCode.KEYCODE_SHIFT_LEFT, KeyMagicVirtualKey.LShift],
      ['Right Shift', KeyCode.KEYCODE_SHIFT_RIGHT, KeyMagicVirtualKey.RShift],
      ['Left Ctrl', KeyCode.KEYCODE_CTRL_LEFT, KeyMagicVirtualKey.LControl],
      ['Left Alt', KeyCode.KEYCODE_ALT_LEFT, KeyMagicVirtualKey.LMenu],
      ['Slash', KeyCode.KEYCODE_SLASH, KeyMagicVirtualKey.Oem2],
    ];
    const trace: string[] = [];
    let passed = true;

    for (const check of checks) {
      const actual = keyMagicVirtualKeyFromHarmonyKeyCode(check[1]);
      const isMatch = actual === check[2];
      passed = passed && isMatch;
      trace.push(`${isMatch ? 'PASS' : 'FAIL'} ${check[0]}: Harmony ${check[1]} -> KeyMagic ${actual}; expected ${check[2]}`);
    }

    this.validationSummary = passed ?
      'PASS: all static HarmonyOS-to-KeyMagic key-code mappings matched.' :
      'FAIL: one or more static HarmonyOS-to-KeyMagic key-code mappings mismatched.';
    this.validationTrace = trace.join('\n');
    this.status = this.validationSummary;
  }

  private outputMismatch(result: KeyMagicProcessResult, expected: ExpectedEngineOutput): string {
    const mismatches: string[] = [];
    if (result.actionType !== expected.actionType) {
      mismatches.push(`action expected ${this.actionLabel(expected.actionType)}, got ${this.actionLabel(result.actionType)}`);
    }
    if (result.text !== expected.text) {
      mismatches.push(`text expected ${this.displayText(expected.text)}, got ${this.displayText(result.text)}`);
    }
    if (result.deleteCount !== expected.deleteCount) {
      mismatches.push(`delete expected ${expected.deleteCount}, got ${result.deleteCount}`);
    }
    if (result.composingText !== expected.composingText) {
      mismatches.push(`composition expected ${this.displayText(expected.composingText)}, got ${this.displayText(result.composingText)}`);
    }
    if (result.isProcessed !== expected.isProcessed) {
      mismatches.push(`processed expected ${expected.isProcessed}, got ${result.isProcessed}`);
    }
    return mismatches.join('; ');
  }

  private resultSummary(result: KeyMagicProcessResult): string {
    return `action=${this.actionLabel(result.actionType)}, text=${this.displayText(result.text)}, delete=${result.deleteCount}, composition=${this.displayText(result.composingText)}, processed=${result.isProcessed}`;
  }

  private displayText(value: string): string {
    return `${value.length === 0 ? '∅' : value} [${this.codePoints(value)}]`;
  }

  private codePoints(value: string): string {
    if (value.length === 0) {
      return 'empty';
    }
    const points: string[] = [];
    for (let index = 0; index < value.length; index++) {
      const point = value.codePointAt(index);
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

  private actionLabel(actionType: KeyMagicActionType): string {
    switch (actionType) {
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

  aboutToAppear(): void {
    this.connectImeTransportDiagnostics();
  }

  aboutToDisappear(): void {
    if (this.imeDiagnosticsPreferences === undefined) {
      return;
    }
    try {
      this.imeDiagnosticsPreferences.off('multiProcessChange', this.onImeDiagnosticsChanged);
    } catch (_error) {
      // The test UI can close after the preferences object has already gone
      // away. There is nothing useful to recover here.
    }
  }

  private connectImeTransportDiagnostics(): void {
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        throw new Error('The test page has no host context for IME diagnostics.');
      }
      hilog.info(IME_DIAGNOSTIC_LOG_DOMAIN, IME_DIAGNOSTIC_LOG_TAG, '%{public}s',
        `MAIN DIAGNOSTICS OPEN store=${IME_DIAGNOSTICS_PREFERENCES} ${this.describeImeDiagnosticsContext()}`);
      this.imeDiagnosticsPreferences = preferences.getPreferencesSync(context, {
        name: IME_DIAGNOSTICS_PREFERENCES,
      });
      this.imeDiagnosticsPreferences.on('multiProcessChange', this.onImeDiagnosticsChanged);
      this.refreshImeTransportDiagnostics(false);
      this.imeDiagnosticConnection = 'Live cross-process diagnostics from InputMethodExtensionAbility.';
    } catch (error) {
      this.imeDiagnosticConnection = `Unable to connect to IME diagnostics: ${JSON.stringify(error)}`;
    }
  }

  private refreshImeTransportDiagnostics(forceStorageReopen: boolean = false): void {
    try {
      if (forceStorageReopen) {
        this.reopenImeDiagnosticsForRefresh();
      }
    } catch (error) {
      this.imeDiagnosticConnection = `Unable to reopen IME diagnostics for refresh: ${JSON.stringify(error)}`;
      return;
    }

    if (this.imeDiagnosticsPreferences === undefined) {
      return;
    }
    try {
      this.imeEngineAction = this.readImeDiagnostic(DIAGNOSTIC_ENGINE_ACTION, '—');
      this.imeEngineText = this.readImeDiagnostic(DIAGNOSTIC_ENGINE_TEXT, '—');
      this.imeEngineDeleteCount = this.readImeDiagnostic(DIAGNOSTIC_ENGINE_DELETE_COUNT, '—');
      this.imeEditorPreviewSupport = this.readImeDiagnostic(DIAGNOSTIC_EDITOR_PREVIEW_SUPPORT, 'unknown');
      this.imePreviewResult = this.readImeDiagnostic(DIAGNOSTIC_PREVIEW_RESULT, 'not called');
      this.imeTransport = this.readImeDiagnostic(DIAGNOSTIC_TRANSPORT, 'unknown');
      this.imePreviewActive = this.readImeDiagnostic(DIAGNOSTIC_PREVIEW_ACTIVE, 'false');
      this.imeEngineComposition = this.readImeDiagnostic(DIAGNOSTIC_ENGINE_COMPOSITION, '—');
      this.imePreviewText = this.readImeDiagnostic(DIAGNOSTIC_PREVIEW_TEXT, '—');
      this.imeTextSentToEditor = this.readImeDiagnostic(DIAGNOSTIC_TEXT_SENT_TO_EDITOR, '—');
      this.imePreviewRange = this.readImeDiagnostic(DIAGNOSTIC_PREVIEW_RANGE, '—');
      this.imePhysicalDown = this.readImeDiagnostic(DIAGNOSTIC_KEY, 'No physical key-down event yet');
      this.imeDiagnosticCounter = this.readImeDiagnostic(DIAGNOSTIC_COUNTER, '0');
      this.imeDiagnosticTimestamp = this.readImeDiagnostic(DIAGNOSTIC_TIMESTAMP, 'not yet written');
      this.imeSelectionChange = this.readImeDiagnostic(
        DIAGNOSTIC_SELECTION_CHANGE,
        'No selection change while preview active yet',
      );
      this.imeEditorIdentity = this.readImeDiagnostic(
        DIAGNOSTIC_EDITOR_IDENTITY,
        'unknown (waiting for editorAttributeChanged)',
      );
      this.imeSetPreviewErrorCode = this.readImeDiagnostic(DIAGNOSTIC_SET_PREVIEW_ERROR_CODE, 'not called');
      this.imeFinishPreviewResult = this.readImeDiagnostic(DIAGNOSTIC_FINISH_PREVIEW_RESULT, 'not called');
      this.imeFinishPreviewErrorCode = this.readImeDiagnostic(DIAGNOSTIC_FINISH_PREVIEW_ERROR_CODE, 'not called');
      this.imeDirectEditResult = this.readImeDiagnostic(DIAGNOSTIC_DIRECT_EDIT_RESULT, 'not used');
      this.imeDirectEditErrorCode = this.readImeDiagnostic(DIAGNOSTIC_DIRECT_EDIT_ERROR_CODE, 'not used');
      this.imeDirectTrace = this.readImeDiagnostic(DIAGNOSTIC_DIRECT_TRACE, 'No direct-fallback transaction yet');
      if (forceStorageReopen) {
        this.logImeDiagnosticsRefreshRead();
        this.imeDiagnosticConnection = 'Refreshed from a newly opened Preferences instance.';
      }
    } catch (error) {
      this.imeDiagnosticConnection = `Unable to refresh IME diagnostics: ${JSON.stringify(error)}`;
    }
  }

  /**
   * The manual Refresh is intentionally stronger than the listener path: it
   * releases the page's cached Preferences object, removes it from this
   * process's cache, and then opens the named store again before reading.
   */
  private reopenImeDiagnosticsForRefresh(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('The test page has no host context for IME diagnostics.');
    }
    if (this.imeDiagnosticsPreferences !== undefined) {
      try {
        this.imeDiagnosticsPreferences.off('multiProcessChange', this.onImeDiagnosticsChanged);
      } catch (error) {
        hilog.error(IME_DIAGNOSTIC_LOG_DOMAIN, IME_DIAGNOSTIC_LOG_TAG, '%{public}s',
          `MAIN REFRESH listener removal failed: ${JSON.stringify(error)}`);
      }
      this.imeDiagnosticsPreferences = undefined;
    }
    hilog.info(IME_DIAGNOSTIC_LOG_DOMAIN, IME_DIAGNOSTIC_LOG_TAG, '%{public}s',
      `MAIN REFRESH REMOVE CACHE store=${IME_DIAGNOSTICS_PREFERENCES} ${this.describeImeDiagnosticsContext()}`);
    try {
      preferences.removePreferencesFromCacheSync(context, IME_DIAGNOSTICS_PREFERENCES);
      this.imeDiagnosticsPreferences = preferences.getPreferencesSync(context, {
        name: IME_DIAGNOSTICS_PREFERENCES,
      });
      this.imeDiagnosticsPreferences.on('multiProcessChange', this.onImeDiagnosticsChanged);
    } catch (error) {
      this.imeDiagnosticsPreferences = undefined;
      throw new Error(`Unable to reopen ${IME_DIAGNOSTICS_PREFERENCES}: ${JSON.stringify(error)}`);
    }
    hilog.info(IME_DIAGNOSTIC_LOG_DOMAIN, IME_DIAGNOSTIC_LOG_TAG, '%{public}s',
      `MAIN REFRESH OPEN store=${IME_DIAGNOSTICS_PREFERENCES} ${this.describeImeDiagnosticsContext()}`);
  }

  private describeImeDiagnosticsContext(): string {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return 'context=<unavailable>';
    }
    return `bundle=${context.applicationInfo.name} module=${KEYMAGIC_MODULE_NAME} ` +
      `process=${context.processName} area=${context.area} preferencesDir=${context.preferencesDir}`;
  }

  private logImeDiagnosticsRefreshRead(): void {
    const values: Array<[string, string]> = [
      [DIAGNOSTIC_KEY, this.imePhysicalDown],
      [DIAGNOSTIC_ENGINE_ACTION, this.imeEngineAction],
      [DIAGNOSTIC_ENGINE_TEXT, this.imeEngineText],
      [DIAGNOSTIC_ENGINE_DELETE_COUNT, this.imeEngineDeleteCount],
      [DIAGNOSTIC_ENGINE_COMPOSITION, this.imeEngineComposition],
      [DIAGNOSTIC_PREVIEW_TEXT, this.imePreviewText],
      [DIAGNOSTIC_EDITOR_PREVIEW_SUPPORT, this.imeEditorPreviewSupport],
      [DIAGNOSTIC_PREVIEW_RESULT, this.imePreviewResult],
      [DIAGNOSTIC_TRANSPORT, this.imeTransport],
      [DIAGNOSTIC_PREVIEW_ACTIVE, this.imePreviewActive],
      [DIAGNOSTIC_TEXT_SENT_TO_EDITOR, this.imeTextSentToEditor],
      [DIAGNOSTIC_PREVIEW_RANGE, this.imePreviewRange],
      [DIAGNOSTIC_COUNTER, this.imeDiagnosticCounter],
      [DIAGNOSTIC_TIMESTAMP, this.imeDiagnosticTimestamp],
      [DIAGNOSTIC_SELECTION_CHANGE, this.imeSelectionChange],
      [DIAGNOSTIC_EDITOR_IDENTITY, this.imeEditorIdentity],
      [DIAGNOSTIC_SET_PREVIEW_ERROR_CODE, this.imeSetPreviewErrorCode],
      [DIAGNOSTIC_FINISH_PREVIEW_RESULT, this.imeFinishPreviewResult],
      [DIAGNOSTIC_FINISH_PREVIEW_ERROR_CODE, this.imeFinishPreviewErrorCode],
      [DIAGNOSTIC_DIRECT_EDIT_RESULT, this.imeDirectEditResult],
      [DIAGNOSTIC_DIRECT_EDIT_ERROR_CODE, this.imeDirectEditErrorCode],
      [DIAGNOSTIC_DIRECT_TRACE, this.imeDirectTrace],
    ];
    hilog.info(IME_DIAGNOSTIC_LOG_DOMAIN, IME_DIAGNOSTIC_LOG_TAG, '%{public}s',
      `MAIN REFRESH READ store=${IME_DIAGNOSTICS_PREFERENCES} ${this.describeImeDiagnosticsContext()}`);
    for (const entry of values) {
      hilog.info(IME_DIAGNOSTIC_LOG_DOMAIN, IME_DIAGNOSTIC_LOG_TAG, '%{public}s',
        `MAIN REFRESH VALUE store=${IME_DIAGNOSTICS_PREFERENCES} key=${entry[0]} value=${entry[1]}`);
    }
  }

  private readImeDiagnostic(key: string, fallback: string): string {
    if (this.imeDiagnosticsPreferences === undefined) {
      return fallback;
    }
    try {
      const value = this.imeDiagnosticsPreferences.getSync(key, fallback);
      return typeof value === 'string' ? value : fallback;
    } catch (_error) {
      return fallback;
    }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('System IME composition test (ZawCode)')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
        Text('Enable KeyMagic ZawCode as the system IME, focus this ordinary native TextArea, then type a,u. The active preview should update in place to ကေ; press Right Arrow to finalize it.')
          .fontSize(14)
        TextArea({ text: this.zawCodeCompositionTestText, placeholder: 'Native HarmonyOS preview-text test field' })
          .height(120)
          .onChange((value: string) => {
            this.zawCodeCompositionTestText = value;
          })
        Text('IME transport state — live diagnostic')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
        Text(this.imeDiagnosticConnection)
          .fontSize(12)
          .fontColor('#666666')
        Text(`Physical DOWN: ${this.imePhysicalDown}`)
          .fontSize(12)
        Text(`Cross-process diagnostic counter: ${this.imeDiagnosticCounter}`)
          .fontSize(12)
        Text(`Last diagnostic timestamp: ${this.imeDiagnosticTimestamp}`)
          .fontSize(12)
        Text(`Editor identity: ${this.imeEditorIdentity}`)
          .fontSize(12)
        Text(`Editor preview support: ${this.imeEditorPreviewSupport}`)
          .fontSize(12)
        Text(`setPreviewTextSync result/error: ${this.imePreviewResult}`)
          .fontSize(12)
        Text(`setPreviewTextSync error code: ${this.imeSetPreviewErrorCode}`)
          .fontSize(12)
        Text(`Transport: ${this.imeTransport}`)
          .fontSize(12)
        Text(`Preview active: ${this.imePreviewActive}`)
          .fontSize(12)
        Text(`Engine action: ${this.imeEngineAction}; delete count: ${this.imeEngineDeleteCount}`)
          .fontSize(12)
        Text(`Engine text: ${this.imeEngineText}`)
          .fontSize(12)
        Text(`Engine composition: ${this.imeEngineComposition}`)
          .fontSize(12)
        Text(`Text sent to preview: ${this.imePreviewText}`)
          .fontSize(12)
        Text(`Text actually sent to editor: ${this.imeTextSentToEditor}`)
          .fontSize(12)
        Text(`Editor preview range: ${this.imePreviewRange}`)
          .fontSize(12)
        Text(`finishTextPreviewSync result/error: ${this.imeFinishPreviewResult}`)
          .fontSize(12)
        Text(`finishTextPreviewSync error code: ${this.imeFinishPreviewErrorCode}`)
          .fontSize(12)
        Text(`Direct-fallback editor operation: ${this.imeDirectEditResult}`)
          .fontSize(12)
        Text(`Direct-fallback error code: ${this.imeDirectEditErrorCode}`)
          .fontSize(12)
        Text('Direct-fallback transaction trace:')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
        Text(this.imeDirectTrace)
          .fontSize(12)
        Text(this.imeSelectionChange)
          .fontSize(12)
        Button('Refresh IME transport state')
          .onClick(() => this.refreshImeTransportDiagnostics(true))

        Divider()
        Text('mmKB HarmonyOS engine smoke test')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
        Text('This page is not a system IME. It only proves the existing Rust engine through NAPI.')
          .fontSize(14)

        Button('Create engine')
          .enabled(!this.engineCreated)
          .onClick(() => this.createEngine())
        Button('Load bundled .km2')
          .enabled(this.engineCreated && !this.keyboardLoaded)
          .onClick(() => {
            this.loadKeyboard();
          })
        Button('Reload bundled .km2')
          .enabled(this.engineCreated && this.keyboardLoaded)
          .onClick(() => {
            this.reloadKeyboard();
          })
        Button('Reset engine')
          .enabled(this.keyboardLoaded)
          .onClick(() => this.resetEngine())
        Button('Destroy engine')
          .enabled(this.engineCreated)
          .onClick(() => this.destroyEngine())

        Divider()
        Text('Manual debug event')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
        TextInput({ text: this.keyCodeInput, placeholder: 'KeyMagic key code' })
          .onChange((value: string) => {
            this.keyCodeInput = value;
          })
        TextInput({ text: this.characterInput, placeholder: 'ASCII character, or empty' })
          .onChange((value: string) => {
            this.characterInput = value;
          })
        Row({ space: 8 }) {
          Button(`Shift: ${this.shift ? 'on' : 'off'}`).onClick(() => this.shift = !this.shift)
          Button(`Ctrl: ${this.ctrl ? 'on' : 'off'}`).onClick(() => this.ctrl = !this.ctrl)
        }
        Row({ space: 8 }) {
          Button(`Alt: ${this.alt ? 'on' : 'off'}`).onClick(() => this.alt = !this.alt)
          Button(`Caps: ${this.capsLock ? 'on' : 'off'}`).onClick(() => this.capsLock = !this.capsLock)
        }
        Button('Process debug event')
          .enabled(this.keyboardLoaded)
          .onClick(() => this.processDebugInput())

        Divider()
        Text('Deterministic  validation')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
        Text('Expected values are traced from the bundled .km2. Each test resets the engine before its sequence.')
          .fontSize(14)
        Button('Run deterministic u baseline (46, u / 117)')
          .enabled(this.keyboardLoaded)
          .onClick(() => this.runDeterministicUBaseline())
        Button('Run deterministic a,u baseline')
          .enabled(this.keyboardLoaded)
          .onClick(() => this.runDeterministicAuBaseline())
        Button('Run all  rule vectors')
          .enabled(this.keyboardLoaded)
          .onClick(() => {
            this.runAllVectors();
          })
        Button('Verify reset clears a,u state')
          .enabled(this.keyboardLoaded)
          .onClick(() => {
            this.validateReset();
          })
        Button('Verify reload replaces state')
          .enabled(this.keyboardLoaded)
          .onClick(() => {
            this.validateReload();
          })
        Button('Stress destroy/create/reload (5 cycles)')
          .enabled(this.engineCreated)
          .onClick(() => {
            this.validateRecreate();
          })
        Button('Verify static Harmony key-code mapping')
          .onClick(() => this.validateHarmonyKeyMap())
        Text(`Validation: ${this.validationSummary}`)
        Text(this.validationTrace.length === 0 ? 'Step trace appears here.' : this.validationTrace)
          .fontSize(12)

        Divider()
        Text('Physical keyboard diagnostic — KeyMagic is disconnected')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
        Text('Both tests return false to ArkUI. Test A is raw-only; Test B records raw callbacks first, then forwards only onKeyEvent DOWN events to KeyMagic after a keyboard is loaded.')
          .fontSize(14)

        Text('TEST A — standard ArkUI Button')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
        Button('Request focus for Test A standard button')
          .onClick(() => this.requestStandardButtonFocus())
        Button('TEST A TARGET: standard focusable Button — press TAB or click here')
          .id(STANDARD_BUTTON_ID)
          .focusable(true)
          .focusOnTouch(true)
          .defaultFocus(true)
          .onClick(() => this.requestStandardButtonFocus())
          .onFocus(() => {
            this.standardButtonFocused = true;
            this.standardFocusRequest = 'FOCUSED: Test A standard Button received ArkUI focus.';
            hilog.info(PHYSICAL_KEY_LOG_DOMAIN, PHYSICAL_KEY_LOG_TAG, '%{public}s', 'Test A standard button focused.');
          })
          .onBlur(() => {
            this.standardButtonFocused = false;
            this.standardFocusRequest = 'NOT FOCUSED: use TAB or Request focus for Test A standard button.';
            hilog.info(PHYSICAL_KEY_LOG_DOMAIN, PHYSICAL_KEY_LOG_TAG, '%{public}s', 'Test A standard button blurred.');
          })
          .onKeyPreIme((event: KeyEvent): boolean => this.onStandardPreIme(event))
          .onKeyEvent((event: KeyEvent): boolean => this.onStandardKeyEvent(event))
        Text(`Button focused: ${this.standardButtonFocused ? 'YES' : 'NO'}`)
        Text(`onKeyPreIme event count: ${this.standardPreImeCount}`)
        Text(`onKeyEvent event count: ${this.standardKeyEventCount}`)
        Text(`Last callback: ${this.standardLastCallback}`)
        Text(`Last event: ${this.standardLastEvent}`)
        Text(`Last raw keyCode: ${this.standardRawKeyCode}`)
        Text(`Key text: ${this.standardKeyText}`)
        Text(`Shift: ${this.standardShift}; Ctrl: ${this.standardCtrl}; Alt: ${this.standardAlt}`)
        Text(this.standardFocusRequest)
          .fontSize(12)

        Divider()
        Text('TEST B — original physical capture surface (compare only after Test A)')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
        Button(`TEST B TARGET: ${this.physicalCaptureFocused ? 'FOCUSED' : 'NOT FOCUSED'} — click or TAB here`)
          .id(PHYSICAL_CAPTURE_ID)
          .focusable(true)
          .focusOnTouch(true)
          .width('100%')
          .backgroundColor(this.physicalCaptureFocused ? Color.Blue : Color.White)
          .border({ width: this.physicalCaptureFocused ? 4 : 2, color: this.physicalCaptureFocused ? Color.Blue : Color.Gray })
          .onClick(() => this.requestPhysicalCaptureFocus())
          .onFocus(() => {
            this.physicalCaptureFocused = true;
            this.physicalFocusRequest = 'FOCUSED: Test B physical capture Button received ArkUI focus.';
            hilog.info(PHYSICAL_KEY_LOG_DOMAIN, PHYSICAL_KEY_LOG_TAG, '%{public}s', 'Test B physical capture Button focused.');
          })
          .onBlur(() => {
            this.physicalCaptureFocused = false;
            this.physicalFocusRequest = 'NOT FOCUSED: click Test B target or use TAB to focus it again.';
            hilog.info(PHYSICAL_KEY_LOG_DOMAIN, PHYSICAL_KEY_LOG_TAG, '%{public}s', 'Test B physical capture Button blurred.');
          })
          .onKeyPreIme((event: KeyEvent): boolean => this.onCustomCapturePreIme(event))
          .onKeyEvent((event: KeyEvent): boolean => this.onCustomCaptureKeyEvent(event))
        Text(`onKeyPreIme event count: ${this.physicalPreImeCount}`)
        Text(`onKeyEvent event count: ${this.physicalKeyEventCount}`)
        Text(`Last callback: ${this.physicalLastCallback}`)
        Text(`Last event: ${this.physicalLastEvent}`)
        Text(`Raw Harmony keyCode: ${this.physicalRawKeyCode}`)
        Text(`Mapped KeyMagic key code: ${this.physicalMappedKeyCode}`)
        Text(`Key text: ${this.physicalKeyText}`)
        Text(`Shift: ${this.physicalShift}; Ctrl: ${this.physicalCtrl}; Alt: ${this.physicalAlt}`)
        Text(this.physicalFocusRequest)
          .fontSize(12)
        Text('ArkTS arguments immediately before native processKey')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
        Text(`DETERMINISTIC u:\n${this.deterministicProcessArguments}`)
          .fontSize(12)
        Text(`PHYSICAL u:\n${this.physicalProcessArguments}`)
          .fontSize(12)
        Text(`Character passed to Rust: ${this.characterPassedToRust}`)
        Text(`Character byte passed to Rust: ${this.characterBytePassedToRust}`)
        Text('Test B now uses the same standard Button focus target as Test A. Raw data is recorded first; only onKeyEvent DOWN events are then forwarded to KeyMagic without consuming the ArkUI event.')
          .fontSize(14)

        Divider()
        Text(`Status: ${this.status}`)
        Text(`Input key: ${this.inputKey}`)
        Text(`Harmony key code: ${this.harmonyKeyCode}`)
        Text(`KeyMagic key code: ${this.engineKeyCode}`)
        Text(`Modifiers: ${this.modifiers}`)
        Text(`Engine action: ${this.action}`)
        Text(`Text output: ${this.displayText(this.outputText)}`)
        Text(`Delete count: ${this.deleteCount}`)
        Text(`Composition: ${this.displayText(this.composingText)}`)
        Text(`Processed: ${this.isProcessed}`)
      }
      .width('100%')
      .padding(20)
    }
    .height('100%')
  }
}

import { hilog } from '@kit.PerformanceAnalysisKit';

import {
  KEYBOARD_HEIGHT_FACTOR_DEFAULT,
  KEYBOARD_HEIGHT_FACTOR_MAX,
  KEYBOARD_HEIGHT_FACTOR_MIN,
  KeyboardHeightSettings,
} from '../settings/KeyboardHeightSettings';

const HEIGHT_ADJUSTER_LOG_DOMAIN = 0x0000;
const HEIGHT_ADJUSTER_LOG_TAG = 'KeyMagicKeyboard';
const HEIGHT_SAMPLE_INPUT_ID = 'myankey-height-adjustment-sample-input';

/**
 * A real editor used solely to put the selected InputMethodExtension on screen.
 * There is intentionally no keyboard preview: dragging the slider resizes the
 * actual SOFT_KEYBOARD panel in the separate IME process.
 */
@Entry
@Component
struct KeyboardHeightAdjuster {
  @State sampleText: string = '';
  @State sampleInputFocused: boolean = false;
  @State heightFactor: number = KEYBOARD_HEIGHT_FACTOR_DEFAULT;
  @State status: string = 'Drag the slider while looking at the real keyboard.';

  aboutToAppear(): void {
    this.loadHeightFactor();
    this.focusSampleInputAfterLayout();
  }

  onPageShow(): void {
    this.focusSampleInputAfterLayout();
  }

  private hostContext(): Context {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('Keyboard height adjustment has no host context.');
    }
    return context;
  }

  private loadHeightFactor(): void {
    try {
      this.heightFactor = KeyboardHeightSettings.read(this.hostContext());
    } catch (error) {
      this.heightFactor = KEYBOARD_HEIGHT_FACTOR_DEFAULT;
      this.status = 'Unable to read the saved height. Showing the default.';
      hilog.error(HEIGHT_ADJUSTER_LOG_DOMAIN, HEIGHT_ADJUSTER_LOG_TAG, '%{public}s',
        `KEYBOARD HEIGHT read failed error=${JSON.stringify(error)}`);
    }
  }

  /** Writes every slider change so the IME's multi-process observer resizes live. */
  private persistHeightFactor(value: number): void {
    const normalized = KeyboardHeightSettings.normalize(value);
    hilog.info(HEIGHT_ADJUSTER_LOG_DOMAIN, HEIGHT_ADJUSTER_LOG_TAG, '%{public}s',
      `HEIGHT slider changed factor=${normalized}`);
    this.heightFactor = normalized;
    try {
      const context = this.hostContext();
      // A direct diagnostic must never silently remain in effect when the
      // user returns to normal slider adjustment.
      KeyboardHeightSettings.applyTestOffset(context, 0);
      const persisted = KeyboardHeightSettings.apply(context, normalized);
      this.status = 'Keyboard height updated live.';
      hilog.info(HEIGHT_ADJUSTER_LOG_DOMAIN, HEIGHT_ADJUSTER_LOG_TAG, '%{public}s',
        `HEIGHT preference persisted factor=${persisted}`);
      hilog.info(HEIGHT_ADJUSTER_LOG_DOMAIN, HEIGHT_ADJUSTER_LOG_TAG, '%{public}s',
        `HEIGHT flush complete factor=${persisted}`);
    } catch (error) {
      this.status = 'Unable to update keyboard height.';
      hilog.error(HEIGHT_ADJUSTER_LOG_DOMAIN, HEIGHT_ADJUSTER_LOG_TAG, '%{public}s',
        `KEYBOARD HEIGHT slider persist failed factor=${normalized} error=${JSON.stringify(error)}`);
    }
  }

  private resetHeight(): void {
    try {
      const context = this.hostContext();
      KeyboardHeightSettings.applyTestOffset(context, 0);
      this.heightFactor = KeyboardHeightSettings.reset(context);
      this.status = 'Keyboard height reset live.';
      hilog.info(HEIGHT_ADJUSTER_LOG_DOMAIN, HEIGHT_ADJUSTER_LOG_TAG, '%{public}s',
        `HEIGHT preference persisted factor=${this.heightFactor}`);
      hilog.info(HEIGHT_ADJUSTER_LOG_DOMAIN, HEIGHT_ADJUSTER_LOG_TAG, '%{public}s',
        `HEIGHT flush complete factor=${this.heightFactor}`);
      this.focusSampleInputAfterLayout();
    } catch (error) {
      this.status = 'Unable to reset keyboard height.';
      hilog.error(HEIGHT_ADJUSTER_LOG_DOMAIN, HEIGHT_ADJUSTER_LOG_TAG, '%{public}s',
        `KEYBOARD HEIGHT reset failed error=${JSON.stringify(error)}`);
    }
  }

  /** Explicit ±150px probe for the already-visible SOFT_KEYBOARD panel. */
  private runPanelResizeDiagnostic(offsetPixels: number): void {
    try {
      const persisted = KeyboardHeightSettings.applyTestOffset(this.hostContext(), offsetPixels);
      this.status = persisted === 0 ? 'Direct panel resize test cleared.' :
        `Direct ${persisted > 0 ? '+' : ''}${persisted}px panel resize requested.`;
      hilog.info(HEIGHT_ADJUSTER_LOG_DOMAIN, HEIGHT_ADJUSTER_LOG_TAG, '%{public}s',
        `HEIGHT direct panel test requested offsetPixels=${persisted}`);
    } catch (error) {
      this.status = 'Unable to run the direct panel resize test.';
      hilog.error(HEIGHT_ADJUSTER_LOG_DOMAIN, HEIGHT_ADJUSTER_LOG_TAG, '%{public}s',
        `HEIGHT direct panel test failed offsetPixels=${offsetPixels} error=${JSON.stringify(error)}`);
    }
  }

  /** Focus occurs after the TextArea enters the tree, which opens the real selected IME. */
  private focusSampleInputAfterLayout(): void {
    setTimeout((): void => {
      const focused = focusControl.requestFocus(HEIGHT_SAMPLE_INPUT_ID);
      hilog.info(HEIGHT_ADJUSTER_LOG_DOMAIN, HEIGHT_ADJUSTER_LOG_TAG, '%{public}s',
        `KEYBOARD HEIGHT sample focus requested result=${focused}`);
    }, 180);
  }

  build() {
    Column({ space: 18 }) {
      Row() {
        Text('Keyboard Height')
          .fontSize(25)
          .fontWeight(FontWeight.Bold)
          .fontColor('#18212D')
          .layoutWeight(1)
        Button('Done')
          .height(40)
          .fontColor('#FFFFFF')
          .backgroundColor('#246BCE')
          .borderRadius(10)
          .onClick(() => this.getUIContext().getRouter().back())
      }
      .width('100%')

      Text('Adjust the slider while the real mmKB keyboard remains visible.')
        .width('100%')
        .fontSize(15)
        .fontColor('#526174')
        .lineHeight(22)

      // Deterministic proof controls. They are intentionally above the focus
      // anchor and keyboard, so +150px/-150px can be observed immediately.
      Row({ space: 10 }) {
        Button('Shorter −150 px')
          .layoutWeight(1)
          .height(38)
          // Keep the tiny sample editor focused. If a diagnostic control
          // steals focus, HarmonyOS ends the IME session before its separate
          // process can receive the live geometry update.
          .focusable(false)
          .focusOnTouch(false)
          .fontColor('#18212D')
          .backgroundColor('#E9EEF5')
          .borderRadius(10)
          .onClick(() => this.runPanelResizeDiagnostic(-150))
        Button('Taller +150 px')
          .layoutWeight(1)
          .height(38)
          .focusable(false)
          .focusOnTouch(false)
          .fontColor('#FFFFFF')
          .backgroundColor('#246BCE')
          .borderRadius(10)
          .onClick(() => this.runPanelResizeDiagnostic(150))
      }
      .width('100%')

      // This minimal focus anchor opens the real selected IME without ArkUI
      // panning the adjustment controls upward to reveal a large sample box.
      // It is an editor, not a keyboard preview or a second keyboard surface.
      TextArea({ text: this.sampleText, placeholder: '' })
        .id(HEIGHT_SAMPLE_INPUT_ID)
        .width(2)
        .height(2)
        .opacity(0.01)
        .fontSize(1)
        .enableKeyboardOnFocus(true)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .border({ width: 0 })
        .onFocus(() => this.sampleInputFocused = true)
        .onBlur(() => this.sampleInputFocused = false)
        .onChange((value: string) => this.sampleText = value)

      // These controls deliberately precede the focused sample editor. The
      // height page must remain operable above the *real* keyboard, not only
      // after it has been hidden.
      Column({ space: 12 }) {
        Text('Keyboard Height')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#18212D')
        Slider({
          value: this.heightFactor,
          min: KEYBOARD_HEIGHT_FACTOR_MIN,
          max: KEYBOARD_HEIGHT_FACTOR_MAX,
          step: 0.01,
          style: SliderStyle.OutSet,
        })
          .width('100%')
          // Dragging changes the existing IME panel; it must not replace the
          // focused sample editor with the Slider as the focus target.
          .focusable(false)
          .focusOnTouch(false)
          .onChange((value: number, _mode: SliderChangeMode) => this.persistHeightFactor(value))
        Row() {
          Text('Low')
            .fontSize(14)
            .fontColor('#526174')
            .layoutWeight(1)
          Text('High')
            .fontSize(14)
            .fontColor('#526174')
        }
        .width('100%')
        Button('Reset')
          .width('100%')
          .height(42)
          .fontColor('#18212D')
          .backgroundColor('#E9EEF5')
          .borderRadius(10)
          .onClick(() => this.resetHeight())
      }
      .width('100%')
      .padding(18)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#D5DCE6' })
      .borderRadius(16)
      .alignItems(HorizontalAlign.Start)

      Text(this.status)
        .width('100%')
        .fontSize(13)
        .fontColor('#526174')
        .lineHeight(20)

    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 28, bottom: 28 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F5F7FA')
  }
}

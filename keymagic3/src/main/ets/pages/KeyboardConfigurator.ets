import { hilog } from '@kit.PerformanceAnalysisKit';
import settings from '@ohos.settings';

import { KeyboardInfo } from '../keyboard/KeyboardInfo';
import { KeyboardManager } from '../keyboard/KeyboardManager';
import { KeyboardSelection, KeyboardSelectionService } from '../keyboard/KeyboardSelectionService';
import { MyanKeyAppearance, MyanKeyAppearanceSettings } from '../settings/MyanKeyAppearanceSettings';
import {
  KEYBOARD_HEIGHT_FACTOR_DEFAULT,
  KEYBOARD_HEIGHT_FACTOR_MAX,
  KEYBOARD_HEIGHT_FACTOR_MIN,
  KeyboardHeightSettings,
  KeyboardTheme,
} from '../settings/KeyboardHeightSettings';

const CONFIGURATOR_LOG_DOMAIN = 0x0000;
const CONFIGURATOR_LOG_TAG = 'KeyMagicKeyboard';

/** Mobile-first launcher/settings surface. It has no dependency on the IME panel. */
@Entry
@Component
struct KeyboardConfigurator {
  @State keyboards: KeyboardInfo[] = [];
  @State activeKeyboardId: string = '';
  @State status: string = 'Loading bundled keyboards…';
  @State testInputText: string = '';
  @State testInputFocused: boolean = false;
  @State appearance: MyanKeyAppearance = 'light';
  @State hapticEnabled: boolean = false;
  @State keyPreviewEnabled: boolean = true;
  @State keyboardTheme: KeyboardTheme = 'system';
  @State keyboardHeightFactor: number = KEYBOARD_HEIGHT_FACTOR_DEFAULT;
  @State showEnableGuide: boolean = false;
  @State showLayoutChoices: boolean = false;
  @State showSetupSteps: boolean = true;

  private readonly keyboardManager: KeyboardManager = new KeyboardManager();
  private readonly keyboardSelectionService: KeyboardSelectionService = new KeyboardSelectionService();

  aboutToAppear(): void {
    this.loadAppearance();
    this.loadKeyboardInteractionSettings();
    void this.refreshKeyboardSelection();
  }

  onPageShow(): void {
    this.loadKeyboardInteractionSettings();
    void this.refreshKeyboardSelection();
  }

  private displayKeyboardSelection(selection: KeyboardSelection): KeyboardInfo {
    const keyboard = this.keyboardManager.getKeyboardById(selection.activeKeyboardId);
    this.activeKeyboardId = selection.activeKeyboardId;
    this.keyboards = this.keyboardManager.getKeyboards(selection.activeKeyboardId);
    return keyboard;
  }

  private async refreshKeyboardSelection(): Promise<void> {
    try {
      const selection = await this.keyboardSelectionService.getSelection();
      const keyboard = this.displayKeyboardSelection(selection);
      this.status = `${keyboard.name} is the active mmKB layout.`;
    } catch (error) {
      this.status = 'Could not refresh the Burmese layout. Please try again.';
      hilog.error(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD selection refresh failed error=${JSON.stringify(error)}`);
    }
  }

  private async applyKeyboard(keyboard: KeyboardInfo): Promise<void> {
    try {
      this.keyboardManager.getKeyboardById(keyboard.id);
      const selection = await this.keyboardSelectionService.setSelection(keyboard.id);
      this.displayKeyboardSelection(selection);
      this.status = `${keyboard.name} is the active mmKB layout.`;
      hilog.info(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD IPC SET requestedId=${keyboard.id} returnedId=${selection.activeKeyboardId} success=true`);
    } catch (error) {
      this.status = `Could not change to ${keyboard.name}. Please try again.`;
      hilog.error(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD IPC SET requestedId=${keyboard.id} success=false error=${JSON.stringify(error)}`);
    }
  }

  private isActiveKeyboard(keyboard: KeyboardInfo): boolean {
    return keyboard.id === this.activeKeyboardId;
  }

  private activeKeyboardName(): string {
    try {
      return this.keyboardManager.getKeyboardById(this.activeKeyboardId).name;
    } catch (_error) {
      return 'Loading…';
    }
  }

  private loadAppearance(): void {
    try {
      this.appearance = MyanKeyAppearanceSettings.read(this.getHostContext());
    } catch (error) {
      this.appearance = 'light';
      hilog.error(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `Unable to read appearance setting: ${JSON.stringify(error)}`);
    }
  }

  private setAppearance(appearance: MyanKeyAppearance): void {
    try {
      MyanKeyAppearanceSettings.apply(this.getHostContext(), appearance);
      this.appearance = appearance;
    } catch (error) {
      this.status = `Unable to change appearance: ${JSON.stringify(error)}`;
    }
  }

  private loadKeyboardInteractionSettings(): void {
    try {
      const context = this.getHostContext();
      this.hapticEnabled = KeyboardHeightSettings.readHapticEnabled(context);
      this.keyPreviewEnabled = KeyboardHeightSettings.readKeyPreviewEnabled(context);
      this.keyboardTheme = KeyboardHeightSettings.readTheme(context);
      this.keyboardHeightFactor = KeyboardHeightSettings.read(context);
    } catch (error) {
      this.hapticEnabled = false;
      this.keyPreviewEnabled = true;
      this.keyboardTheme = 'system';
      this.keyboardHeightFactor = KEYBOARD_HEIGHT_FACTOR_DEFAULT;
      hilog.error(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `Unable to read keyboard interaction settings: ${JSON.stringify(error)}`);
    }
  }

  private setHapticEnabled(enabled: boolean): void {
    try {
      KeyboardHeightSettings.applyHapticEnabled(this.getHostContext(), enabled);
      this.hapticEnabled = enabled;
      hilog.info(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD HAPTIC preference persisted enabled=${enabled}`);
    } catch (error) {
      this.status = 'Unable to change Haptic Feedback.';
      hilog.error(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD HAPTIC preference failed enabled=${enabled} error=${JSON.stringify(error)}`);
    }
  }

  private setKeyPreviewEnabled(enabled: boolean): void {
    try {
      KeyboardHeightSettings.applyKeyPreviewEnabled(this.getHostContext(), enabled);
      this.keyPreviewEnabled = enabled;
      hilog.info(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD KEY PREVIEW preference persisted enabled=${enabled}`);
    } catch (error) {
      this.status = 'Unable to change Key Preview.';
      hilog.error(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD KEY PREVIEW preference failed enabled=${enabled} error=${JSON.stringify(error)}`);
    }
  }

  private setKeyboardTheme(theme: KeyboardTheme): void {
    try {
      this.keyboardTheme = KeyboardHeightSettings.applyTheme(this.getHostContext(), theme);
      hilog.info(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD THEME preference persisted theme=${this.keyboardTheme}`);
    } catch (error) {
      this.status = 'Unable to change Keyboard Theme.';
      hilog.error(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD THEME preference failed theme=${theme} error=${JSON.stringify(error)}`);
    }
  }

  /** Uses the existing persisted live-setting path on every slider change. */
  private updateKeyboardHeight(value: number): void {
    const normalized = KeyboardHeightSettings.normalize(value);
    this.keyboardHeightFactor = normalized;
    try {
      const context = this.getHostContext();
      KeyboardHeightSettings.applyTestOffset(context, 0);
      this.keyboardHeightFactor = KeyboardHeightSettings.apply(context, normalized);
      hilog.info(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD HEIGHT inline update factor=${this.keyboardHeightFactor}`);
    } catch (error) {
      this.status = 'Unable to update keyboard height.';
      hilog.error(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD HEIGHT inline update failed factor=${normalized} error=${JSON.stringify(error)}`);
    }
  }

  private resetKeyboardHeight(): void {
    try {
      const context = this.getHostContext();
      KeyboardHeightSettings.applyTestOffset(context, 0);
      this.keyboardHeightFactor = KeyboardHeightSettings.reset(context);
      hilog.info(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD HEIGHT inline reset factor=${this.keyboardHeightFactor}`);
    } catch (error) {
      this.status = 'Unable to reset keyboard height.';
      hilog.error(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD HEIGHT inline reset failed error=${JSON.stringify(error)}`);
    }
  }

  private keyboardHeightPercent(): string {
    return `${Math.round(this.keyboardHeightFactor * 100)}%`;
  }

  /** Opens the public HarmonyOS keyboard-management settings screen. */
  private openInputMethodSettings(): void {
    try {
      settings.openInputMethodSettings(this.getHostContext());
      this.status = 'Open keyboard settings to turn on mmKB.';
      hilog.info(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        'INPUT METHOD settings opened');
    } catch (error) {
      this.showEnableGuide = true;
      this.status = 'Could not open keyboard settings. Follow the quick setup steps below.';
      hilog.error(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `INPUT METHOD settings open failed error=${JSON.stringify(error)}`);
    }
  }

  private getHostContext(): Context {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('mmKB configurator has no host context.');
    }
    return context;
  }

  private isDarkMode(): boolean {
    return this.appearance === 'dark';
  }

  private headingColor(): string {
    return this.isDarkMode() ? '#F3F6FA' : '#18212D';
  }

  private contentColor(): string {
    return this.isDarkMode() ? '#E7ECF3' : '#1B2430';
  }

  private secondaryTextColor(): string {
    return this.isDarkMode() ? '#B7C2D0' : '#58677A';
  }

  private mutedTextColor(): string {
    return this.isDarkMode() ? '#99A8BA' : '#687588';
  }

  private cardColor(): string {
    return this.isDarkMode() ? '#1E2936' : '#FFFFFF';
  }

  private pageColor(): string {
    return this.isDarkMode() ? '#121A24' : '#F6F8FB';
  }

  private subtleSurfaceColor(): string {
    return this.isDarkMode() ? '#1A2634' : '#EEF3F8';
  }

  private secondaryButtonColor(): string {
    return this.isDarkMode() ? '#2A3A4C' : '#E5ECF5';
  }

  private frameColor(): string {
    return this.isDarkMode() ? '#344557' : '#D7DEE8';
  }

  private accentColor(): string {
    return '#2878D4';
  }

  private keyboardDescription(keyboard: KeyboardInfo): string {
    if (keyboard.id === 'zawcode') {
      return 'KeyMagic-compatible Unicode typing with traditional Burmese input sequences.';
    }
    return keyboard.description;
  }

  @Builder
  private buildHero() {
    Column({ space: 7 }) {
      Text('mmKB')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.headingColor())
      Text('Myanmar & English Keyboard')
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.contentColor())
      Text('Type Burmese naturally on HarmonyOS')
        .fontSize(15)
        .fontColor(this.secondaryTextColor())
        .lineHeight(22)
      Text('Powered by KeyMagic')
        .fontSize(14)
        .fontColor(this.mutedTextColor())
      Button('Enable mmKB')
        .width('100%')
        .height(50)
        .margin({ top: 8 })
        .fontColor('#FFFFFF')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(this.accentColor())
        .borderRadius(14)
        .onClick(() => this.openInputMethodSettings())
      if (this.showSetupSteps) {
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            Text('!')
              .width(24)
              .height(24)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .textAlign(TextAlign.Center)
              .backgroundColor(this.accentColor())
              .borderRadius(12)
            Text('Important — finish all 3 steps')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.headingColor())
              .layoutWeight(1)
            Button('Hide')
              .height(32)
              .fontSize(13)
              .fontColor(this.contentColor())
              .backgroundColor(this.secondaryButtonColor())
              .borderRadius(10)
              .onClick(() => this.showSetupSteps = false)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text('After opening Keyboard settings:')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.contentColor())

          Row({ space: 10 }) {
            Text('1')
              .width(28)
              .height(28)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .textAlign(TextAlign.Center)
              .backgroundColor(this.accentColor())
              .borderRadius(14)
            Text('Enable mmKB')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.contentColor())
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Row({ space: 10 }) {
            Text('2')
              .width(28)
              .height(28)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .textAlign(TextAlign.Center)
              .backgroundColor(this.accentColor())
              .borderRadius(14)
            Text('Choose mmKB as your keyboard')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.contentColor())
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Row({ space: 10 }) {
            Text('3')
              .width(28)
              .height(28)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .textAlign(TextAlign.Center)
              .backgroundColor(this.accentColor())
              .borderRadius(14)
            Column({ space: 3 }) {
              Text('Enable Full mode')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.contentColor())
              Text('Required for keyboard settings, live height adjustment, haptic feedback, and other mmKB features.')
                .fontSize(13)
                .fontColor(this.secondaryTextColor())
                .lineHeight(19)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text('Privacy: mmKB processes typing locally on your device and does not upload what you type.')
            .fontSize(13)
            .fontColor(this.secondaryTextColor())
            .lineHeight(19)
        }
        .width('100%')
        .margin({ top: 10 })
        .padding(14)
        .backgroundColor(this.subtleSurfaceColor())
        .border({ width: 1, color: this.accentColor() })
        .borderRadius(14)
        .alignItems(HorizontalAlign.Start)
      } else {
        Button('Show setup instructions')
          .height(38)
          .margin({ top: 8 })
          .fontSize(13)
          .fontColor(this.contentColor())
          .backgroundColor(this.secondaryButtonColor())
          .borderRadius(10)
          .onClick(() => this.showSetupSteps = true)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildKeyboardStatusCard() {
    Column({ space: 12 }) {
      Text('Keyboard status')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.contentColor())
      Text('mmKB is installed')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDarkMode() ? '#A9DBAE' : '#246B32')
        .lineHeight(22)
      Text('Complete the setup above, then use the test box below to try mmKB.')
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .lineHeight(21)
      Column({ space: 3 }) {
        Text('Current Burmese layout')
          .fontSize(13)
          .fontColor(this.mutedTextColor())
        Text(this.activeKeyboardName())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.contentColor())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      Text(this.status)
        .fontSize(13)
        .fontColor(this.mutedTextColor())
        .lineHeight(19)
      Row({ space: 10 }) {
        Button('Refresh')
          .layoutWeight(1)
          .height(46)
          .fontColor(this.contentColor())
          .backgroundColor(this.secondaryButtonColor())
          .borderRadius(12)
          .onClick(() => void this.refreshKeyboardSelection())
        Button(this.showLayoutChoices ? 'Hide layouts' : 'Change layout')
          .layoutWeight(1)
          .height(46)
          .fontColor('#FFFFFF')
          .backgroundColor(this.accentColor())
          .borderRadius(12)
          .onClick(() => this.showLayoutChoices = !this.showLayoutChoices)
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.cardColor())
    .border({ width: 1, color: this.frameColor() })
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildEnableGuide() {
    Column({ space: 10 }) {
      Text('Enable mmKB')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.contentColor())
      Text('1. Open keyboard settings.\n2. Turn on and choose mmKB.\n3. Enable Full mode so keyboard settings, live height adjustment, haptics, and related features work correctly.\n4. Return here to choose a Burmese layout and test typing.')
        .fontSize(15)
        .lineHeight(23)
        .fontColor(this.contentColor())
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.subtleSurfaceColor())
    .border({ width: 1, color: this.frameColor() })
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildKeyboardCard(keyboard: KeyboardInfo) {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Text(this.isActiveKeyboard(keyboard) ? '●' : '○')
          .fontSize(20)
          .fontColor(this.isActiveKeyboard(keyboard) ? '#2E8B57' : this.mutedTextColor())
        Column({ space: 4 }) {
          Text(keyboard.name)
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.contentColor())
          Text(this.keyboardDescription(keyboard))
            .fontSize(13)
            .fontColor(this.secondaryTextColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Text(this.isActiveKeyboard(keyboard) ? 'Currently active' : 'Available mmKB layout')
        .fontSize(13)
        .fontColor(this.isActiveKeyboard(keyboard) ? (this.isDarkMode() ? '#A9DBAE' : '#246B32') : this.mutedTextColor())
      Button(this.isActiveKeyboard(keyboard) ? 'Active keyboard' : 'Use this layout')
        .width('100%')
        .height(46)
        .enabled(!this.isActiveKeyboard(keyboard))
        .fontColor('#FFFFFF')
        .backgroundColor(this.isActiveKeyboard(keyboard) ? '#547767' : this.accentColor())
        .borderRadius(12)
        .onClick(() => void this.applyKeyboard(keyboard))
    }
    .width('100%')
    .height(194)
    .padding(18)
    .backgroundColor(this.cardColor())
    .border({ width: 1, color: this.isActiveKeyboard(keyboard) ? '#8BC49A' : this.frameColor() })
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildAppearanceCard() {
    Column({ space: 12 }) {
      Text('Appearance')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.contentColor())
      Text('Choose the mmKB app appearance. System-following appearance is not available yet.')
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .lineHeight(21)
      Row({ space: 10 }) {
        Button('Light')
          .layoutWeight(1)
          .height(46)
          .fontColor(this.appearance === 'light' ? '#FFFFFF' : this.contentColor())
          .backgroundColor(this.appearance === 'light' ? this.accentColor() : this.secondaryButtonColor())
          .borderRadius(12)
          .onClick(() => this.setAppearance('light'))
        Button('Dark')
          .layoutWeight(1)
          .height(46)
          .fontColor(this.appearance === 'dark' ? '#FFFFFF' : this.contentColor())
          .backgroundColor(this.appearance === 'dark' ? this.accentColor() : this.secondaryButtonColor())
          .borderRadius(12)
          .onClick(() => this.setAppearance('dark'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.cardColor())
    .border({ width: 1, color: this.frameColor() })
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildKeyboardHeightCard() {
    Column({ space: 12 }) {
      Text('Quick settings')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.contentColor())
      Text('Set up your keyboard just the way you like it.')
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .lineHeight(21)
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text('Keyboard Height')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.contentColor())
          Text('Adjust how tall mmKB appears while typing.')
            .fontSize(13)
            .fontColor(this.secondaryTextColor())
            .lineHeight(19)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(this.keyboardHeightPercent())
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accentColor())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Row({ space: 10 }) {
        Text(`${Math.round(KEYBOARD_HEIGHT_FACTOR_MIN * 100)}%`)
          .fontSize(13)
          .fontColor(this.mutedTextColor())
        Slider({
          value: this.keyboardHeightFactor,
          min: KEYBOARD_HEIGHT_FACTOR_MIN,
          max: KEYBOARD_HEIGHT_FACTOR_MAX,
          step: 0.01,
          style: SliderStyle.OutSet,
        })
          .layoutWeight(1)
          .focusable(false)
          .focusOnTouch(false)
          .onChange((value: number, _mode: SliderChangeMode) => this.updateKeyboardHeight(value))
        Text(`${Math.round(KEYBOARD_HEIGHT_FACTOR_MAX * 100)}%`)
          .fontSize(13)
          .fontColor(this.mutedTextColor())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Button('Reset to default')
        .width('100%')
        .height(42)
        .focusable(false)
        .focusOnTouch(false)
        .fontColor(this.contentColor())
        .backgroundColor(this.secondaryButtonColor())
        .borderRadius(10)
        .onClick(() => this.resetKeyboardHeight())
      Divider().color(this.frameColor())
      Column({ space: 8 }) {
        Text('Keyboard Theme')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.contentColor())
        Text('Choose the keyboard colors independently from the mmKB app appearance.')
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
          .lineHeight(19)
        Row({ space: 8 }) {
          Button('System')
            .layoutWeight(1)
            .height(42)
            .fontColor(this.keyboardTheme === 'system' ? '#FFFFFF' : this.contentColor())
            .backgroundColor(this.keyboardTheme === 'system' ? this.accentColor() : this.secondaryButtonColor())
            .borderRadius(10)
            .onClick(() => this.setKeyboardTheme('system'))
          Button('Light')
            .layoutWeight(1)
            .height(42)
            .fontColor(this.keyboardTheme === 'light' ? '#FFFFFF' : this.contentColor())
            .backgroundColor(this.keyboardTheme === 'light' ? this.accentColor() : this.secondaryButtonColor())
            .borderRadius(10)
            .onClick(() => this.setKeyboardTheme('light'))
          Button('Dark')
            .layoutWeight(1)
            .height(42)
            .fontColor(this.keyboardTheme === 'dark' ? '#FFFFFF' : this.contentColor())
            .backgroundColor(this.keyboardTheme === 'dark' ? this.accentColor() : this.secondaryButtonColor())
            .borderRadius(10)
            .onClick(() => this.setKeyboardTheme('dark'))
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      Divider().color(this.frameColor())
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text('Haptic Feedback')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.contentColor())
          Text('Feel a subtle touch response when pressing keys.')
            .fontSize(13)
            .fontColor(this.secondaryTextColor())
            .lineHeight(19)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.hapticEnabled })
          .onChange((enabled: boolean) => this.setHapticEnabled(enabled))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Divider().color(this.frameColor())
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text('Key Preview')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.contentColor())
          Text('Show a larger character above the key while you press it.')
            .fontSize(13)
            .fontColor(this.secondaryTextColor())
            .lineHeight(19)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.keyPreviewEnabled })
          .onChange((enabled: boolean) => this.setKeyPreviewEnabled(enabled))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.cardColor())
    .border({ width: 1, color: this.frameColor() })
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildKeyboardFeaturesCard() {
    Column({ space: 12 }) {
      Text('What mmKB includes')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.contentColor())
      Text('Language')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.contentColor())
      Text('Myanmar + English')
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
      Divider().color(this.frameColor())
      Text('Burmese layout')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.contentColor())
      Text('Choose a layout below to match the way you type.')
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
      Divider().color(this.frameColor())
      Text('Long-press keys')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.contentColor())
      Text('Burmese letter alternatives are available directly on the keyboard where supported.')
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .lineHeight(21)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.cardColor())
    .border({ width: 1, color: this.frameColor() })
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildTestInputCard() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('Try mmKB')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.contentColor())
          Text(`Burmese layout: ${this.activeKeyboardName()}`)
            .fontSize(14)
            .fontColor(this.secondaryTextColor())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button('Clear')
          .height(42)
          .enabled(this.testInputText.length > 0)
          .fontColor(this.contentColor())
          .backgroundColor(this.secondaryButtonColor())
          .borderRadius(10)
          .onClick(() => this.testInputText = '')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      TextArea({ text: this.testInputText, placeholder: 'Tap here to try mmKB…' })
        .width('100%')
        .height(150)
        .fontSize(18)
        .fontColor(this.contentColor())
        .placeholderColor(this.mutedTextColor())
        .copyOption(CopyOptions.LocalDevice)
        .enableKeyboardOnFocus(true)
        .padding(14)
        .backgroundColor(this.subtleSurfaceColor())
        .border({ width: this.testInputFocused ? 2 : 1, color: this.testInputFocused ? this.accentColor() : this.frameColor() })
        .borderRadius(12)
        .onFocus(() => this.testInputFocused = true)
        .onBlur(() => this.testInputFocused = false)
        .onChange((value: string) => this.testInputText = value)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.cardColor())
    .border({ width: 1, color: this.frameColor() })
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildAboutCard() {
    Column({ space: 8 }) {
      Text('About mmKB')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.contentColor())
      Text('mmKB is a Myanmar Keyboard for HarmonyOS. It processes input locally on your device and uses the KeyMagic engine for Burmese keyboard-rule processing.')
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
        .lineHeight(21)
      Text('Typed text is not uploaded, analyzed, or shared. Keyboard preferences such as layout, height, theme, haptics, key preview, and recent emoji are stored locally on the device.')
        .fontSize(13)
        .fontColor(this.secondaryTextColor())
        .lineHeight(19)
      Divider()
        .color(this.frameColor())
        .margin({ top: 4, bottom: 2 })
      Text('Open-source software')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.contentColor())
      Text('KeyMagic 3 — GNU GPL v2.0')
        .fontSize(14)
        .fontColor(this.secondaryTextColor())
      Text('mmKB includes a HarmonyOS integration of KeyMagic 3. License notices are included with the source release.')
        .fontSize(13)
        .fontColor(this.secondaryTextColor())
        .lineHeight(19)
      Text('Version 1.0.0 • KeyMagic engine')
        .fontSize(13)
        .fontColor(this.mutedTextColor())
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.cardColor())
    .border({ width: 1, color: this.frameColor() })
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column({ space: 20 }) {
        this.buildHero()
        this.buildKeyboardStatusCard()

        if (this.showLayoutChoices) {
          Text('Burmese layouts')
            .fontSize(21)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.headingColor())
            .width('100%')

          GridRow({
            columns: { xs: 1, sm: 1, md: 2, lg: 2, xl: 2, xxl: 2 },
            gutter: { x: 14, y: 14 },
            breakpoints: {
              value: ['520vp', '720vp', '960vp', '1280vp', '1600vp'],
              reference: BreakpointsReference.ComponentSize,
            },
          }) {
            ForEach(this.keyboards, (keyboard: KeyboardInfo) => {
              GridCol({ span: { xs: 1, sm: 1, md: 1, lg: 1, xl: 1, xxl: 1 } }) {
                this.buildKeyboardCard(keyboard)
              }
            }, (keyboard: KeyboardInfo): string => keyboard.id)
          }
          .width('100%')
        }

        this.buildTestInputCard()

        if (this.showEnableGuide) {
          this.buildEnableGuide()
        }

        GridRow({
          columns: { xs: 1, sm: 1, md: 2, lg: 2, xl: 2, xxl: 2 },
          gutter: { x: 14, y: 14 },
          breakpoints: {
            value: ['520vp', '720vp', '960vp', '1280vp', '1600vp'],
            reference: BreakpointsReference.ComponentSize,
          },
        }) {
          GridCol({ span: { xs: 1, sm: 1, md: 1, lg: 1, xl: 1, xxl: 1 } }) {
            this.buildKeyboardHeightCard()
          }
          GridCol({ span: { xs: 1, sm: 1, md: 1, lg: 1, xl: 1, xxl: 1 } }) {
            this.buildAppearanceCard()
          }
        }
        .width('100%')

        this.buildAboutCard()
      }
      .width('100%')
      .constraintSize({ maxWidth: '960vp' })
      .padding({ left: 18, right: 18, top: 24, bottom: 32 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor())
  }
}

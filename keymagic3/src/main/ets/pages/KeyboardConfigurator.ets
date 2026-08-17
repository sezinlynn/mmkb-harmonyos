import { hilog } from '@kit.PerformanceAnalysisKit';

import { KeyboardInfo } from '../keyboard/KeyboardInfo';
import { KeyboardManager } from '../keyboard/KeyboardManager';
import { KeyboardSelection, KeyboardSelectionService } from '../keyboard/KeyboardSelectionService';
import { MyanKeyAppearance, MyanKeyAppearanceSettings } from '../settings/MyanKeyAppearanceSettings';

const CONFIGURATOR_LOG_DOMAIN = 0x0000;
const CONFIGURATOR_LOG_TAG = 'KeyMagicKeyboard';

@Entry
@Component
struct KeyboardConfigurator {
  @State selectedNavigation: string = 'Keyboards';
  @State keyboards: KeyboardInfo[] = [];
  @State activeKeyboardId: string = '';
  @State status: string = 'Loading bundled keyboards...';
  @State testInputText: string = '';
  @State testInputFocused: boolean = false;
  @State appearance: MyanKeyAppearance = 'light';

  private readonly keyboardManager: KeyboardManager = new KeyboardManager();
  private readonly keyboardSelectionService: KeyboardSelectionService = new KeyboardSelectionService();

  aboutToAppear(): void {
    this.loadAppearance();
    void this.refreshKeyboardSelection();
  }

  onPageShow(): void {
    void this.refreshKeyboardSelection();
  }

  private displayKeyboardSelection(selection: KeyboardSelection): KeyboardInfo {
    const keyboard = this.keyboardManager.getKeyboardById(selection.activeKeyboardId);
    this.activeKeyboardId = selection.activeKeyboardId;
    this.keyboards = this.keyboardManager.getKeyboards(selection.activeKeyboardId);
    hilog.info(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
      `CONFIGURATOR STATE authoritativeId=${selection.activeKeyboardId} ` +
        `displayedActiveId=${this.activeKeyboardId} generation=${selection.keyboardGeneration}`);
    return keyboard;
  }

  private async refreshKeyboardSelection(): Promise<void> {
    try {
      const selection = await this.keyboardSelectionService.getSelection();
      const keyboard = this.displayKeyboardSelection(selection);
      this.status = `${keyboard.name} is active.`;
    } catch (error) {
      this.status = `Unable to read MyanKey keyboard selection IPC: ${JSON.stringify(error)}`;
    }
  }

  private async applyKeyboard(keyboard: KeyboardInfo): Promise<void> {
    try {
      // Validate locally for UI safety; service validation is authoritative.
      this.keyboardManager.getKeyboardById(keyboard.id);
      const selection = await this.keyboardSelectionService.setSelection(keyboard.id);
      this.displayKeyboardSelection(selection);
      this.status = `${keyboard.name} is active.`;
      hilog.info(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD IPC SET requestedId=${keyboard.id} returnedId=${selection.activeKeyboardId} ` +
          `returnedGeneration=${selection.keyboardGeneration} success=true`);
    } catch (error) {
      hilog.error(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `KEYBOARD IPC SET requestedId=${keyboard.id} returnedId=<none> returnedGeneration=<none> ` +
          `success=false error=${JSON.stringify(error)}`);
      this.status = `Unable to apply ${keyboard.name}: ${JSON.stringify(error)}`;
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

  private clearTestInput(): void {
    this.testInputText = '';
  }

  private loadAppearance(): void {
    try {
      this.appearance = MyanKeyAppearanceSettings.read(this.getHostContext());
    } catch (error) {
      hilog.error(CONFIGURATOR_LOG_DOMAIN, CONFIGURATOR_LOG_TAG, '%{public}s',
        `Unable to read MyanKey appearance setting: ${JSON.stringify(error)}`);
      this.appearance = 'light';
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

  private getHostContext(): Context {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('MyanKey configurator has no host context.');
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
    return this.isDarkMode() ? '#121A24' : '#FAFBFD';
  }

  private sidebarColor(): string {
    return this.isDarkMode() ? '#18222E' : '#F2F5F9';
  }

  private subtleSurfaceColor(): string {
    return this.isDarkMode() ? '#1A2634' : '#F5F8FC';
  }

  private secondaryButtonColor(): string {
    return this.isDarkMode() ? '#2A3A4C' : '#E7EDF5';
  }

  private frameColor(): string {
    return this.isDarkMode() ? '#344557' : '#D7DEE8';
  }

  build() {
    Row() {
      Column({ space: 8 }) {
        Text('MyanKey')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.contentColor())
          .margin({ bottom: 28 })

        Button('Keyboards')
          .width('100%')
          .fontColor(this.selectedNavigation === 'Keyboards' ? '#FFFFFF' : this.contentColor())
          .backgroundColor(this.selectedNavigation === 'Keyboards' ? '#2878D4' : '#00000000')
          .onClick(() => this.selectedNavigation = 'Keyboards')

        Button('Settings')
          .width('100%')
          .fontColor(this.selectedNavigation === 'Settings' ? '#FFFFFF' : this.contentColor())
          .backgroundColor(this.selectedNavigation === 'Settings' ? '#2878D4' : '#00000000')
          .onClick(() => this.selectedNavigation = 'Settings')

        Button('About')
          .width('100%')
          .fontColor(this.selectedNavigation === 'About' ? '#FFFFFF' : this.contentColor())
          .backgroundColor(this.selectedNavigation === 'About' ? '#2878D4' : '#00000000')
          .onClick(() => this.selectedNavigation = 'About')

        Blank()
          .layoutWeight(1)

        Text('MyanKey for physical keyboards')
          .fontSize(12)
          .fontColor(this.mutedTextColor())
      }
      .width(220)
      .height('100%')
      .padding(22)
      .backgroundColor(this.sidebarColor())
      .alignItems(HorizontalAlign.Start)

      Divider()
        .vertical(true)
        .color(this.frameColor())

      Scroll() {
        Column({ space: 18 }) {
          if (this.selectedNavigation === 'Keyboards') {
            Text('Installed Keyboards')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.headingColor())

            Text('Bundled layouts supported by MyanKey.')
              .fontSize(15)
              .fontColor(this.secondaryTextColor())

            Button('How to enable MyanKey')
              .fontColor(this.contentColor())
              .backgroundColor(this.secondaryButtonColor())
              .borderRadius(8)
              .onClick(() => this.selectedNavigation = 'EnableGuide')

            Text('New to MyanKey? Enable it in HarmonyOS Input Method settings before typing.')
              .fontSize(14)
              .fontColor(this.secondaryTextColor())
              .padding(12)
              .width('100%')
              .backgroundColor(this.subtleSurfaceColor())
              .border({ width: 1, color: this.frameColor() })
              .borderRadius(8)

            Text(this.status)
              .fontSize(14)
              .fontColor(this.isDarkMode() ? '#A9DBAE' : '#356A3B')
              .padding(12)
              .width('100%')
              .backgroundColor(this.isDarkMode() ? '#193923' : '#EDF7EE')
              .borderRadius(8)

            GridRow({
              columns: { xs: 1, sm: 1, md: 2, lg: 3, xl: 3, xxl: 3 },
              gutter: { x: 16, y: 16 },
              breakpoints: {
                value: ['540vp', '720vp', '900vp', '1280vp', '1600vp'],
                reference: BreakpointsReference.ComponentSize,
              },
            }) {
              ForEach(this.keyboards, (keyboard: KeyboardInfo) => {
                GridCol({
                  span: { xs: 1, sm: 1, md: 1, lg: 1, xl: 1, xxl: 1 },
                }) {
                  Column({ space: 14 }) {
                Row({ space: 12 }) {
                  Text(this.isActiveKeyboard(keyboard) ? '●' : '○')
                    .fontSize(22)
                    .fontColor(this.isActiveKeyboard(keyboard) ? '#2E8B57' : '#8B98A8')
                    .margin({ top: 1 })
                  Column({ space: 5 }) {
                    Text(keyboard.name)
                      .fontSize(21)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.contentColor())
                    Text(keyboard.description)
                      .fontSize(14)
                      .fontColor(this.secondaryTextColor())
                    if (keyboard.author !== undefined) {
                      Text(`Author: ${keyboard.author}`)
                        .fontSize(13)
                        .fontColor(this.mutedTextColor())
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if (this.isActiveKeyboard(keyboard)) {
                    Text('Active')
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.isDarkMode() ? '#A9DBAE' : '#246B32')
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .backgroundColor(this.isDarkMode() ? '#20492C' : '#DDF3E0')
                      .borderRadius(16)
                  }
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)

                Row({ space: 12 }) {
                  Text(keyboard.resourcePath)
                    .fontSize(12)
                    .fontColor(this.mutedTextColor())
                    .layoutWeight(1)
                  Text(this.isActiveKeyboard(keyboard) ? 'Currently active' : 'Select this keyboard')
                    .fontSize(13)
                    .fontColor(this.isActiveKeyboard(keyboard) ?
                      (this.isDarkMode() ? '#A9DBAE' : '#246B32') : this.secondaryTextColor())
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                Blank()
                  .layoutWeight(1)

                Button(this.isActiveKeyboard(keyboard) ? 'Active Keyboard' : 'Use')
                  .enabled(!this.isActiveKeyboard(keyboard))
                  .fontColor('#FFFFFF')
                  .backgroundColor(this.isActiveKeyboard(keyboard) ? '#547767' : '#2878D4')
                  .borderRadius(8)
                  .onClick(() => void this.applyKeyboard(keyboard))
                  }
                  .width('100%')
                  .height(320)
                  .padding(20)
                  .backgroundColor(this.cardColor())
                  .border({ width: 1, color: this.isActiveKeyboard(keyboard) ? '#8BC49A' : this.frameColor() })
                  .borderRadius(12)
                }
              }, (keyboard: KeyboardInfo): string => keyboard.id)
            }
            .width('100%')

            this.buildTestInputArea()
          } else if (this.selectedNavigation === 'Settings') {
            this.buildSettingsPage()
          } else if (this.selectedNavigation === 'EnableGuide') {
            this.buildEnableGuide()
          } else {
            this.buildAboutPage()
          }
        }
        .width('100%')
        .padding({ left: 36, right: 44, top: 36, bottom: 36 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .height('100%')
      .backgroundColor(this.pageColor())
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildEnableGuide() {
    Column({ space: 18 }) {
      Row({ space: 16 }) {
        Column({ space: 6 }) {
          Text('How to enable MyanKey')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.headingColor())
          Text('Enable MyanKey once in HarmonyOS Settings, then select it as your input method.')
            .fontSize(15)
            .fontColor(this.secondaryTextColor())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('Done')
          .fontColor(this.contentColor())
          .backgroundColor(this.secondaryButtonColor())
          .borderRadius(8)
          .onClick(() => this.selectedNavigation = 'Keyboards')
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Column({ space: 12 }) {
        Text('Before using MyanKey, you need to enable it as an input method in HarmonyOS Settings. You only need to do this once.')
          .fontSize(16)
          .fontColor(this.contentColor())
          .lineHeight(24)

        Divider().color(this.frameColor())

        Text('1. Open HarmonyOS Settings.')
          .fontSize(16)
          .fontColor(this.contentColor())
        Text('2. Open the keyboard / input method settings. If you cannot find it, search Settings for: “Input method”.')
          .fontSize(16)
          .fontColor(this.contentColor())
          .lineHeight(24)
        Text('3. Find MyanKey in the list of available input methods.')
          .fontSize(16)
          .fontColor(this.contentColor())
        Text('4. Enter MyanKey.')
          .fontSize(16)
          .fontColor(this.contentColor())
        Text('5. Enable both Input Methods and Full Mode. Full Mode is required for physical keyboard input.')
          .fontSize(16)
          .fontColor(this.contentColor())
        Text('6. Select MyanKey as your current input method.')
          .fontSize(16)
          .fontColor(this.contentColor())
        Text('7. Return to MyanKey and choose the Burmese keyboard layout you want to use:')
          .fontSize(16)
          .fontColor(this.contentColor())
          .lineHeight(24)
        Text('• ZawCode\n• \u1019\u103c\u1014\u103a\u1005\u1036 (Smart)\n• ')
          .fontSize(16)
          .fontColor(this.secondaryTextColor())
          .lineHeight(25)
          .margin({ left: 12 })
        Text('7. Click inside any text field and start typing.')
          .fontSize(16)
          .fontColor(this.contentColor())
      }
      .width('100%')
      .padding(20)
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.frameColor() })
      .borderRadius(12)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text('MyanKey controls the Burmese layout itself. To change between ZawCode, \u1019\u103c\u1014\u103a\u1005\u1036 (Smart), and , use the Keyboards page inside MyanKey.')
          .fontSize(15)
          .fontColor(this.secondaryTextColor())
          .lineHeight(23)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.subtleSurfaceColor())
      .border({ width: 1, color: this.frameColor() })
      .borderRadius(10)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildTestInputArea() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Text('Test MyanKey')
            .fontSize(21)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.contentColor())
          Text('Click the box below and start typing to test the active keyboard.')
            .fontSize(14)
            .fontColor(this.secondaryTextColor())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('Clear')
          .fontColor(this.contentColor())
          .backgroundColor(this.secondaryButtonColor())
          .borderRadius(8)
          .enabled(this.testInputText.length > 0)
          .onClick(() => this.clearTestInput())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(`Active keyboard: ${this.activeKeyboardName()}`)
        .fontSize(14)
        .fontColor(this.isDarkMode() ? '#A9DBAE' : '#246B32')
        .fontWeight(FontWeight.Medium)

      TextArea({ text: this.testInputText, placeholder: 'Type here to test your active keyboard…' })
        .width('100%')
        .height(180)
        .fontSize(19)
        .fontColor(this.contentColor())
        .placeholderColor(this.mutedTextColor())
        .copyOption(CopyOptions.LocalDevice)
        .enableKeyboardOnFocus(true)
        .padding(14)
        .backgroundColor(this.cardColor())
        .border({ width: this.testInputFocused ? 2 : 1, color: this.testInputFocused ? '#2878D4' : this.frameColor() })
        .borderRadius(10)
        .onFocus(() => this.testInputFocused = true)
        .onBlur(() => this.testInputFocused = false)
        .onChange((value: string) => this.testInputText = value)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.subtleSurfaceColor())
    .border({ width: 1, color: this.frameColor() })
    .borderRadius(12)
  }

  @Builder
  private buildSettingsPage() {
    Column({ space: 18 }) {
      Text('Settings')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.headingColor())

      Column({ space: 14 }) {
        Text('General')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.contentColor())
        Text('Active Keyboard')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.contentColor())
        Text(this.activeKeyboardName())
          .fontSize(16)
          .fontColor(this.isDarkMode() ? '#A9DBAE' : '#246B32')
        Text('Choose a different layout from the Keyboards page.')
          .fontSize(13)
          .fontColor(this.mutedTextColor())
      }
      .width('100%')
      .padding(20)
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.frameColor() })
      .borderRadius(12)

      Column({ space: 14 }) {
        Text('Appearance')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.contentColor())
        Text('Choose the MyanKey app appearance.')
          .fontSize(13)
          .fontColor(this.mutedTextColor())
        Row({ space: 10 }) {
          Button('Light')
            .fontColor(this.appearance === 'light' ? '#FFFFFF' : this.contentColor())
            .backgroundColor(this.appearance === 'light' ? '#2878D4' : this.secondaryButtonColor())
            .borderRadius(8)
            .onClick(() => this.setAppearance('light'))
          Button('Dark')
            .fontColor(this.appearance === 'dark' ? '#FFFFFF' : this.contentColor())
            .backgroundColor(this.appearance === 'dark' ? '#2878D4' : this.secondaryButtonColor())
            .borderRadius(8)
            .onClick(() => this.setAppearance('dark'))
        }
        Text(`Current appearance: ${this.appearance === 'dark' ? 'Dark' : 'Light'}`)
          .fontSize(13)
          .fontColor(this.mutedTextColor())
      }
      .width('100%')
      .padding(20)
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.frameColor() })
      .borderRadius(12)

      Column({ space: 14 }) {
        Text('Composition Popup')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.contentColor())
        Text('Enabled')
          .fontSize(16)
          .fontColor(this.isDarkMode() ? '#A9DBAE' : '#246B32')
        Text('Shows the current uncommitted composition near the editor while you type.')
          .fontSize(13)
          .fontColor(this.mutedTextColor())
      }
      .width('100%')
      .padding(20)
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.frameColor() })
      .borderRadius(12)

      Column({ space: 14 }) {
        Text('Troubleshooting')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.contentColor())
        Text('If input stops responding, return to the Keyboards page and select the active layout again.')
          .fontSize(14)
          .fontColor(this.secondaryTextColor())
      }
      .width('100%')
      .padding(20)
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.frameColor() })
      .borderRadius(12)

      Column({ space: 4 }) {
        Text('Version / Build')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.contentColor())
        Text('MyanKey — Version 1.0.0 (build 1)')
          .fontSize(16)
          .fontColor(this.isDarkMode() ? '#A9DBAE' : '#246B32')
        Text('HarmonyOS PC /2in1 release build')
          .fontSize(13)
          .fontColor(this.mutedTextColor())
      }
      .width('100%')
      .padding(20)
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.frameColor() })
      .borderRadius(12)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildAboutPage() {
    Column({ space: 18 }) {
      Column({ space: 6 }) {
        Text('MyanKey')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.headingColor())
        Text('Burmese physical keyboard input for HarmonyOS')
          .fontSize(18)
          .fontColor(this.secondaryTextColor())
        Text('MyanKey brings flexible Burmese keyboard layouts to HarmonyOS, powered by the KeyMagic input engine.')
          .fontSize(15)
          .fontColor(this.secondaryTextColor())
      }
      .alignItems(HorizontalAlign.Start)

      Column({ space: 12 }) {
        Text('Current Supported Layouts')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.contentColor())
        Text('ZawCode\nမြန်စံ (Smart)\n')
          .fontSize(15)
          .fontColor(this.contentColor())
          .lineHeight(25)
      }
      .width('100%')
      .padding(20)
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.frameColor() })
      .borderRadius(12)

      Column({ space: 12 }) {
        Text('Privacy')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.contentColor())
        Text('MyanKey processes keyboard input locally on your device. It does not record, collect, transmit, or store what you type, including keystrokes, composed text, passwords, messages, or other typed content.')
          .fontSize(15)
          .fontColor(this.contentColor())
          .lineHeight(23)
        Text('The app stores only settings required for operation, such as your selected keyboard layout and local preferences. This build includes no advertising trackers or analytics that record keyboard input.')
          .fontSize(15)
          .fontColor(this.contentColor())
          .lineHeight(23)
      }
      .width('100%')
      .padding(20)
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.frameColor() })
      .borderRadius(12)

      Column({ space: 12 }) {
        Text('Powered by KeyMagic')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.contentColor())
        Text('MyanKey uses the open-source KeyMagic engine for keyboard rule processing. KeyMagic and its keyboard contributors retain their applicable copyright notices.')
          .fontSize(15)
          .fontColor(this.contentColor())
          .lineHeight(23)
        Text('Open-source acknowledgement: KeyMagic 3 — GNU General Public License, version 2. MyanKey is a HarmonyOS adapter and is not an official KeyMagic product.')
          .fontSize(14)
          .fontColor(this.mutedTextColor())
          .lineHeight(22)
      }
      .width('100%')
      .padding(20)
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.frameColor() })
      .borderRadius(12)

      Column({ space: 12 }) {
        Text('App Details')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.contentColor())
        Text('MyanKey\nVersion 1.0.0 (build 1)\nMade for HarmonyOS')
          .fontSize(14)
          .fontColor(this.secondaryTextColor())
          .lineHeight(23)
      }
      .width('100%')
      .padding(20)
      .backgroundColor(this.cardColor())
      .border({ width: 1, color: this.frameColor() })
      .borderRadius(12)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

}

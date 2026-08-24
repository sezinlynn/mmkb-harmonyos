import { AbilityConstant, Configuration, ConfigurationConstant, EnvironmentCallback, Want } from '@kit.AbilityKit';
import { InputMethodExtensionAbility } from '@kit.IMEKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { KeyMagicImeController } from './KeyMagicImeController';

const IME_LOG_DOMAIN = 0x0000;
const IME_LOG_TAG = 'KeyMagicIme';

/** Relays system appearance changes to the presentation-only IME popup. */
class KeyMagicPopupEnvironmentCallback extends EnvironmentCallback {
  private readonly controller: KeyMagicImeController;

  constructor(controller: KeyMagicImeController) {
    super();
    this.controller = controller;
  }

  onConfigurationUpdated(configuration: Configuration): void {
    this.controller.setCompositionPopupDarkMode(
      configuration.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK,
    );
  }

  onMemoryLevel(_level: AbilityConstant.MemoryLevel): void {
    // The popup has no cache or editor state to release here.
  }
}

/** Entry point registered as the mmKB parent input method. */
export default class KeyMagicInputMethodService extends InputMethodExtensionAbility {
  private readonly controller: KeyMagicImeController = new KeyMagicImeController();
  private readonly popupEnvironmentCallback: KeyMagicPopupEnvironmentCallback =
    new KeyMagicPopupEnvironmentCallback(this.controller);
  private popupEnvironmentCallbackId: number | undefined;

  onCreate(want: Want): void {
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      `IME ABILITY START abilityName=KeyMagicInputMethodService parentLabel=mmKB ` +
        `wantAbilityName=${want.abilityName === undefined ? '<none>' : want.abilityName}`);
    this.controller.setCompositionPopupDarkMode(
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK,
    );
    try {
      this.popupEnvironmentCallbackId = this.context.getApplicationContext().on(
        'environment',
        this.popupEnvironmentCallback,
      );
    } catch (error) {
      hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
        `Unable to subscribe to popup appearance changes: ${JSON.stringify(error)}`);
    }
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      'IME EXTENSION onCreate controller.start begin.');
    this.controller.start(this.context);
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      'IME EXTENSION onCreate controller.start returned.');
  }

  onDestroy(): void {
    if (this.popupEnvironmentCallbackId !== undefined) {
      this.context.getApplicationContext().off('environment', this.popupEnvironmentCallbackId).catch((error: Object) => {
        hilog.error(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
          `Unable to unsubscribe from popup appearance changes: ${JSON.stringify(error)}`);
      });
      this.popupEnvironmentCallbackId = undefined;
    }
    this.controller.stop();
    hilog.info(IME_LOG_DOMAIN, IME_LOG_TAG, '%{public}s',
      'IME ABILITY STOP abilityName=KeyMagicInputMethodService parentLabel=mmKB');
  }
}

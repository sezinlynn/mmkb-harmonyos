import { ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export type MyanKeyAppearance = 'light' | 'dark';

const APPEARANCE_STORE_NAME = 'myankey_appearance_settings';
const APPEARANCE_KEY = 'appearance';

function normalizeAppearance(value: preferences.ValueType): MyanKeyAppearance {
  return value === 'dark' ? 'dark' : 'light';
}

/**
 * UI-only appearance preference. It is separate from keyboard selection and
 * never participates in IME input, engine loading, or composition state.
 */
export class MyanKeyAppearanceSettings {
  static read(context: Context): MyanKeyAppearance {
    const store = preferences.getPreferencesSync(context.getApplicationContext(), {
      name: APPEARANCE_STORE_NAME,
    });
    return normalizeAppearance(store.getSync(APPEARANCE_KEY, 'light'));
  }

  static apply(context: Context, appearance: MyanKeyAppearance): void {
    const store = preferences.getPreferencesSync(context.getApplicationContext(), {
      name: APPEARANCE_STORE_NAME,
    });
    store.putSync(APPEARANCE_KEY, appearance);
    store.flushSync();
    context.getApplicationContext().setColorMode(
      appearance === 'dark' ?
        ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
        ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT,
    );
  }
}

import { dataShare, preferences, ValueType } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import commonEventManager from '@ohos.commonEventManager';

/**
 * One persisted, bounded factor shared by the application UI and the
 * InputMethodExtension process. The numerical value is intentionally an
 * implementation detail; the settings UI presents only a Low–High slider.
 */
export const KEYBOARD_HEIGHT_PREFERENCES_STORE = 'myankey_keyboard_preferences';
export const KEYBOARD_HEIGHT_FACTOR_KEY = 'heightFactor';
// A temporary, explicit panel-resize probe. It does not alter the saved user
// height factor and exists solely to prove that a visible fixed panel accepts
// a real runtime geometry change.
export const KEYBOARD_HEIGHT_TEST_OFFSET_KEY = 'heightTestOffsetPixels';
export const KEYBOARD_HEIGHT_FACTOR_MIN = 0.65;
export const KEYBOARD_HEIGHT_FACTOR_MAX = 1.00;
export const KEYBOARD_HEIGHT_FACTOR_DEFAULT = 0.75;
export const KEYBOARD_HAPTIC_ENABLED_KEY = 'hapticEnabled';
export const KEYBOARD_KEY_PREVIEW_ENABLED_KEY = 'keyPreviewEnabled';
export const KEYBOARD_THEME_KEY = 'keyboardTheme';
export type KeyboardTheme = 'system' | 'light' | 'dark';
export const KEYBOARD_THEME_DEFAULT: KeyboardTheme = 'system';
// These are panel-process UI state names, not persisted preference keys.
export const KEYBOARD_HAPTIC_APP_STORAGE_KEY = 'myankeyKeyboardHapticEnabled';
export const KEYBOARD_KEY_PREVIEW_APP_STORAGE_KEY = 'myankeyKeyboardKeyPreviewEnabled';
export const KEYBOARD_THEME_APP_STORAGE_KEY = 'myankeyKeyboardTheme';
// Live values are sent post-flush to the separate InputMethodExtension
// process. Preferences remains the persisted source for a freshly started IME.
export const KEYBOARD_VISUAL_SETTINGS_CHANGED_EVENT =
  'com.szl.myankey.action.KEYBOARD_VISUAL_SETTINGS_CHANGED';
/**
 * System-owned shared config. Unlike an app Preferences cache, this value is
 * available to both the UIAbility and the separately restarted IME process.
 */
export const KEYBOARD_VISUAL_SETTINGS_PROXY_URI =
  'datashareproxy://com.szl.myankey/keymagic3/keyboard-visual-settings';
// Haptic feedback is opt-in because devices vary greatly in feel and support.
export const KEYBOARD_HAPTIC_ENABLED_DEFAULT = false;
// Character previews are a familiar mobile-keyboard visual affordance.
export const KEYBOARD_KEY_PREVIEW_ENABLED_DEFAULT = true;

const VISUAL_SETTINGS_IPC_CONFIG: dataShare.DataProxyConfig = {
  type: dataShare.DataProxyType.SHARED_CONFIG,
};
const VISUAL_SETTINGS_LOG_DOMAIN = 0x0000;
const VISUAL_SETTINGS_LOG_TAG = 'KeyMagicKeyboard';

/** The complete panel-only state exchanged through the system Data Proxy. */
export interface KeyboardVisualSettingsSnapshot {
  factor: number;
  testOffsetPixels: number;
  hapticEnabled: boolean;
  keyPreviewEnabled: boolean;
  theme: KeyboardTheme;
}

export type KeyboardVisualSettingsObserver = (snapshot: KeyboardVisualSettingsSnapshot) => void;

function encodeVisualSettings(snapshot: KeyboardVisualSettingsSnapshot): string {
  return `${snapshot.factor}|${snapshot.testOffsetPixels}|${snapshot.hapticEnabled ? '1' : '0'}|` +
    `${snapshot.keyPreviewEnabled ? '1' : '0'}|${snapshot.theme}`;
}

function decodeVisualSettings(value: ValueType | undefined): KeyboardVisualSettingsSnapshot | undefined {
  if (typeof value !== 'string') {
    return undefined;
  }
  const values = value.split('|');
  // Accept the old four-field record so existing installs upgrade cleanly.
  if (values.length !== 4 && values.length !== 5) {
    return undefined;
  }
  const rawFactor = Number(values[0]);
  const rawOffset = Number(values[1]);
  if (!Number.isFinite(rawFactor) || !Number.isFinite(rawOffset) ||
    (values[2] !== '0' && values[2] !== '1') || (values[3] !== '0' && values[3] !== '1')) {
    return undefined;
  }
  return {
    factor: KeyboardHeightSettings.normalize(rawFactor),
    testOffsetPixels: Math.max(-300, Math.min(300, Math.round(rawOffset))),
    hapticEnabled: values[2] === '1',
    keyPreviewEnabled: values[3] === '1',
    theme: KeyboardHeightSettings.normalizeTheme(values.length >= 5 ? values[4] : KEYBOARD_THEME_DEFAULT),
  };
}

/**
 * A tiny system-authoritative store for settings that must survive an IME
 * process restart. It follows the existing keyboard-selection proxy pattern.
 */
export class KeyboardVisualSettingsIpc {
  private dataProxy: dataShare.DataProxyHandle | undefined;
  private dataProxyPromise: Promise<dataShare.DataProxyHandle> | undefined;
  private observing: boolean = false;
  private observers: KeyboardVisualSettingsObserver[] = [];

  async publish(snapshot: KeyboardVisualSettingsSnapshot): Promise<void> {
    const handle = await this.getDataProxy();
    const results = await handle.publish([{
      uri: KEYBOARD_VISUAL_SETTINGS_PROXY_URI,
      value: encodeVisualSettings(snapshot),
    }], VISUAL_SETTINGS_IPC_CONFIG);
    if (results.length !== 1 || results[0].result !== dataShare.DataProxyErrorCode.SUCCESS) {
      const result = results.length === 0 ? '<none>' : `${results[0].result}`;
      throw new Error(`Keyboard visual settings IPC publish failed with result=${result}.`);
    }
  }

  async get(): Promise<KeyboardVisualSettingsSnapshot | undefined> {
    const handle = await this.getDataProxy();
    const results = await handle.get([KEYBOARD_VISUAL_SETTINGS_PROXY_URI], VISUAL_SETTINGS_IPC_CONFIG);
    if (results.length !== 1) {
      throw new Error(`Keyboard visual settings IPC returned ${results.length} records.`);
    }
    const result = results[0];
    if (result.result === dataShare.DataProxyErrorCode.URI_NOT_EXIST) {
      return undefined;
    }
    if (result.result !== dataShare.DataProxyErrorCode.SUCCESS) {
      throw new Error(`Keyboard visual settings IPC get failed with result=${result.result}.`);
    }
    const snapshot = decodeVisualSettings(result.value);
    if (snapshot === undefined) {
      throw new Error('Keyboard visual settings IPC returned an invalid record.');
    }
    return snapshot;
  }

  async startObserving(observer: KeyboardVisualSettingsObserver): Promise<KeyboardVisualSettingsSnapshot | undefined> {
    this.observers.push(observer);
    const handle = await this.getDataProxy();
    if (!this.observing) {
      const registration = handle.on('dataChange', [KEYBOARD_VISUAL_SETTINGS_PROXY_URI],
        VISUAL_SETTINGS_IPC_CONFIG, (_error, changes) => {
          for (let index = 0; index < changes.length; index++) {
            if (changes[index].uri === KEYBOARD_VISUAL_SETTINGS_PROXY_URI) {
              void this.refreshFromChangeNotification();
              break;
            }
          }
        });
      if (registration.length !== 1 || registration[0].result !== dataShare.DataProxyErrorCode.SUCCESS) {
        throw new Error('Unable to observe keyboard visual settings IPC changes.');
      }
      this.observing = true;
    }
    const snapshot = await this.get();
    if (snapshot !== undefined) {
      observer(snapshot);
    }
    return snapshot;
  }

  private async getDataProxy(): Promise<dataShare.DataProxyHandle> {
    if (this.dataProxy !== undefined) {
      return this.dataProxy;
    }
    if (this.dataProxyPromise === undefined) {
      this.dataProxyPromise = dataShare.createDataProxyHandle();
    }
    this.dataProxy = await this.dataProxyPromise;
    return this.dataProxy;
  }

  private async refreshFromChangeNotification(): Promise<void> {
    try {
      const snapshot = await this.get();
      if (snapshot === undefined) {
        return;
      }
      for (let index = 0; index < this.observers.length; index++) {
        this.observers[index](snapshot);
      }
    } catch (error) {
      hilog.error(VISUAL_SETTINGS_LOG_DOMAIN, VISUAL_SETTINGS_LOG_TAG, '%{public}s',
        `HEIGHT visual IPC refresh failed error=${JSON.stringify(error)}`);
    }
  }
}

/** Process-local handle to the one system-authoritative visual record. */
export const keyboardVisualSettingsIpc = new KeyboardVisualSettingsIpc();

/** UI-only fixed-keyboard height preference shared across MyanKey processes. */
export class KeyboardHeightSettings {
  /**
   * Touching an ordinary app control may cause the system to restart the
   * selected InputMethodExtension before it subscribes to the first event.
   * Keep just one short replay for the newest post-flush visual state.
   */
  private static visualSettingsReplayTimer: number = -1;

  static normalize(value: number): number {
    if (!Number.isFinite(value)) {
      return KEYBOARD_HEIGHT_FACTOR_DEFAULT;
    }
    return Math.max(KEYBOARD_HEIGHT_FACTOR_MIN, Math.min(KEYBOARD_HEIGHT_FACTOR_MAX, value));
  }

  static normalizeTheme(value: preferences.ValueType | ValueType | string | undefined): KeyboardTheme {
    return value === 'light' || value === 'dark' ? value : 'system';
  }

  static read(context: Context): number {
    const stored = KeyboardHeightSettings.open(context).getSync(
      KEYBOARD_HEIGHT_FACTOR_KEY,
      KEYBOARD_HEIGHT_FACTOR_DEFAULT,
    );
    const value = typeof stored === 'number' ? stored : Number(`${stored}`);
    return KeyboardHeightSettings.normalize(value);
  }

  /** Persists immediately so the IME's multi-process observer can resize live. */
  static apply(context: Context, factor: number): number {
    const normalized = KeyboardHeightSettings.normalize(factor);
    const store = KeyboardHeightSettings.open(context);
    store.putSync(KEYBOARD_HEIGHT_FACTOR_KEY, normalized);
    store.flushSync();
    KeyboardHeightSettings.publishVisualSettingsChanged(context, 'height-factor', normalized);
    return normalized;
  }

  static reset(context: Context): number {
    return KeyboardHeightSettings.apply(context, KEYBOARD_HEIGHT_FACTOR_DEFAULT);
  }

  static readTestOffset(context: Context): number {
    const stored = KeyboardHeightSettings.open(context).getSync(KEYBOARD_HEIGHT_TEST_OFFSET_KEY, 0);
    const value = typeof stored === 'number' ? stored : Number(`${stored}`);
    if (!Number.isFinite(value)) {
      return 0;
    }
    // Keep this diagnostic bounded. It is intentionally in physical pixels,
    // matching inputMethodEngine.Panel rect coordinates.
    return Math.max(-300, Math.min(300, Math.round(value)));
  }

  static applyTestOffset(context: Context, offsetPixels: number): number {
    const normalized = Math.max(-300, Math.min(300, Math.round(offsetPixels)));
    const store = KeyboardHeightSettings.open(context);
    store.putSync(KEYBOARD_HEIGHT_TEST_OFFSET_KEY, normalized);
    store.flushSync();
    KeyboardHeightSettings.publishVisualSettingsChanged(context, 'height-direct-test', undefined, normalized);
    return normalized;
  }

  static readHapticEnabled(context: Context): boolean {
    return KeyboardHeightSettings.readBoolean(context, KEYBOARD_HAPTIC_ENABLED_KEY,
      KEYBOARD_HAPTIC_ENABLED_DEFAULT);
  }

  static applyHapticEnabled(context: Context, enabled: boolean): void {
    KeyboardHeightSettings.applyBoolean(context, KEYBOARD_HAPTIC_ENABLED_KEY, enabled);
  }

  static readKeyPreviewEnabled(context: Context): boolean {
    return KeyboardHeightSettings.readBoolean(context, KEYBOARD_KEY_PREVIEW_ENABLED_KEY,
      KEYBOARD_KEY_PREVIEW_ENABLED_DEFAULT);
  }

  static applyKeyPreviewEnabled(context: Context, enabled: boolean): void {
    KeyboardHeightSettings.applyBoolean(context, KEYBOARD_KEY_PREVIEW_ENABLED_KEY, enabled);
  }

  static readTheme(context: Context): KeyboardTheme {
    const stored = KeyboardHeightSettings.open(context).getSync(KEYBOARD_THEME_KEY, KEYBOARD_THEME_DEFAULT);
    return KeyboardHeightSettings.normalizeTheme(stored);
  }

  static applyTheme(context: Context, theme: KeyboardTheme): KeyboardTheme {
    const normalized = KeyboardHeightSettings.normalizeTheme(theme);
    const store = KeyboardHeightSettings.open(context);
    store.putSync(KEYBOARD_THEME_KEY, normalized);
    store.flushSync();
    KeyboardHeightSettings.publishVisualSettingsChanged(
      context,
      'keyboard-theme',
      undefined,
      undefined,
      undefined,
      undefined,
      normalized,
    );
    return normalized;
  }

  private static readBoolean(context: Context, key: string, fallback: boolean): boolean {
    const stored = KeyboardHeightSettings.open(context).getSync(key, fallback);
    return typeof stored === 'boolean' ? stored : fallback;
  }

  private static applyBoolean(context: Context, key: string, enabled: boolean): void {
    const store = KeyboardHeightSettings.open(context);
    store.putSync(key, enabled);
    store.flushSync();
    KeyboardHeightSettings.publishVisualSettingsChanged(
      context,
      key,
      undefined,
      undefined,
      key === KEYBOARD_HAPTIC_ENABLED_KEY ? enabled : undefined,
      key === KEYBOARD_KEY_PREVIEW_ENABLED_KEY ? enabled : undefined,
    );
  }

  /**
   * The public common event is the live IPC path. It carries the exact values
   * after flushSync(), avoiding a second process's stale Preferences cache.
   */
  private static publishVisualSettingsChanged(
    context: Context,
    reason: string,
    factorOverride?: number,
    testOffsetOverride?: number,
    hapticOverride?: boolean,
    keyPreviewOverride?: boolean,
    themeOverride?: KeyboardTheme,
  ): void {
    try {
      const factor = factorOverride ?? KeyboardHeightSettings.read(context);
      const testOffset = testOffsetOverride ?? KeyboardHeightSettings.readTestOffset(context);
      const hapticEnabled = hapticOverride ?? KeyboardHeightSettings.readHapticEnabled(context);
      const keyPreviewEnabled = keyPreviewOverride ?? KeyboardHeightSettings.readKeyPreviewEnabled(context);
      const theme = themeOverride ?? KeyboardHeightSettings.readTheme(context);
      const bundleName = context.applicationInfo.name;
      const data = `${factor}|${testOffset}|${hapticEnabled ? '1' : '0'}|${keyPreviewEnabled ? '1' : '0'}|${theme}|${reason}`;
      const snapshot: KeyboardVisualSettingsSnapshot = {
        factor,
        testOffsetPixels: testOffset,
        hapticEnabled,
        keyPreviewEnabled,
        theme,
      };
      // This is the durable cross-process source. It survives the normal
      // teardown/restart that occurs when the settings page changes focus.
      void keyboardVisualSettingsIpc.publish(snapshot).catch((error: Error): void => {
        hilog.error(VISUAL_SETTINGS_LOG_DOMAIN, VISUAL_SETTINGS_LOG_TAG, '%{public}s',
          `HEIGHT visual IPC publish failed reason=${reason} error=${JSON.stringify(error)}`);
      });
      KeyboardHeightSettings.sendVisualSettingsEvent(bundleName, data);

      // The initial event is the normal live path. This bounded replay carries
      // exactly the same state if an app-control tap briefly restarts the IME
      // process between write and subscription; it is not a polling loop.
      if (KeyboardHeightSettings.visualSettingsReplayTimer !== -1) {
        clearTimeout(KeyboardHeightSettings.visualSettingsReplayTimer);
      }
      KeyboardHeightSettings.visualSettingsReplayTimer = setTimeout((): void => {
        KeyboardHeightSettings.visualSettingsReplayTimer = -1;
        KeyboardHeightSettings.sendVisualSettingsEvent(bundleName, data);
      }, 650);
    } catch (_error) {
      // Visual IPC must not make a successful settings write fail.
    }
  }

  private static sendVisualSettingsEvent(bundleName: string, data: string): void {
    // The installed 6.1 SDK exposes the callback overload. A compact data
    // string also avoids ArkTS's unsupported computed property names.
    commonEventManager.publish(KEYBOARD_VISUAL_SETTINGS_CHANGED_EVENT, {
      bundleName,
      data,
    }, (): void => {});
  }

  static open(context: Context): preferences.Preferences {
    return preferences.getPreferencesSync(context.getApplicationContext(), {
      name: KEYBOARD_HEIGHT_PREFERENCES_STORE,
    });
  }
}


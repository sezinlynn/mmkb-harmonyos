import { dataShare, ValueType } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { KeyboardManager } from './KeyboardManager';

/** The one keyboard-selection record shared by the UI ability and the IME. */
export interface KeyboardSelection {
  activeKeyboardId: string;
  keyboardGeneration: number;
}

type KeyboardSelectionObserver = (selection: KeyboardSelection) => void;

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'MyanKeySelection';
const DEFAULT_KEYBOARD_ID = 'zawcode';
const DEFAULT_KEYBOARD_GENERATION = 0;

/**
 * API-20 Data Proxy is a public system IPC store. Declaring this URI in
 * module.json5 makes the system, rather than either application process, the
 * single authority for this small shared-config record.
 */
export const KEYBOARD_SELECTION_PROXY_URI =
  'datashareproxy://com.szl.myankey/keymagic3/keyboard-selection';

const PROXY_CONFIG: dataShare.DataProxyConfig = {
  type: dataShare.DataProxyType.SHARED_CONFIG,
};

function defaultSelection(): KeyboardSelection {
  return {
    activeKeyboardId: DEFAULT_KEYBOARD_ID,
    keyboardGeneration: DEFAULT_KEYBOARD_GENERATION,
  };
}

function encodeSelection(selection: KeyboardSelection): string {
  return `${selection.activeKeyboardId}\n${selection.keyboardGeneration}`;
}

function decodeSelection(value: ValueType | undefined): KeyboardSelection | undefined {
  if (typeof value !== 'string') {
    return undefined;
  }
  const separator = value.lastIndexOf('\n');
  if (separator <= 0) {
    return undefined;
  }
  const activeKeyboardId = value.substring(0, separator);
  const rawGeneration = Number(value.substring(separator + 1));
  if (activeKeyboardId.length === 0 || !Number.isFinite(rawGeneration) || rawGeneration < 0) {
    return undefined;
  }
  return {
    activeKeyboardId,
    keyboardGeneration: Math.floor(rawGeneration),
  };
}

/**
 * The only external keyboard-selection API. It deliberately contains no
 * Preferences access: every caller reads and writes the one declared Data
 * Proxy URI through IPC. The observer keeps each process's local snapshot in
 * sync without making a physical-key callback asynchronous.
 */
export class KeyboardSelectionService {
  private readonly keyboardManager: KeyboardManager = new KeyboardManager();
  private dataProxy: dataShare.DataProxyHandle | undefined;
  private dataProxyPromise: Promise<dataShare.DataProxyHandle> | undefined;
  private observing: boolean = false;
  private currentSelection: KeyboardSelection | undefined;
  private observers: KeyboardSelectionObserver[] = [];

  async getSelection(): Promise<KeyboardSelection> {
    const handle = await this.getDataProxy();
    const results = await handle.get([KEYBOARD_SELECTION_PROXY_URI], PROXY_CONFIG);
    if (results.length !== 1) {
      throw new Error(`Keyboard selection IPC returned ${results.length} records.`);
    }
    const result = results[0];
    if (result.result === dataShare.DataProxyErrorCode.SUCCESS) {
      const selection = decodeSelection(result.value);
      if (selection === undefined) {
        throw new Error('Keyboard selection IPC returned an invalid selection record.');
      }
      this.keyboardManager.getKeyboardById(selection.activeKeyboardId);
      this.publishLocalSelection(selection);
      return selection;
    }
    if (result.result === dataShare.DataProxyErrorCode.URI_NOT_EXIST) {
      const initial = defaultSelection();
      await this.writeSelection(initial);
      return initial;
    }
    throw new Error(`Keyboard selection IPC get failed with result=${result.result}.`);
  }

  async setSelection(keyboardId: string): Promise<KeyboardSelection> {
    this.keyboardManager.getKeyboardById(keyboardId);
    const current = await this.getSelection();
    const next: KeyboardSelection = {
      activeKeyboardId: keyboardId,
      keyboardGeneration: current.keyboardGeneration + 1,
    };
    await this.writeSelection(next);
    return this.getSelection();
  }

  async reloadCurrent(): Promise<KeyboardSelection> {
    const current = await this.getSelection();
    const next: KeyboardSelection = {
      activeKeyboardId: current.activeKeyboardId,
      keyboardGeneration: current.keyboardGeneration + 1,
    };
    await this.writeSelection(next);
    return this.getSelection();
  }

  /** Returns the last system-authoritative record delivered to this process. */
  getCachedSelection(): KeyboardSelection | undefined {
    return this.currentSelection;
  }

  /**
   * Starts observation once per process. The callback is observation only;
   * callers still use getSelection/setSelection/reloadCurrent for authority.
   */
  async startObserving(observer: KeyboardSelectionObserver): Promise<KeyboardSelection> {
    this.observers.push(observer);
    const handle = await this.getDataProxy();
    if (!this.observing) {
      const registration = handle.on('dataChange', [KEYBOARD_SELECTION_PROXY_URI], PROXY_CONFIG,
        (_error, changes) => {
          for (let index = 0; index < changes.length; index++) {
            if (changes[index].uri === KEYBOARD_SELECTION_PROXY_URI) {
              void this.refreshFromChangeNotification();
              break;
            }
          }
        });
      if (registration.length !== 1 || registration[0].result !== dataShare.DataProxyErrorCode.SUCCESS) {
        throw new Error('Unable to observe keyboard selection IPC changes.');
      }
      this.observing = true;
    }
    const selection = await this.getSelection();
    observer(selection);
    return selection;
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

  private async writeSelection(selection: KeyboardSelection): Promise<void> {
    const handle = await this.getDataProxy();
    const results = await handle.publish([{
      uri: KEYBOARD_SELECTION_PROXY_URI,
      value: encodeSelection(selection),
    }], PROXY_CONFIG);
    if (results.length !== 1 || results[0].result !== dataShare.DataProxyErrorCode.SUCCESS) {
      const result = results.length === 0 ? '<none>' : `${results[0].result}`;
      throw new Error(`Keyboard selection IPC publish failed with result=${result}.`);
    }
    this.publishLocalSelection(selection);
  }

  private async refreshFromChangeNotification(): Promise<void> {
    try {
      await this.getSelection();
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s',
        `KEYBOARD IPC CHANGE refresh failed: ${JSON.stringify(error)}`);
    }
  }

  private publishLocalSelection(selection: KeyboardSelection): void {
    const changed = this.currentSelection === undefined ||
      this.currentSelection.activeKeyboardId !== selection.activeKeyboardId ||
      this.currentSelection.keyboardGeneration !== selection.keyboardGeneration;
    this.currentSelection = selection;
    if (!changed) {
      return;
    }
    for (let index = 0; index < this.observers.length; index++) {
      this.observers[index](selection);
    }
  }
}

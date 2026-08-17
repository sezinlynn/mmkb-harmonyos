import cryptoFramework from '@ohos.security.cryptoFramework';

import { bundledKeyboardsWithActive, KeyboardInfo } from './KeyboardInfo';

export interface KeyboardResource {
  keyboard: KeyboardInfo;
  data: Uint8Array;
  sha256: string;
}

/**
 * Owns the immutable bundled keyboard catalog and ID-to-resource mapping.
 * KeyboardSelectionService, rather than HarmonyOS subtype state, owns the
 * active keyboard selection.
 */
export class KeyboardManager {
  // MyanKey's layout-cycle order. Keep this list here so configurator ordering
  // and IME cycling have one source of truth.
  private readonly keyboardCycleIds: string[] = [
    'zawcode',
    '',
    '-mm',
  ];

  getKeyboards(activeKeyboardId?: string): KeyboardInfo[] {
    const unordered = bundledKeyboardsWithActive(activeKeyboardId);
    const ordered: KeyboardInfo[] = [];
    for (let cycleIndex = 0; cycleIndex < this.keyboardCycleIds.length; cycleIndex++) {
      const cycleId = this.keyboardCycleIds[cycleIndex];
      for (let keyboardIndex = 0; keyboardIndex < unordered.length; keyboardIndex++) {
        if (unordered[keyboardIndex].id === cycleId) {
          ordered.push(unordered[keyboardIndex]);
          break;
        }
      }
    }
    // Preserve any future bundled/imported layout that is not part of the
    // cycle instead of silently hiding it from the UI.
    for (let keyboardIndex = 0; keyboardIndex < unordered.length; keyboardIndex++) {
      let alreadyOrdered = false;
      for (let orderedIndex = 0; orderedIndex < ordered.length; orderedIndex++) {
        if (ordered[orderedIndex].id === unordered[keyboardIndex].id) {
          alreadyOrdered = true;
          break;
        }
      }
      if (!alreadyOrdered) {
        ordered.push(unordered[keyboardIndex]);
      }
    }
    return ordered;
  }

  getNextKeyboardId(activeKeyboardId: string): string {
    let activeIndex = -1;
    for (let index = 0; index < this.keyboardCycleIds.length; index++) {
      if (this.keyboardCycleIds[index] === activeKeyboardId) {
        activeIndex = index;
        break;
      }
    }
    const nextIndex = activeIndex < 0 ? 0 : (activeIndex + 1) % this.keyboardCycleIds.length;
    return this.keyboardCycleIds[nextIndex];
  }

  getKeyboardById(id: string): KeyboardInfo {
    const keyboards = this.getKeyboards();
    for (let index = 0; index < keyboards.length; index++) {
      if (keyboards[index].id === id) {
        return keyboards[index];
      }
    }
    throw new Error(`Unknown bundled KeyMagic keyboard: ${id}.`);
  }

  /** Reads the exact selected KM2 bytes before the controller loads the engine. */
  async readBundledKeyboardResource(context: Context, keyboard: KeyboardInfo): Promise<KeyboardResource> {
    try {
      const data = await context.resourceManager.getRawFileContent(keyboard.resourcePath);
      return {
        keyboard,
        data,
        sha256: this.sha256(data),
      };
    } catch (error) {
      throw new Error(`Unable to read bundled keyboard ${keyboard.resourcePath}: ${JSON.stringify(error)}`);
    }
  }

  /** Synchronous API-20 rawfile read used before the current physical key. */
  readBundledKeyboardResourceSync(context: Context, keyboard: KeyboardInfo): KeyboardResource {
    try {
      const data = context.resourceManager.getRawFileContentSync(keyboard.resourcePath);
      return {
        keyboard,
        data,
        sha256: this.sha256(data),
      };
    } catch (error) {
      throw new Error(`Unable to read bundled keyboard ${keyboard.resourcePath}: ${JSON.stringify(error)}`);
    }
  }

  private sha256(data: Uint8Array): string {
    const md = cryptoFramework.createMd('SHA256');
    md.updateSync({ data });
    const digest = md.digestSync().data;
    let hex = '';
    for (let index = 0; index < digest.length; index++) {
      const value = digest[index].toString(16);
      hex += value.length === 1 ? `0${value}` : value;
    }
    return hex.toUpperCase();
  }
}

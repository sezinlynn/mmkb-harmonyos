import nativeKeyMagic from 'libkeymagic3.so';
import { hilog } from '@kit.PerformanceAnalysisKit';

const KEYMAGIC_PROCESS_LOG_DOMAIN = 0x0000;
const KEYMAGIC_PROCESS_LOG_TAG = 'KeyMagicProcessArgs';

export enum KeyMagicActionType {
  None = 0,
  Insert = 1,
  BackspaceDelete = 2,
  BackspaceDeleteAndInsert = 3,
}

export interface KeyMagicKeyInput {
  keyCode: number;
  character?: string;
  shift?: boolean;
  ctrl?: boolean;
  alt?: boolean;
  capsLock?: boolean;
}

export interface KeyMagicProcessResult {
  actionType: KeyMagicActionType;
  text: string;
  deleteCount: number;
  composingText: string;
  isProcessed: boolean;
  /** Native engine identity that processed this exact input. */
  engineId: number;
  /** Harmony subtype ID associated with that native engine at successful load. */
  runtimeKeyboardId: string;
}

interface KeyMagicNativeModule {
  createEngine(): Object;
  destroyEngine(engine: Object): void;
  loadKeyboard(engine: Object, keyboardData: Uint8Array, subtypeId?: string): number;
  processKey(
    engine: Object,
    keyCode: number,
    character: string,
    shift: boolean,
    ctrl: boolean,
    alt: boolean,
    capsLock: boolean
  ): KeyMagicProcessResult | number;
  resetEngine(engine: Object): number;
  getComposition(engine: Object): string;
  setComposition(engine: Object, composition: string): number;
}

const nativeModule = nativeKeyMagic as KeyMagicNativeModule;

function requireSuccess(operation: string, status: number): void {
  if (status !== 0) {
    throw new Error(`${operation} failed with KeyMagicResult ${status}.`);
  }
}

function characterByteForDiagnostic(character: string): number {
  if (character.length === 0) {
    return 0;
  }
  const byte = character.charCodeAt(0);
  return byte <= 0x7F ? byte : -1;
}

/**
 * Small ownership-safe ArkTS wrapper over the existing Rust C FFI exposed by
 * libkeymagic3.so. It intentionally exposes only Milestone 1 engine methods.
 */
export class KeyMagicNative {
  private engine: Object | undefined;

  createEngine(): void {
    if (this.engine !== undefined) {
      throw new Error('A KeyMagic engine is already active. Destroy it before creating another one.');
    }
    this.engine = nativeModule.createEngine();
  }

  destroyEngine(): void {
    if (this.engine === undefined) {
      return;
    }
    nativeModule.destroyEngine(this.engine);
    this.engine = undefined;
  }

  async loadBundledKeyboard(context: Context, rawFilePath: string): Promise<void> {
    let keyboardData: Uint8Array;
    try {
      keyboardData = await context.resourceManager.getRawFileContent(rawFilePath);
    } catch (error) {
      throw new Error(`Unable to read bundled keyboard ${rawFilePath}: ${JSON.stringify(error)}`);
    }
      this.loadKeyboardData(keyboardData, rawFilePath);
  }

  /** Loads already-read KM2 bytes through the unchanged NAPI/Rust bridge. */
  loadKeyboardData(keyboardData: Uint8Array, subtypeId: string = '<unspecified>'): void {
    requireSuccess('Loading keyboard', nativeModule.loadKeyboard(this.requireEngine(), keyboardData, subtypeId));
  }

  processKey(input: KeyMagicKeyInput, source: string = 'ArkTS'): KeyMagicProcessResult {
    const engine = this.requireEngine();
    const character = input.character === undefined ? '' : input.character;
    const characterByte = characterByteForDiagnostic(character);
    hilog.info(
      KEYMAGIC_PROCESS_LOG_DOMAIN,
      KEYMAGIC_PROCESS_LOG_TAG,
      '%{public}s',
      `before native processKey source=${source} key_code=${input.keyCode} character=${character.length === 0 ? '<empty>' : character} character_byte=${characterByte} shift=${input.shift === true} ctrl=${input.ctrl === true} alt=${input.alt === true} caps_lock=${input.capsLock === true}`,
    );
    const result = nativeModule.processKey(
      engine,
      input.keyCode,
      character,
      input.shift === true,
      input.ctrl === true,
      input.alt === true,
      input.capsLock === true,
    );

    if (typeof result === 'number') {
      requireSuccess('Processing key', result);
      throw new Error('KeyMagic processKey returned an unexpected success status.');
    }

    hilog.info(
      KEYMAGIC_PROCESS_LOG_DOMAIN,
      KEYMAGIC_PROCESS_LOG_TAG,
      '%{public}s',
      `native processKey result engineId=${result.engineId} runtimeKeyboardId=${result.runtimeKeyboardId}`,
    );

    return result;
  }

  resetEngine(): void {
    requireSuccess('Resetting engine', nativeModule.resetEngine(this.requireEngine()));
  }

  /** Existing C FFI composition accessor, needed only for direct-mode editor synchronization. */
  getComposition(): string {
    return nativeModule.getComposition(this.requireEngine());
  }

  /** Existing C FFI composition mutator, needed only for direct-mode editor synchronization. */
  setComposition(composition: string): void {
    requireSuccess('Setting engine composition', nativeModule.setComposition(this.requireEngine(), composition));
  }

  isCreated(): boolean {
    return this.engine !== undefined;
  }

  private requireEngine(): Object {
    if (this.engine === undefined) {
      throw new Error('Create a KeyMagic engine before using it.');
    }
    return this.engine;
  }
}

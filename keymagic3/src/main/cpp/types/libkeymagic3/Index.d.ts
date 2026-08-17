export interface ProcessKeyOutput {
  actionType: number;
  text: string;
  deleteCount: number;
  composingText: string;
  isProcessed: boolean;
}

export const createEngine: () => Object;
export const destroyEngine: (engine: Object) => void;
export const loadKeyboard: (engine: Object, keyboardData: Uint8Array) => number;
export const processKey: (
  engine: Object,
  keyCode: number,
  character: string,
  shift: boolean,
  ctrl: boolean,
  alt: boolean,
  capsLock: boolean
) => ProcessKeyOutput | number;
export const resetEngine: (engine: Object) => number;
export const getComposition: (engine: Object) => string;
export const setComposition: (engine: Object, composition: string) => number;

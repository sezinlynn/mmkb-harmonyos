const NativeMock = {
  createEngine: (): Object => {
    return {};
  },
  destroyEngine: (_engine: Object): void => {
  },
  loadKeyboard: (_engine: Object, _keyboardData: Uint8Array): number => {
    return 0;
  },
  processKey: (
    _engine: Object,
    _keyCode: number,
    _character: string,
    _shift: boolean,
    _ctrl: boolean,
    _alt: boolean,
    _capsLock: boolean
  ): Object => {
    return {
      actionType: 0,
      text: '',
      deleteCount: 0,
      composingText: '',
      isProcessed: false,
    };
  },
  resetEngine: (_engine: Object): number => {
    return 0;
  },
  getComposition: (_engine: Object): string => {
    return '';
  },
  setComposition: (_engine: Object, _composition: string): number => {
    return 0;
  },
};

export default NativeMock;

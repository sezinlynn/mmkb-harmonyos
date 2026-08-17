import { KeyMagicActionType, KeyMagicKeyInput } from './KeyMagicNative';
import { KeyMagicVirtualKey } from './KeyMagicKeyMap';

export interface ExpectedEngineOutput {
  actionType: KeyMagicActionType;
  text: string;
  deleteCount: number;
  composingText: string;
  isProcessed: boolean;
}

export interface KeyMagicValidationStep {
  name: string;
  input: KeyMagicKeyInput;
  expected: ExpectedEngineOutput;
}

export interface KeyMagicValidationVector {
  name: string;
  steps: KeyMagicValidationStep[];
}

const vowelE: KeyMagicValidationStep = {
  name: 'a (vowel e)',
  input: { keyCode: KeyMagicVirtualKey.KeyA, character: 'a' },
  expected: {
    actionType: KeyMagicActionType.Insert,
    text: '\u200C\u1031',
    deleteCount: 0,
    composingText: '\u200C\u1031',
    isProcessed: true,
  },
};

/**
 * Expected values are traced from keyboards/bundled/.km2 through the
 * existing C FFI. They deliberately do not use the KMS fixture, whose icon
 * path is absent from this checkout.
 */
export const _VALIDATION_VECTORS: KeyMagicValidationVector[] = [
  {
    name: 'Single consonant: u -> က',
    steps: [{
      name: 'u',
      input: { keyCode: KeyMagicVirtualKey.KeyU, character: 'u' },
      expected: {
        actionType: KeyMagicActionType.Insert,
        text: '\u1000',
        deleteCount: 0,
        composingText: '\u1000',
        isProcessed: true,
      },
    }],
  },
  {
    name: 'Vowel-e reorder: a, u -> ကေ',
    steps: [
      vowelE,
      {
        name: 'u (reorders vowel e after က)',
        input: { keyCode: KeyMagicVirtualKey.KeyU, character: 'u' },
        expected: {
          actionType: KeyMagicActionType.BackspaceDeleteAndInsert,
          text: '\u1000\u1031',
          deleteCount: 2,
          composingText: '\u1000\u1031',
          isProcessed: true,
        },
      },
    ],
  },
  {
    name: 'Stack reorder: a, u, F, u -> က္ကေ',
    steps: [
      vowelE,
      {
        name: 'u',
        input: { keyCode: KeyMagicVirtualKey.KeyU, character: 'u' },
        expected: {
          actionType: KeyMagicActionType.BackspaceDeleteAndInsert,
          text: '\u1000\u1031',
          deleteCount: 2,
          composingText: '\u1000\u1031',
          isProcessed: true,
        },
      },
      {
        name: 'F (stack marker)',
        input: { keyCode: KeyMagicVirtualKey.KeyF, character: 'F' },
        expected: {
          actionType: KeyMagicActionType.Insert,
          text: '\u1039',
          deleteCount: 0,
          composingText: '\u1000\u1031\u1039',
          isProcessed: true,
        },
      },
      {
        name: 'u (reorders stack)',
        input: { keyCode: KeyMagicVirtualKey.KeyU, character: 'u' },
        expected: {
          actionType: KeyMagicActionType.BackspaceDeleteAndInsert,
          text: '\u1039\u1000\u1031',
          deleteCount: 2,
          composingText: '\u1000\u1039\u1000\u1031',
          isProcessed: true,
        },
      },
    ],
  },
  {
    name: 'Medial reorder: a, s -> ‌ျေ',
    steps: [
      vowelE,
      {
        name: 's (ya-yit medial)',
        input: { keyCode: KeyMagicVirtualKey.KeyS, character: 's' },
        expected: {
          actionType: KeyMagicActionType.BackspaceDeleteAndInsert,
          text: '\u103B\u1031',
          deleteCount: 1,
          composingText: '\u200C\u103B\u1031',
          isProcessed: true,
        },
      },
    ],
  },
  {
    name: 'Autocorrect replacement: p, s -> ဈ',
    steps: [
      {
        name: 'p',
        input: { keyCode: KeyMagicVirtualKey.KeyP, character: 'p' },
        expected: {
          actionType: KeyMagicActionType.Insert,
          text: '\u1005',
          deleteCount: 0,
          composingText: '\u1005',
          isProcessed: true,
        },
      },
      {
        name: 's (replaces စျ)',
        input: { keyCode: KeyMagicVirtualKey.KeyS, character: 's' },
        expected: {
          actionType: KeyMagicActionType.BackspaceDeleteAndInsert,
          text: '\u1008',
          deleteCount: 1,
          composingText: '\u1008',
          isProcessed: true,
        },
      },
    ],
  },
  {
    name: 'Filler removal: a, O -> ဿေ',
    steps: [
      vowelE,
      {
        name: 'O',
        input: { keyCode: KeyMagicVirtualKey.KeyO, character: 'O' },
        expected: {
          actionType: KeyMagicActionType.BackspaceDeleteAndInsert,
          text: '\u103F\u1031',
          deleteCount: 2,
          composingText: '\u103F\u1031',
          isProcessed: true,
        },
      },
    ],
  },
  {
    name: 'Shift modifier: Shift+4 -> ကျပ်',
    steps: [{
      name: 'Shift+4',
      input: { keyCode: KeyMagicVirtualKey.Key4, character: '4', shift: true },
      expected: {
        actionType: KeyMagicActionType.Insert,
        text: '\u1000\u103B\u1015\u103A',
        deleteCount: 0,
        composingText: '\u1000\u103B\u1015\u103A',
        isProcessed: true,
      },
    }],
  },
  {
    name: 'Punctuation: / -> ။, Shift+/ -> ၊',
    steps: [
      {
        name: '/',
        input: { keyCode: KeyMagicVirtualKey.Oem2, character: '/' },
        expected: {
          actionType: KeyMagicActionType.Insert,
          text: '\u104B',
          deleteCount: 0,
          composingText: '\u104B',
          isProcessed: true,
        },
      },
      {
        name: 'Shift+/',
        input: { keyCode: KeyMagicVirtualKey.Oem2, character: '?', shift: true },
        expected: {
          actionType: KeyMagicActionType.Insert,
          text: '\u104A',
          deleteCount: 0,
          composingText: '\u104B\u104A',
          isProcessed: true,
        },
      },
    ],
  },
  {
    name: 'Smart backspace: a, u, Back -> ‌ေ',
    steps: [
      vowelE,
      {
        name: 'u',
        input: { keyCode: KeyMagicVirtualKey.KeyU, character: 'u' },
        expected: {
          actionType: KeyMagicActionType.BackspaceDeleteAndInsert,
          text: '\u1000\u1031',
          deleteCount: 2,
          composingText: '\u1000\u1031',
          isProcessed: true,
        },
      },
      {
        name: 'Backspace (restores prior composition)',
        input: { keyCode: KeyMagicVirtualKey.Back },
        expected: {
          actionType: KeyMagicActionType.BackspaceDeleteAndInsert,
          text: '\u200C\u1031',
          deleteCount: 2,
          composingText: '\u200C\u1031',
          isProcessed: true,
        },
      },
    ],
  },
];

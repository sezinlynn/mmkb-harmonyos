/**
 * UI-neutral description of one keyboard available to the HarmonyOS adapter.
 * The bundled manifest is populated from the embedded KM2 @NAME and
 * @DESCRIPTION fields; it does not change or reinterpret KM2 rules.
 */
export interface KeyboardInfo {
  /** Stable MyanKey keyboard identifier selected through the IPC service. */
  id: string;
  name: string;
  locale: string;
  description: string;
  author?: string;
  resourcePath: string;
  bundled: boolean;
  active: boolean;
}

export interface BundledKeyboardDefinition {
  id: string;
  name: string;
  locale: string;
  description: string;
  author?: string;
  resourcePath: string;
}

// Metadata source: the corresponding immutable KM2 file in
// keyboards/bundled/, inspected through keymagic-core's Km2Loader.
export const BUNDLED_KEYBOARD_DEFINITIONS: BundledKeyboardDefinition[] = [
  {
    id: 'zawcode',
    name: 'ဇော်ကုဒ်',
    locale: 'my-MM',
    description: 'A Unicode Keyboard Layout that can be type the same sequence just like normal ZawGyi layout but the output is Unicode.',
    resourcePath: 'keyboards/ZawCode.km2',
  },
  {
    id: 'mm-unicode',
    name: 'MM Unicode',
    locale: 'my-MM',
    description: 'Myanmar Unicode smart input layout for mmKB.',
    resourcePath: 'keyboards/MM Unicode.km2',
  },
];

export function bundledKeyboardsWithActive(activeKeyboardId: string | undefined): KeyboardInfo[] {
  const keyboards: KeyboardInfo[] = [];
  for (let index = 0; index < BUNDLED_KEYBOARD_DEFINITIONS.length; index++) {
    const keyboard = BUNDLED_KEYBOARD_DEFINITIONS[index];
    keyboards.push({
      id: keyboard.id,
      name: keyboard.name,
      locale: keyboard.locale,
      description: keyboard.description,
      author: keyboard.author,
      resourcePath: keyboard.resourcePath,
      bundled: true,
      active: keyboard.id === activeKeyboardId,
    });
  }
  return keyboards;
}

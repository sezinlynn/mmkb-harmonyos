import { preferences } from '@kit.ArkData';

/** Small local-only MRU store for the keyboard panel's Recent emoji tab. */
const EMOJI_RECENT_STORE = 'myankey_emoji_preferences';
const EMOJI_RECENT_KEY = 'recentEmojis';
export const EMOJI_RECENT_LIMIT = 40;

export class EmojiRecentSettings {
  static read(context: Context): string[] {
    const stored = EmojiRecentSettings.open(context).getSync(EMOJI_RECENT_KEY, '');
    if (typeof stored !== 'string' || stored.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(stored) as string[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const values: string[] = [];
      parsed.forEach((emoji: string): void => {
        if (typeof emoji === 'string' && emoji.length > 0 && values.indexOf(emoji) < 0 &&
          values.length < EMOJI_RECENT_LIMIT) {
          values.push(emoji);
        }
      });
      return values;
    } catch (_error) {
      return [];
    }
  }

  static write(context: Context, emojis: string[]): void {
    const unique: string[] = [];
    emojis.forEach((emoji: string): void => {
      if (emoji.length > 0 && unique.indexOf(emoji) < 0 && unique.length < EMOJI_RECENT_LIMIT) {
        unique.push(emoji);
      }
    });
    const store = EmojiRecentSettings.open(context);
    store.putSync(EMOJI_RECENT_KEY, JSON.stringify(unique));
    store.flushSync();
  }

  private static open(context: Context): preferences.Preferences {
    return preferences.getPreferencesSync(context.getApplicationContext(), { name: EMOJI_RECENT_STORE });
  }
}

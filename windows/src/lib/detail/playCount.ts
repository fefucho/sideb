import type { AppLanguage } from '../i18n/format';

/** Translates one catalog key with its arguments (the app's `text` adapter). */
export type PlayCountTranslate = (key: string, args: readonly string[], language: AppLanguage) => string;

const abbreviated = /^(\d[\d.,]*)\s*([KMB])?$/i;
const suffixKeys: Record<string, string> = { K: 'detail.track.plays.thousand', M: 'detail.track.plays.million', B: 'detail.track.plays.billion' };

/**
 * Presents the provider's abbreviated play count ("53M", "1.2B", "1,234") with the app language's separators and
 * suffixes ("53 M", "1,2 mil M" in Spanish; "1.2M" in English). Same contract as Apple's `PlayCountFormatter`:
 * empty or unrecognised values yield null, never raw text.
 */
export function formatPlayCount(raw: string | null | undefined, language: AppLanguage, translate: PlayCountTranslate): string | null {
  const trimmed = raw?.trim();
  if (!trimmed) return null;
  const match = abbreviated.exec(trimmed);
  if (!match) return null;
  const number = match[1];
  const suffix = match[2]?.toUpperCase();
  if (suffix) {
    // The provider's pinned English locale always uses a dot as the decimal separator ("1.2").
    const value = Number(number);
    if (!Number.isFinite(value)) return null;
    const shown = new Intl.NumberFormat(language, { maximumFractionDigits: 1, minimumFractionDigits: 0 }).format(value);
    return translate(suffixKeys[suffix], [shown], language);
  }
  const digits = number.replace(/\D/g, '');
  if (!digits) return null;
  return new Intl.NumberFormat(language, { maximumFractionDigits: 0, useGrouping: 'always' }).format(Number(digits));
}

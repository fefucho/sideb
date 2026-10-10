import { derived, writable, get } from 'svelte/store';
import catalog from './catalog.json';
import windows from './windows.json';
import { lookup, normalizeLanguage, preferenceKey, type AppLanguage, type Arguments, type AppMessage } from './format';
export { message, preferenceKey } from './format';
export type { AppLanguage, AppMessage } from './format';
function initial(): AppLanguage { try { return normalizeLanguage(globalThis.localStorage?.getItem(preferenceKey)); } catch { return 'es'; } }
const current = writable<AppLanguage>(initial());
export const language = { subscribe: current.subscribe };
export function setLanguage(value: AppLanguage): void {
  const normalized = normalizeLanguage(value);
  try { globalThis.localStorage?.setItem(preferenceKey, normalized); } catch { /* Private/disabled storage still permits a session preference. */ }
  current.set(normalized);
}
const resources = { ...catalog, ...windows };
const ownTextKeys = new Map(Object.entries(resources).flatMap(([key, value]) => typeof value.es === 'string' && typeof value.en === 'string' ? [[value.es, key] as const, [value.en, key] as const] : []));
const ownPatterns = Object.entries(resources).flatMap(([key, value]) => [value.es, value.en].flatMap(template => {
  if (typeof template !== 'string' || !template.includes('%@') || template.startsWith('%@') || template.replaceAll('%@', '').length < 12) return [];
  const segments = template.split('%@').map(segment => segment.replaceAll('%%', '%').replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  return [{ key, pattern: new RegExp('^' + segments.join('(.*?)') + '$'), specificity: template.replaceAll('%@', '').length }];
})).sort((a, b) => b.specificity - a.specificity);
export const text = (key: string, args: Arguments = [], selected: AppLanguage = get(language)): string => lookup(resources, key, selected, args);
export const t = derived(language, selected => (key: string, args: Arguments = []) => text(key, args, selected));
export const count = (key: string, amount: number, selected: AppLanguage = get(language)): string => lookup(resources, key, selected, [], amount);
/** Adapter for legacy app-owned labels/errors only. Never run over user or provider metadata. */
export const translateOwnText = (value: string, selected: AppLanguage = get(language)): string => {
  const key = ownTextKeys.get(value); if (key) return text(key, [], selected);
  for (const { key, pattern } of ownPatterns) {
    const match = pattern.exec(value); if (match) return text(key, match.slice(1), selected);
  }
  return value;
};
export const resolveMessage = (value: AppMessage | string | null, selected: AppLanguage = get(language)): string => typeof value === 'string' ? translateOwnText(value, selected) : value ? text(value.key, value.args, selected) : '';

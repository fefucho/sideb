export type AppLanguage = 'es' | 'en';
export type Arguments = readonly (string | number)[];
export interface AppMessage { key: string; args: Arguments }
export type Catalog = Record<string, { es: string | { one: string; other: string }; en: string | { one: string; other: string } }>;
export const preferenceKey = 'sideb.ui.language.v1';
export const normalizeLanguage = (value: unknown): AppLanguage => value === 'en' ? 'en' : 'es';
export function format(template: string, args: Arguments): string {
  let index = 0;
  return template.replace(/%(?:(\d+)\$)?(@|lld|%)/g, (_, position, kind) => kind === '%' ? '%' : String(args[position ? Number(position) - 1 : index++] ?? ''));
}
export function lookup(catalog: Catalog, key: string, language: AppLanguage, args: Arguments = [], count?: number): string {
  const entry = catalog[key];
  const value = entry?.[language] ?? entry?.es ?? 'No disponible';
  const template = typeof value === 'string' ? value : value[new Intl.PluralRules(language).select(count ?? Number(args[0] ?? 0)) === 'one' ? 'one' : 'other'];
  return format(template, count === undefined ? args : [count, ...args]);
}
export const message = (key: string, args: Arguments = []): AppMessage => ({ key, args: [...args] });

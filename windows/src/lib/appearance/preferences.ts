import { writable } from 'svelte/store';

export type HomeBackground = 'artwork' | 'solid';
export type SidebarLayout = 'list' | 'grid';
export interface AppearancePreferences { version: 1; homeBackground: HomeBackground; sidebarLayout: SidebarLayout }
export const appearanceKey = 'sideb.appearance.v1';
export const appearanceDefaults = (): AppearancePreferences => ({ version: 1, homeBackground: 'artwork', sidebarLayout: 'list' });

export function decodeAppearance(value: unknown): AppearancePreferences {
  if (!value || typeof value !== 'object' || (value as { version?: unknown }).version !== 1) return appearanceDefaults();
  const raw = value as Record<string, unknown>;
  return { version: 1, homeBackground: raw.homeBackground === 'solid' ? 'solid' : 'artwork', sidebarLayout: raw.sidebarLayout === 'grid' ? 'grid' : 'list' };
}

type PreferenceStorage = Pick<Storage, 'getItem' | 'setItem'>;
function browserStorage(): PreferenceStorage | undefined {
  try { return globalThis.localStorage; } catch { return undefined; }
}

/** Installation appearance stays independent of account-specific recommendations and library data. */
export function createAppearancePreferences(storage = browserStorage()) {
  let current = appearanceDefaults();
  try { current = decodeAppearance(JSON.parse(storage?.getItem(appearanceKey) ?? 'null')); } catch { /* Use defaults for unavailable or malformed storage. */ }
  const store = writable(current);
  function update(patch: Partial<Omit<AppearancePreferences, 'version'>>) {
    current = decodeAppearance({ ...current, ...patch });
    try { storage?.setItem(appearanceKey, JSON.stringify(current)); } catch { /* Keep the session usable when storage is blocked/full. */ }
    store.set(current);
  }
  return {
    subscribe: store.subscribe,
    setHomeBackground: (homeBackground: HomeBackground) => update({ homeBackground }),
    setSidebarLayout: (sidebarLayout: SidebarLayout) => update({ sidebarLayout }),
    toggleSidebarLayout: () => update({ sidebarLayout: current.sidebarLayout === 'list' ? 'grid' : 'list' }),
  };
}

export const appearance = createAppearancePreferences();

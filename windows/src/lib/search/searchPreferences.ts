import { writable } from 'svelte/store';

export const showVideosKey = 'sideb.search.showVideos.v1';
/** Only an explicit boolean `false` (or its serialized form) hides videos; any other value keeps the default. */
export function resolveShowVideos(value: unknown): boolean {
  return !(value === false || value === 'false');
}
function browserStorage(): Pick<Storage, 'getItem' | 'setItem'> | undefined {
  try { return globalThis.localStorage; } catch { return undefined; }
}
/** Installation preference for video cards/payloads in search results and suggestions (default: shown). */
export function createSearchPreferences(storage = browserStorage()) {
  let current = true;
  try { current = resolveShowVideos(storage?.getItem(showVideosKey)); } catch { /* Keep default. */ }
  const store = writable(current);
  return {
    subscribe: store.subscribe,
    currentShowVideos: () => current,
    setShowVideos(value: unknown) {
      current = resolveShowVideos(value);
      try { storage?.setItem(showVideosKey, String(current)); } catch { /* Session choice remains usable. */ }
      store.set(current);
    },
  };
}
export const searchPreferences = createSearchPreferences();

export const categoryViewKey = 'sideb.search.categoryView.v1';
/** Results grouped by category (Apple-Music style, PLAN-027 W4). Default on; only an explicit `false` turns it off,
 * which shows the provider's own mixed list again. Same storage rules as the videos preference. */
export function createCategoryViewPreference(storage = browserStorage()) {
  let current = true;
  try { current = resolveShowVideos(storage?.getItem(categoryViewKey)); } catch { /* Keep default. */ }
  const store = writable(current);
  return {
    subscribe: store.subscribe,
    current: () => current,
    set(value: unknown) {
      current = resolveShowVideos(value);
      try { storage?.setItem(categoryViewKey, String(current)); } catch { /* Session choice remains usable. */ }
      store.set(current);
    },
  };
}
export const categoryViewPreference = createCategoryViewPreference();

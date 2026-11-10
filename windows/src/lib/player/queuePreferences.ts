import { writable } from 'svelte/store';

export type RecommendationSelection = 'advance' | 'play-only';
export const queueSelectionKey = 'sideb.queue.recommendationSelection.v1';
export function resolveQueueSelection(value: unknown): RecommendationSelection {
  return value === 'play-only' ? 'play-only' : 'advance';
}
function browserStorage(): Pick<Storage, 'getItem' | 'setItem'> | undefined {
  try { return globalThis.localStorage; } catch { return undefined; }
}
/** Installation preference, independent of account-specific queue/session data. */
export function createQueuePreferences(storage = browserStorage()) {
  let current: RecommendationSelection = 'advance';
  try { current = resolveQueueSelection(storage?.getItem(queueSelectionKey)); } catch { /* Keep default. */ }
  const store = writable(current);
  return {
    subscribe: store.subscribe,
    currentSelection: () => current,
    setSelection(value: unknown) {
      current = resolveQueueSelection(value);
      try { storage?.setItem(queueSelectionKey, current); } catch { /* Session choice remains usable. */ }
      store.set(current);
    },
  };
}
export const queuePreferences = createQueuePreferences();

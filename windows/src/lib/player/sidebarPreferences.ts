import { derived, writable } from 'svelte/store';

/** Mirrors macOS `SidebarBottomContent`: what the side player shows under its transport controls. */
export type SidebarBottomContent = 'queue' | 'lyrics';
export const sidebarBottomContents: readonly SidebarBottomContent[] = ['queue', 'lyrics'];
/** Installation preference (not account data). The stored string matches the macOS raw values. */
export const sidebarLyricsPreviewKey = 'sideb.sidebar.lyricsPreview.v1';

/** Unknown, missing or malformed values fall back to the macOS default: the upcoming queue. */
export function resolveSidebarBottomContent(value: unknown): SidebarBottomContent {
  return value === 'lyrics' ? 'lyrics' : 'queue';
}
function browserStorage(): Pick<Storage, 'getItem' | 'setItem'> | undefined {
  try { return globalThis.localStorage; } catch { return undefined; }
}
export function createSidebarPreferences(storage = browserStorage()) {
  let current: SidebarBottomContent = 'queue';
  try { current = resolveSidebarBottomContent(storage?.getItem(sidebarLyricsPreviewKey)); } catch { /* Keep the default. */ }
  const store = writable<SidebarBottomContent>(current);
  function setBottomContent(value: unknown) {
    current = resolveSidebarBottomContent(value);
    try { storage?.setItem(sidebarLyricsPreviewKey, current); } catch { /* The session choice remains usable. */ }
    store.set(current);
  }
  return {
    subscribe: store.subscribe,
    currentBottomContent: () => current,
    setBottomContent,
    /** `true` selects the live lyrics sample, `false` the upcoming queue. */
    setLyricsPreview: (enabled: boolean) => setBottomContent(enabled ? 'lyrics' : 'queue'),
  };
}
export const sidebarPreferences = createSidebarPreferences();
/** `true` when the side player must show the lyrics sample instead of "Up next". */
export const sidebarLyricsPreviewEnabled = derived(sidebarPreferences, value => value === 'lyrics');

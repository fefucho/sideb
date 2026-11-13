import type { CollectionKind, HomeSettings } from './settings';
export function featuredSelectionKey(session: string, chip: string | null, kind: CollectionKind, settings: HomeSettings) {
  return JSON.stringify([session, chip, kind, kind === 'albums' ? settings.albumSources : settings.playlistSources]);
}
/** Preserve the actual anchor index while the column count changes, as HomeFeaturedView does.
 * A row resting at its start (never scrolled, or scrolled back) stays there: following its first card through a
 * reorder or a prepended item would leave the carousel displaced to the right without any user gesture (FIX-339). */
export function alignCollectionAnchor(anchor: number, previous: string[], next: string[]) {
  if (anchor <= 0) return 0;
  if (previous.length === next.length && previous.every((id,index)=>id === next[index])) return anchor;
  const index = next.indexOf(previous[anchor]);
  return index < 0 ? 0 : index;
}

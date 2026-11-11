import type { CollectionKind, HomeSettings } from './settings';
export function featuredSelectionKey(session: string, chip: string | null, kind: CollectionKind, settings: HomeSettings) {
  return JSON.stringify([session, chip, kind, kind === 'albums' ? settings.albumSources : settings.playlistSources]);
}
/** Preserve the actual anchor index while the column count changes, as HomeFeaturedView does. */
export function alignCollectionAnchor(anchor: number, previous: string[], next: string[]) {
  if (previous.length === next.length && previous.every((id,index)=>id === next[index])) return anchor;
  const index = next.indexOf(previous[anchor]);
  return index < 0 ? 0 : index;
}

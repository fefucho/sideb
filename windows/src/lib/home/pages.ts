import type { CollectionKind, HomeSettings } from './settings';
export function featuredSelectionKey(session: string, chip: string | null, kind: CollectionKind, settings: HomeSettings) {
  return JSON.stringify([session, chip, kind, kind === 'albums' ? settings.albumSources : settings.playlistSources]);
}

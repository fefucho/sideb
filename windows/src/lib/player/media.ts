import type { BrowseCardDto, PlaybackStateDto, SongDto } from '../types';
import { canonicalId } from '../home/settings';
import { collectionEntryId } from './controller';
export const MEDIA_CONTEXT = Symbol('sideb-media');
export interface MediaService {
  state: () => PlaybackStateDto;
  pending: () => string | null;
  activate: (card: BrowseCardDto) => void;
  toggle: () => void;
  rowActive: (song: SongDto, index: number, source?: { kind: string; id: string }) => boolean;
}
export function mediaKey(card: Pick<BrowseCardDto, 'kind' | 'id'>) {
  const kind = ['song', 'video'].includes(card.kind) ? 'radio' : card.kind === 'mix' ? 'playlist' : card.kind;
  return `${kind}|${canonicalId(kind, card.id)}`;
}
export function sourceActive(state: PlaybackStateDto, kind: string, id: string): boolean {
  const source = state.queue.source;
  if (!source || !state.currentTrack || !id.trim()) return false;
  const expected = ['song', 'video'].includes(kind) ? 'radio' : kind === 'mix' ? 'playlist' : kind;
  const sourceKind = source.kind === 'mix' ? 'playlist' : source.kind;
  return sourceKind === expected && canonicalId(expected, source.id ?? '') === canonicalId(expected, id);
}
export interface MediaRequestContext { play: number; session: number; navigation: number; generation: number }
/** Source-card loading survives navigation, but a different playback/account must invalidate it. */
export function mediaRequestCurrent(captured:MediaRequestContext,current:MediaRequestContext,sourceScope=false) {
  return captured.play === current.play && captured.session === current.session
    && (sourceScope ? captured.generation === current.generation : captured.navigation === current.navigation);
}
/** Occurrences in a list remain distinct even if video IDs are repeated. */
export function occurrenceActive(state: PlaybackStateDto, song: SongDto, index: number, kind: string, id: string) {
  if (!sourceActive(state, kind, id)) return false;
  const current = state.queue.items[state.queue.currentIndex ?? -1];
  if (!current) return false;
  return collectionEntryId({ kind, id, title: null }, song, index) === current.entryId;
}
export function songCard(song: SongDto): BrowseCardDto {
  return { ...song, kind: song.isVideo ? 'video' : 'song', id: song.videoId, subtitle: song.artists };
}

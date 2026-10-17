import type { BrowseCardDto } from '../types';
import { canonicalId } from '../home/settings';
export type LibrarySection = 'all' | 'songs' | 'playlists' | 'albums' | 'artists';
export type LibraryOrder = 'original' | 'name' | 'artist';
export interface LibraryPreferences { version: 1; tab: LibrarySection; layout: 'grid' | 'list'; order: LibraryOrder; pins: BrowseCardDto[]; }
export const libraryDefaults = (): LibraryPreferences => ({ version: 1, tab: 'all', layout: 'grid', order: 'original', pins: [] });
const libraryKind = (kind: string) => kind === 'mix' ? 'playlist' : kind;
export const libraryKey = (card: BrowseCardDto) => `${libraryKind(card.kind)}:${canonicalId(libraryKind(card.kind),card.id)}`;
export const libraryMatches = (query: string, ...values: (string | null | undefined)[]) => values.some(value => value?.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()));
export function readLibraryPreferences(storage: Pick<Storage, 'getItem'>, account: string): LibraryPreferences {
  const fallback = libraryDefaults();
  try {
    const raw = JSON.parse(storage.getItem(`sideb.library.v1:${account}`) ?? 'null');
    if (raw?.version !== 1) return fallback;
    return { version: 1, tab: ['all','songs','playlists','albums','artists'].includes(raw.tab) ? raw.tab : 'all',
      layout: raw.layout === 'list' ? 'list' : 'grid', order: ['original','name','artist'].includes(raw.order) ? raw.order : 'original',
      pins: Array.isArray(raw.pins) ? raw.pins.filter((p: BrowseCardDto) => p && ['album','playlist','artist','mix'].includes(p.kind) && typeof p.id === 'string' && p.id.trim().length > 0 && typeof p.title === 'string')
        .filter((p: BrowseCardDto, i: number, all: BrowseCardDto[]) => all.findIndex(other => libraryKey(other) === libraryKey(p)) === i).slice(0, 50)
        .map((p: BrowseCardDto) => ({ kind:libraryKind(p.kind),id:canonicalId(libraryKind(p.kind),p.id),title:p.title,subtitle:typeof p.subtitle==='string'?p.subtitle:null,thumbnail:typeof p.thumbnail==='string'?p.thumbnail:null })) : [] };
  } catch { return fallback; }
}
export function writeLibraryPreferences(storage: Pick<Storage, 'setItem'>, account: string, value: LibraryPreferences) {
  try { storage.setItem(`sideb.library.v1:${account}`, JSON.stringify({...value,pins:value.pins.map(p=>({kind:libraryKind(p.kind),id:canonicalId(libraryKind(p.kind),p.id),title:p.title,subtitle:typeof p.subtitle==='string'?p.subtitle:null,thumbnail:typeof p.thumbnail==='string'?p.thumbnail:null}))})); } catch { /* Session preferences remain usable when storage is unavailable. */ }
}
export function orderedLibraryCards(cards: BrowseCardDto[], query: string, order: LibraryOrder) {
  const matching = cards.filter(card => libraryMatches(query, card.title, card.subtitle));
  if (order === 'original') return matching;
  return matching.map((card,index) => ({card,index})).sort((a,b) =>
    (order === 'artist' ? a.card.subtitle ?? '' : a.card.title).localeCompare(order === 'artist' ? b.card.subtitle ?? '' : b.card.title, undefined, {sensitivity:'base',numeric:true}) || a.index-b.index).map(item=>item.card);
}
// Navigation state is ephemeral; account keys prevent crossing private sessions.
export const libraryNavigation = new Map<string, { query: string; scroll: number }>();

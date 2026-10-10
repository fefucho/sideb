import type { BrowseCardDto, HomeItemDto, HomeSectionDto } from '../types';
import { homeSections } from './presentation';
import { normalizeHomeSongCard } from './songMetadata';
import { canonicalId, categoryKey, sourceForTitle, type CollectionKind, type HomeSettings } from './settings';
type History = { items: { albumId: string | null; album: string | null; artists: string; artistId: string | null; artistRuns?: HomeItemDto['artistRuns'] }[] }[];
export function homeItem(card: BrowseCardDto): HomeItemDto {
  return { ...card, artists: card.artists ?? null, artistId: card.artistId ?? null, albumId: card.albumId ?? null,
    album: card.album ?? null, artistRuns: card.artistRuns ?? [], explicit: card.explicit ?? false };
}
export function projectHome(sections: HomeSectionDto[], chip: string | null, settings: HomeSettings, kind: CollectionKind,
  capacity: number, albums: BrowseCardDto[] = [], playlists: BrowseCardDto[] = [], history: History = []) {
  const providerSections = homeSections(sections, chip);
  const rank = (title: string) => { const i = settings.categoryOrder.indexOf(categoryKey(title)); return i < 0 ? Number.MAX_SAFE_INTEGER : i; };
  const orderedRecords = settings.categoryOrderMode === 'custom' ? [...sections].sort((a,b) => rank(a.title) - rank(b.title)) : sections;
  const categoryRecords = settings.categoryOrderMode === 'sideB' ? providerSections : orderedRecords;
  const seenCategories = new Set<string>();
  const categories = categoryRecords.flatMap(section => { const key = categoryKey(section.title); if(seenCategories.has(key)) return []; seenCategories.add(key); return [{key,title:section.title}]; });
  const songs: HomeItemDto[] = []; const songIds = new Set<string>();
  const songPriority = (title: string) => ({'speed-dial':0,'quick-picks':0,'listen-again':1,'forgotten-favorites':2,'from-library':3} as Record<string,number>)[categoryKey(title)] ?? 4;
  const orderedSongs = [...providerSections].sort((a,b) => songPriority(a.title) - songPriority(b.title));
  for (const section of orderedSongs) for (const {record:item} of section.items) {
    if (item.kind !== 'song' || !item.id || songIds.has(item.id) || songs.length >= 27) continue;
    songIds.add(item.id); songs.push(normalizeHomeSongCard(item));
  }
  const recent: HomeItemDto[] = [];
  const recentIds = new Set<string>();
  for (const group of history) for (const song of group.items) {
    if (!song.albumId || recentIds.has(song.albumId)) continue;
    recentIds.add(song.albumId);
    const stored = albums.find(card => card.id === song.albumId);
    recent.push(homeItem(stored ?? { kind: 'album', id: song.albumId, title: song.album ?? 'Álbum', subtitle: song.artists, thumbnail: null, duration: null, artists: song.artists, artistId: song.artistId, artistRuns: song.artistRuns }));
  }
  const preferences = kind === 'albums' ? settings.albumSources : settings.playlistSources;
  const collections: HomeItemDto[] = []; const exposed = new Set<string>();
  const itemKey = (item: HomeItemDto) => `${item.kind}|${canonicalId(item.kind, item.id)}`;
  for (const preference of preferences) {
    if (!preference.enabled) continue;
    const candidates = preference.source === 'libraryAlbums' ? albums.map(homeItem)
      : preference.source === 'libraryPlaylists' ? playlists.map(homeItem) : preference.source === 'recentAlbums' ? recent
      : providerSections.filter(section => sourceForTitle(section.title) === preference.source).flatMap(section => section.items.map(item => item.record));
    for (const item of candidates) {
      if (item.kind !== (kind === 'albums' ? 'album' : 'playlist') || !canonicalId(item.kind,item.id) || exposed.has(itemKey(item)) || collections.length >= ([2,4,6].includes(capacity)?capacity:2) * 6) continue;
      exposed.add(itemKey(item)); collections.push(item);
    }
  }
  let shelves = homeSections(orderedRecords, chip, settings.categoryOrderMode !== 'sideB');
  shelves = shelves.filter(s => !settings.hiddenCategoryKeys.includes(categoryKey(s.title)))
    .map(s => ({ ...s, items: s.items.filter(({ record }) => !exposed.has(itemKey(record)) && !(record.kind === 'song' && songIds.has(record.id))) }))
    .filter(s => s.items.length);
  const uniqueArt = (items:HomeItemDto[]) => [...new Set(items.map(item=>item.thumbnail).filter((url):url is string=>Boolean(url)))];
  const artwork = [...new Set([...uniqueArt(collections).slice(0,2),...uniqueArt(songs).slice(0,2),...uniqueArt([...collections,...songs])])].slice(0,4);
  return { categories, songs, collections, shelves, artwork };
}
/** HomeFeaturedLayout in logical pixels; width includes the 28px insets. */
export function featuredLayout(width:number,songCount:number,collectionCount:number) {
  const wide=width>=900, inner=Math.max(0,width-56);
  const tile=Math.min(wide?144:140,Math.max(0,((wide&&collectionCount?inner-24-432:inner)-16)/3));
  const songWidth=3*tile+16;
  const available=wide&&songCount?Math.max(0,inner-24-songWidth):inner;
  const columns=Math.min(3,Math.max(1,Math.ceil(collectionCount/2)),Math.max(1,Math.floor((available+24)/456)));
  const columnWidth=(available-(columns-1)*24)/columns;
  const songRows=songCount?Math.ceil(Math.min(9,Math.max(1,songCount))/3):0;
  const songHeight=songRows*tile+Math.max(0,songRows-1)*8;
  const rows=collectionCount?Math.min(2,Math.max(1,collectionCount)):0;
  const cardHeight=wide&&songCount&&collectionCount?Math.min(212,Math.max(152,(songHeight-Math.max(0,rows-1)*24)/rows)):Math.min(212,Math.max(164,columnWidth*.3));
  return {wide,tile,songWidth,columns,capacity:columns*2,cardHeight};
}
export function featuredCapacity(width:number,count=Infinity,songCount=9) {
  return featuredLayout(width,songCount,count).capacity;
}
export function visibleSignature(projection: ReturnType<typeof projectHome>) {
  return JSON.stringify([projection.songs, projection.collections, projection.shelves.map(s => [s.id, s.title, s.items])]);
}

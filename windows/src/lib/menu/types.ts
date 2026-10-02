import type { AlbumDetailDto, ArtistDetailDto, BrowseCardDto, HomeItemDto, PlaylistDetailDto, QueueEntryDto, SongDto } from '../types';

export type MenuTarget =
  | { kind: 'song'; song: SongDto; entryId?: string }
  | { kind: 'album'; card: BrowseCardDto; detail?: AlbumDetailDto }
  | { kind: 'artist'; card: BrowseCardDto; detail?: ArtistDetailDto }
  | { kind: 'playlist'; card: BrowseCardDto; detail?: PlaylistDetailDto };
export interface MenuOrigin {
  view?: string;
  currentId?: string | null;
  playlistId?: string | null;
  playlistOwned?: boolean;
  currentQueueEntryId?: string | null;
  nowPlaying?: boolean;
}
export interface MenuService { open(event: MouseEvent | KeyboardEvent, target: MenuTarget, origin?: MenuOrigin): void }
export type MenuAction = { type: 'play' | 'shuffle' | 'radio' | 'enqueue-next' | 'enqueue-end' | 'like' | 'save-song' | 'save-collection' | 'subscribe' | 'open' | 'open-album' | 'open-artist' | 'share' | 'remove-playlist' | 'remove-queue' | 'edit-playlist' | 'delete-playlist' | 'new-playlist' }
  | { type: 'add-to-playlist'; playlistId: string }
  | { type: 'sort-playlist'; sort: string };
export type MenuIconName = 'play' | 'shuffle' | 'radio' | 'queue-next' | 'queue-end' | 'heart' | 'heart-remove' | 'heart-fill' | 'bookmark' | 'bookmark-fill' | 'music-list' | 'list-add' | 'plus' | 'disc' | 'person' | 'share' | 'trash' | 'minus' | 'edit' | 'sort' | 'reorder' | 'history' | 'clock' | 'text' | 'bell' | 'bell-off';
export interface MenuItem { id: string; label: string; icon?: MenuIconName; disabled?: boolean; checked?: boolean; action?: MenuAction; children?: MenuItem[]; separator?: boolean }
export interface MenuFacts { loggedIn: boolean; likedIds: Set<string>; playlists: BrowseCardDto[] }
export interface MenuRequest { x: number; y: number; target: MenuTarget; origin: MenuOrigin; focus: HTMLElement | null }
export const MENU_CONTEXT = Symbol('sideb-menu');

export function songFromHome(item: HomeItemDto): SongDto {
  return { videoId: item.id, title: item.title, artists: item.artists ?? item.subtitle ?? '',
    thumbnail: item.thumbnail, duration: item.duration, album: item.album, albumId: item.albumId,
    artistId: item.artistId, artistRuns: item.artistRuns.map(run => ({ ...run })), isVideo: item.kind === 'video' };
}
export function songFromQueue(item: QueueEntryDto | Omit<QueueEntryDto, 'entryId'>): SongDto {
  return { videoId: item.videoId, title: item.title, artists: item.artists, thumbnail: item.thumbnail,
    duration: item.duration == null ? null : String(Math.floor(item.duration / 60)) + ':' + String(Math.floor(item.duration % 60)).padStart(2, '0'),
    album: item.album ?? null, albumId: item.albumId ?? null, artistId: item.artistId ?? null,
    artistRuns: item.artistRuns?.map(run => ({ ...run })) ?? [], isVideo: false };
}
export function targetFromCard(card: BrowseCardDto): MenuTarget | null {
  if (card.kind === 'song' || card.kind === 'video') return { kind: 'song', song: {
    videoId: card.id, title: card.title, artists: card.artists ?? card.subtitle ?? '', thumbnail: card.thumbnail,
    duration: card.duration, album: card.album ?? null, albumId: card.albumId ?? null, artistId: card.artistId ?? null,
    artistRuns: card.artistRuns?.map(run => ({ ...run })) ?? [], isVideo: card.kind === 'video',
  } };
  if (card.kind === 'album' || card.kind === 'artist' || card.kind === 'playlist') return { kind: card.kind, card };
  if (card.id.startsWith('RD')) return { kind: 'playlist', card };
  return null;
}

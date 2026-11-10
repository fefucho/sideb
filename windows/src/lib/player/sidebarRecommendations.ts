import type { BrowseCardDto, PlaybackTrackDto, SongDto } from '../types';
import { recommendationIdentity, type RecommendedData } from './recommendations';
import { recommendedOffsets } from './recommended-viewport';

/**
 * Presentation helpers for the playback sidebar's recommendations feed (PLAN-023 W5).
 * They are pure: no playback clock, no requests and no queue state. The native queue
 * stays authoritative; this feed only projects the data `RecommendationsController` already owns.
 */

/** Downward scroll, past the initial hero position, that activates the feed. Never 0: opening the panel must not load anything. */
export const SIDEBAR_RECOMMENDATION_ACTIVATION_OFFSET = 24;
/** Songs/artists mounted per shelf. Matches `PreparedSidebarRecommendations(maxPerShelf: 10)` on macOS. */
export const SIDEBAR_RECOMMENDATION_SHELF_LIMIT = 10;
/** Fixed row heights (px), identical to the macOS `NSTableView` delegate. */
export const SIDEBAR_ROW_HEIGHT = { refresh: 44, heading: 40, track: 54, artists: 140, status: 180 } as const;
/** Artist shelf cell: 92 px card, 12 px gap, 16 px edge inset. */
export const SIDEBAR_ARTIST_CARD_WIDTH = 92;
export const SIDEBAR_ARTIST_CARD_GAP = 12;

export interface SidebarHeadingTitle { key: string; args: string[] }
export type SidebarShelf = 'similar' | 'artist' | 'album';
export type SidebarRecommendationRow =
  | { kind: 'hero'; id: 'hero' }
  | { kind: 'refresh'; id: 'refresh' }
  | { kind: 'heading'; id: string; title: SidebarHeadingTitle; browseId: string | null; target: 'artist' | 'album' | null }
  | { kind: 'track'; id: string; shelf: SidebarShelf; index: number; song: SongDto }
  | { kind: 'artists'; id: 'artists'; cards: BrowseCardDto[] }
  | { kind: 'status'; id: 'status'; state: 'idle' | 'loading' | 'empty' | 'error'; error: string | null };

export interface PreparedSidebarRecommendations {
  artists: BrowseCardDto[];
  similarSongs: Array<{ id: string; shelf: SidebarShelf; index: number; song: SongDto }>;
  artistSongs: Array<{ id: string; shelf: SidebarShelf; index: number; song: SongDto }>;
  albumSongs: Array<{ id: string; shelf: SidebarShelf; index: number; song: SongDto }>;
}

/** Duplicate provider occurrences keep distinct ids through shelf + position (`similar-3-videoId`). */
function prepareShelf(shelf: SidebarShelf, songs: SongDto[], limit: number) {
  return songs.slice(0, limit).map((song, index) => ({ id: `${shelf}-${index}-${song.videoId}`, shelf, index, song }));
}
export function prepareSidebarRecommendations(data: RecommendedData, limit = SIDEBAR_RECOMMENDATION_SHELF_LIMIT): PreparedSidebarRecommendations {
  return {
    artists: data.relatedArtists.slice(0, limit),
    similarSongs: prepareShelf('similar', data.similarSongs, limit),
    artistSongs: prepareShelf('artist', data.artistSongs, limit),
    albumSongs: prepareShelf('album', data.albumSongs, limit),
  };
}
export const sidebarRecommendationsEmpty = (prepared: PreparedSidebarRecommendations) =>
  !prepared.artists.length && !prepared.similarSongs.length && !prepared.artistSongs.length && !prepared.albumSongs.length;

export interface SidebarProjectionInput {
  data: RecommendedData | null;
  activated: boolean;
  loading: boolean;
  error: string | null;
}
/**
 * Flat row list. Before the first real scroll only the hero spacer and an empty status row exist,
 * so no artwork request, artist shelf or song row is constructed.
 */
export function projectSidebarRecommendations({ data, activated, loading, error }: SidebarProjectionInput): SidebarRecommendationRow[] {
  const rows: SidebarRecommendationRow[] = [{ kind: 'hero', id: 'hero' }];
  if (!activated) return [...rows, { kind: 'status', id: 'status', state: 'idle', error: null }];
  rows.push({ kind: 'refresh', id: 'refresh' });
  const prepared = data ? prepareSidebarRecommendations(data) : null;
  if (data && prepared && !sidebarRecommendationsEmpty(prepared)) {
    if (prepared.artists.length) {
      rows.push({ kind: 'heading', id: 'heading:artists', title: { key: 'fullscreen.fansAlsoLike', args: [] }, browseId: null, target: null });
      rows.push({ kind: 'artists', id: 'artists', cards: prepared.artists });
    }
    const shelf = (items: PreparedSidebarRecommendations['similarSongs'], id: string, title: SidebarHeadingTitle, browseId: string | null, target: 'artist' | 'album' | null) => {
      if (!items.length) return;
      rows.push({ kind: 'heading', id: `heading:${id}`, title, browseId, target });
      for (const item of items) rows.push({ kind: 'track', ...item });
    };
    shelf(prepared.similarSongs, 'similar', { key: 'fullscreen.similarSongs', args: [] }, null, null);
    shelf(prepared.artistSongs, 'artist', data.artistName ? { key: 'fullscreen.moreByArtist', args: [data.artistName] } : { key: 'fullscreen.moreByThisArtist', args: [] }, data.artistBrowseId, 'artist');
    shelf(prepared.albumSongs, 'album', data.albumTitle ? { key: 'fullscreen.fromAlbum', args: [data.albumTitle] } : { key: 'fullscreen.fromSameAlbum', args: [] }, data.albumBrowseId, 'album');
    // Partial failures keep the usable shelves and still offer a retry.
    if (error) rows.push({ kind: 'status', id: 'status', state: 'error', error });
  } else {
    rows.push({ kind: 'status', id: 'status', state: error ? 'error' : loading ? 'loading' : 'empty', error });
  }
  return rows;
}

export function sidebarRowHeight(row: SidebarRecommendationRow, heroHeight: number): number {
  if (row.kind === 'hero') return Math.max(0, heroHeight);
  return SIDEBAR_ROW_HEIGHT[row.kind];
}
/** Cumulative offsets for `recommendedRange`; `total` is the scrollable height. */
export function sidebarLayout(rows: SidebarRecommendationRow[], heroHeight: number) {
  const offsets = recommendedOffsets(rows, row => sidebarRowHeight(row, heroHeight), 0, 0);
  return { offsets, total: offsets.at(-1) ?? 0 };
}

/** The Y where the blurred/tinted feed surface starts; only the covered area carries the material. */
export const sidebarFeedTop = (heroHeight: number, scrollTop: number) => Math.max(0, heroHeight - Math.max(0, scrollTop));

/** Occurrence identity: account session + song context (+ optional queue occurrence). Any change returns to the hero. */
export function sidebarRequestKey(session: number, track: PlaybackTrackDto | null, occurrenceId: string | null = null): string {
  return JSON.stringify([session, recommendationIdentity(track), occurrenceId]);
}

/**
 * Per-occurrence activation. It latches (leaving the feed does not unmount shelves again) and is
 * reset whenever the key changes (account, song or queue occurrence).
 */
export class SidebarRecommendationsGate {
  private key: string | null = null;
  private latched = false;
  get activated() { return this.latched; }
  /** Returns true when the key changed, so the owner can return to the hero. */
  sync(key: string): boolean {
    if (key === this.key) return false;
    this.key = key; this.latched = false;
    return true;
  }
  /** Scroll evaluation: activation needs a strictly positive offset and a current song. */
  update(offsetY: number, hasTrack: boolean): boolean {
    if (!this.latched && hasTrack && offsetY >= SIDEBAR_RECOMMENDATION_ACTIVATION_OFFSET) this.latched = true;
    return this.latched;
  }
}

/**
 * Whether the owner should ask the controller to load. `RecommendationsController.load()` is
 * idempotent per song, and it also clears itself when a song is accepted late (the page passes
 * `null` while a track is loading), so this re-requests after such an invalidation without looping:
 * a finished load always leaves data (possibly empty) or an error behind.
 */
export function shouldRequestSidebarRecommendations(input: { activated: boolean; hasTrack: boolean; loading: boolean; hasData: boolean; error: string | null }): boolean {
  return input.activated && input.hasTrack && !input.loading && !input.hasData && !input.error;
}

/**
 * Data is only shown for the current song and the current account generation:
 * `loadedVideoId`/`requestIdentity` must match and the `contextKey` must not be one that was
 * already on screen when the account session changed (stale responses are discarded).
 */
export function currentSidebarData(data: RecommendedData | null, track: PlaybackTrackDto | null, rejectedContexts: ReadonlySet<string>): RecommendedData | null {
  if (!data || !track || data.loadedVideoId !== track.videoId) return null;
  if (data.requestIdentity && data.requestIdentity !== recommendationIdentity(track)) return null;
  if (data.contextKey && rejectedContexts.has(data.contextKey)) return null;
  return data;
}

/** wheel deltas normalised to pixels for forwarding scroll that started over the hero. */
export function wheelPixels(event: { deltaY: number; deltaMode: number }, pageExtent: number): number {
  return event.deltaMode === 1 ? event.deltaY * 16 : event.deltaMode === 2 ? event.deltaY * pageExtent : event.deltaY;
}

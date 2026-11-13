// Shared model of the Jam session logic: internal data, the core services every module uses, and
// the conversions between YouTube Music songs, matches and native queue entries.
import { contentRating } from '../contentRating';
import type { PlayerRpc } from '../player/controller';
import type { PlaybackStateDto, QueueEntryDto, SongDto } from '../types';
import { durationSeconds } from './matcher';
import { isJamEntryId } from './queueMapping';
import type { JamMatchedSong, JamPluginTrack, JamScheduler, JamSyncStatus, JamViewState } from './types';

/** A YouTube Music song chosen for a Jam track, with what the native queue entry needs. */
export interface Matched {
  view: JamMatchedSong;
  album: string | null;
  albumId: string | null;
  artistId: string | null;
  artistRuns: NonNullable<QueueEntryDto['artistRuns']>;
  isUpload: boolean;
  rating: 'explicit' | 'clean' | 'unknown';
}

export type MatchState = { kind: 'matched'; match: Matched; corrected: boolean } | { kind: 'unavailable' };

export function songToMatched(song: SongDto): Matched {
  return {
    view: { videoId: song.videoId, title: song.title, artists: song.artists, thumbnail: song.thumbnail, durationSecs: durationSeconds(song.duration) },
    album: song.album, albumId: song.albumId, artistId: song.artistId, artistRuns: song.artistRuns?.map(run => ({ ...run })) ?? [],
    isUpload: song.isUpload ?? false, rating: contentRating(song)
  };
}

/** A version picked by hand in the UI: it carries only what `JamMatchedSong` has. */
export function viewToMatched(view: JamMatchedSong): Matched {
  return { view: { ...view }, album: null, albumId: null, artistId: null, artistRuns: [], isUpload: false, rating: 'unknown' };
}

/**
 * The native queue assigns fresh opaque `entryId`s on every `play_song` / `jam_replace_upcoming`
 * and keeps only `sourceOccurrenceId`, so the Jam identity (`jam|<uri>|<n>`) travels there.
 * `entryId` is required by the DTO but ignored by the native side.
 */
export function matchedEntry(match: Matched, jamId: string): QueueEntryDto {
  const { view } = match;
  return {
    contentRating: match.rating, isUpload: match.isUpload, entryId: jamId, sourceOccurrenceId: jamId, videoId: view.videoId, title: view.title,
    artists: view.artists, thumbnail: view.thumbnail, duration: view.durationSecs, artistId: match.artistId, albumId: match.albumId,
    album: match.album, artistRuns: match.artistRuns.map(run => ({ ...run }))
  };
}

/** Jam identity of a native queue entry (`null` when the entry is not one of ours). */
export function jamIdOf(entry: QueueEntryDto | null | undefined): string | null {
  const id = entry?.sourceOccurrenceId;
  return id && isJamEntryId(id) ? id : null;
}

/** The native entry with this (opaque) native id in a playback snapshot. */
export function nativeEntry(playback: PlaybackStateDto | null, nativeId: string | null | undefined): QueueEntryDto | null {
  if (!playback || !nativeId) return null;
  return playback.queue.items.find(entry => entry.entryId === nativeId) ?? null;
}

/** Timing reference actually followed; updated only on real changes so reporting jitter never moves the target. */
export interface Anchor {
  positionMs: number;
  /** Local-clock instant (epoch ms) at which `positionMs` was true. */
  atLocalMs: number;
  paused: boolean;
  durationMs: number | null;
}

export function livePositionSeconds(anchor: Anchor, nowMs: number): number {
  const elapsed = anchor.paused ? 0 : Math.max(0, nowMs - anchor.atLocalMs);
  return (anchor.positionMs + elapsed) / 1000;
}

export interface JamData {
  /** Changes whenever a session starts or ends; late work from an older session checks it. */
  token: number;
  track: JamPluginTrack | null;
  queue: JamPluginTrack[];
  queueRevision: string | null;
  anchor: Anchor | null;
  matches: Map<string, MatchState>;
  /** Versions picked by hand, by Spotify URI; they outlive a session. */
  overrides: Map<string, Matched>;
  /** Last native playback snapshot the app reported. */
  playback: PlaybackStateDto | null;
  /** The user paused locally because they cannot control the Jam; sync keeps its hands off. */
  locallyPaused: boolean;
  /** The user sought locally because they cannot control the Jam; sync stays out until the next real change. */
  syncHold: boolean;
  offsetMs: number | null;
  syncStatus: JamSyncStatus;
}

export interface MirrorApi {
  /** The Jam's current track changed (or became known). */
  onTrackChange(): void;
  /** The upcoming list changed. */
  onQueueChange(): void;
  /** A lookup settled for `uri`. */
  onMatch(uri: string): void;
  /** Load the current track now, even if the player already shows an equivalent entry. */
  loadCurrent(force: boolean): void;
  onPlayback(state: PlaybackStateDto): void;
  /** A load or replace is in flight. */
  busy(): boolean;
  /** Entry id of the native entry that is playing, if it belongs to the Jam. */
  nativeCurrentEntryId(): string | null;
  stop(): void;
}

export interface SyncApi {
  /** Opens a correction window after a real change; also lifts a local hold. */
  begin(): void;
  start(): void;
  stop(): void;
  pauseLocal(): void;
}

export interface MatchingApi {
  statusOf(uri: string): 'pending' | 'searching' | 'matched' | 'unavailable';
  matchOf(uri: string): Matched | null;
  pump(): void;
  /** Gives failed lookups that ran out of attempts another chance. */
  retryExhausted(): void;
  reset(): void;
  setCorrected(uri: string, match: Matched): void;
}

/** Services shared by the session modules. */
export interface JamCore {
  /** Raw Tauri invoke: calls made by the Jam itself bypass the Jam-aware wrapper. */
  raw: PlayerRpc;
  now(): number;
  sched: JamScheduler;
  d: JamData;
  /** A Jam is in progress (joining excluded): phase `active` or `reconnecting`. */
  isLive(): boolean;
  /** The session `token` still is the running one. */
  isCurrent(token: number): boolean;
  view(): JamViewState;
  patch(partial: Partial<JamViewState>): void;
  /** Rebuild `current`/`queue` of the view from the data. */
  publishTracks(): void;
  note(line: string): void;
  toast(key: string, values?: Record<string, string>): void;
  /** `jam_send`; false when the runtime rejected it. */
  send(message: Record<string, unknown>): Promise<boolean>;
  /** Registers interest in the `commandResult` of `requestId`. */
  expectResult(requestId: string, handler: (ok: boolean, detail: string | null) => void): void;
  forgetResult(requestId: string): void;
  newId(prefix: string): string;
  mirror: MirrorApi;
  sync: SyncApi;
  matching: MatchingApi;
}

export const rpcCode = (error: unknown): string =>
  error && typeof error === 'object' && 'code' in error && typeof error.code === 'string' ? error.code : 'error';

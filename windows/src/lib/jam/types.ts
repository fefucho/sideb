// Spotify Jam on Windows (PAR-062, windows/plans/PLAN-028-spotify-jam.md).
// This file is the contract between the runtime bridge (src-tauri/src/jam), the session logic
// (src/lib/jam) and the UI (src/lib/components/jam). Change it additively.

import type { PlaybackStateDto, QueueEntryDto } from '../types';

// MARK: Plugin protocol v2 (extensions/README.md, "Spotify Jam"). Arrives as the `jam-event` payload.

export interface JamPluginTrack {
  uri: string;
  title: string | null;
  artists: string[];
  album: string | null;
  durationMs: number | null;
  isrc: string | null;
  provider: string | null;
}

export interface JamPluginMember {
  id?: string | null;
  name?: string | null;
  imageUrl?: string | null;
  isHost?: boolean;
  isCurrentUser?: boolean;
}

export type JamPluginEvent =
  | { type: 'joined'; protocolVersion: number; members: JamPluginMember[]; canControl: boolean; queueOnly: boolean; hostDevice: string | null; hostActive: boolean }
  | { type: 'state'; track: JamPluginTrack | null; positionMs: number; atLocalMs: number; paused: boolean; durationMs: number | null; queue: JamPluginTrack[]; queueRevision: string | null; previousCount: number; shuffle: boolean; clockOffsetMs: number }
  | { type: 'members'; members: JamPluginMember[] }
  | { type: 'session'; reason: string | null }
  | { type: 'notice'; code: string }
  | { type: 'commandResult'; action: string; ok: boolean; detail: string | null; requestId?: string }
  | { type: 'resolved'; requestId: string; uri: string | null; title: string | null; artists: string[]; durationMs: number | null }
  | { type: 'ended'; reason: string | null }
  | { type: 'error'; code: string; retryable: boolean }
  /** Synthesised by the runtime when the plugin process ends without `ended`. */
  | { type: 'exited'; code: number | null };

// MARK: Runtime bridge (Tauri commands and events of src-tauri/src/jam)

/** `jam_status`. */
export interface JamRuntimeStatus {
  /** `sideb-spotify-jam.exe` was found next to the app. */
  pluginAvailable: boolean;
  /** A plugin process is alive. */
  running: boolean;
  /** A Spotify web session is known to exist; `null` = not checked yet. */
  signedIn: boolean | null;
}

/** `jam_clock`: the audible position, sampled straight from the player. */
export interface JamClock {
  positionSecs: number;
  /** `Date.now()`-compatible instant at which `positionSecs` was read. */
  atEpochMs: number;
  isPlaying: boolean;
  isLoading: boolean;
  videoId: string | null;
  entryId: string | null;
  generation: number;
  authGeneration: number;
  /** Current playback rate (1 outside a correction burst). */
  speed: number;
}

/**
 * Commands (all reject with `{ code, message }` like the rest of the app):
 * - `jam_status(): JamRuntimeStatus`
 * - `jam_join({ link }): void` — codes `JAM_PLUGIN_MISSING`, `JAM_NOT_SIGNED_IN`, `JAM_START_FAILED`.
 *   The runtime obtains the Spotify token itself; it never crosses IPC.
 * - `jam_send({ message })` — only `{type:"command",…}` and `{type:"resolve",…}`; codes
 *   `JAM_NOT_RUNNING`, `JAM_INVALID_MESSAGE`.
 * - `jam_leave(): void` — idempotent; also restores speed 1.
 * - `jam_open_spotify_login({ title }): boolean`, `jam_cancel_spotify_login(): void`
 * - `jam_spotify_sign_out(): void`
 * - `jam_set_speed({ speed }): void` — clamped to 0.9…1.1.
 * - `jam_clock(): JamClock`
 * - `jam_replace_upcoming({ items: QueueEntryDto[] }): PlaybackStateDto` — replaces everything
 *   after the current entry, without touching the audio.
 * Events: `jam-event` (JamPluginEvent), `jam-spotify-login` ({ state: string }, same states as
 * `visual-provider-login`).
 */
export const JAM_EVENT = 'jam-event';
export const JAM_LOGIN_EVENT = 'jam-spotify-login';
/** `queue.source.kind` of the mirrored queue; never triggers radio or source loading. */
export const JAM_QUEUE_SOURCE_KIND = 'jam';

/** Injectable timers so the session logic runs without real time (tests, simulations). */
export interface JamScheduler {
  setTimeout(callback: () => void, ms: number): unknown;
  clearTimeout(handle: unknown): void;
}

// MARK: View state (what the UI renders)

export type JamPhase = 'idle' | 'joining' | 'active' | 'reconnecting' | 'ended' | 'error';
export type JamMatchStatus = 'pending' | 'searching' | 'matched' | 'unavailable';
export type JamSyncStatus = 'idle' | 'adjusting' | 'locked' | 'gaveUp';

export interface JamMember {
  id: string;
  name: string;
  imageUrl: string | null;
  isHost: boolean;
  isMe: boolean;
}

export interface JamMatchedSong {
  videoId: string;
  title: string;
  artists: string;
  thumbnail: string | null;
  durationSecs: number | null;
}

export interface JamTrackView {
  /** Stable per occurrence (URI + occurrence number). */
  key: string;
  uri: string;
  title: string;
  artists: string;
  album: string | null;
  durationMs: number | null;
  status: JamMatchStatus;
  matched: JamMatchedSong | null;
  /** The user picked this version by hand. */
  corrected: boolean;
  /** A person added it to the Jam (plugin `provider === 'queue'`); otherwise it is a Spotify suggestion. */
  addedByPerson?: boolean;
}

export interface JamNoticeView {
  /** i18n key (`jam.notice.*`, `jam.error.*`). */
  key: string;
  /** Values for `{placeholders}` in the string. */
  values?: Record<string, string>;
}

export interface JamPendingExit {
  /** What the user tried to do; i18n key for the dialog body (`jam.exit.*`). */
  reasonKey: string;
}

export interface JamViewState {
  phase: JamPhase;
  runtime: JamRuntimeStatus;
  /** Set when `phase` is `error` or `ended` (i18n key). */
  messageKey: string | null;
  members: JamMember[];
  host: JamMember | null;
  canControl: boolean;
  hostActive: boolean;
  current: JamTrackView | null;
  queue: JamTrackView[];
  paused: boolean;
  sync: {
    status: JamSyncStatus;
    /** Local minus Jam, in ms; `null` while unknown. */
    offsetMs: number | null;
    /** User trim added to the target (debug menu). */
    manualOffsetMs: number;
  };
  /** Newest first, capped; the UI shows them as toasts. */
  toasts: Array<JamNoticeView & { id: number }>;
  pendingExit: JamPendingExit | null;
  /** Last debug lines (debug menu). */
  log: string[];
}

export interface JamActions {
  refreshStatus(): Promise<void>;
  openLogin(title: string): Promise<void>;
  signOut(): Promise<void>;
  join(link: string): Promise<void>;
  leave(): Promise<void>;
  /** The user picked another YouTube Music version for a Jam track: load and sync it right away. */
  correctMatch(key: string, song: JamMatchedSong): Promise<void>;
  /** Asks Spotify to add the YouTube Music song to the Jam (resolves its Spotify equivalent first). */
  addSong(song: { title: string; artists: string; album?: string | null; durationSecs?: number | null }, index?: number): Promise<boolean>;
  /** `from`/`to` index `JamViewState.queue` (0 = plays next); `to` is the final index after the move. */
  moveQueue(from: number, to: number): Promise<void>;
  /** `index` indexes `JamViewState.queue`. */
  removeQueue(index: number): Promise<void>;
  setManualOffset(ms: number): void;
  resync(): void;
  dismissToast(id: number): void;
  confirmExit(): Promise<void>;
  cancelExit(): void;
}

export const emptyJamState = (): JamViewState => ({
  phase: 'idle',
  runtime: { pluginAvailable: false, running: false, signedIn: null },
  messageKey: null,
  members: [],
  host: null,
  canControl: false,
  hostActive: false,
  current: null,
  queue: [],
  paused: true,
  sync: { status: 'idle', offsetMs: null, manualOffsetMs: 0 },
  toasts: [],
  pendingExit: null,
  log: []
});

/** Re-exported so consumers of the contract do not need the app types. */
export type { PlaybackStateDto, QueueEntryDto };

// Pure presentation rules of the Jam surfaces (no DOM): kept apart so they are testable and shared.
import { text, hasText, type AppLanguage } from '$lib/i18n';
import type { JamMatchedSong, JamMember, JamNoticeView, JamPhase, JamTrackView, JamViewState } from '$lib/jam/types';
import type { PlaybackStateDto, QueueEntryDto, SongDto } from '$lib/types';

/** The Jam owns the queue and the transport (also while it reconnects). */
export const isJamLive = (state: Pick<JamViewState, 'phase'> | null | undefined): boolean =>
  state?.phase === 'active' || state?.phase === 'reconnecting';
export const isJamPhase = (phase: JamPhase): boolean => phase === 'active' || phase === 'reconnecting';

export const hostOf = (state: Pick<JamViewState, 'host' | 'members'>): JamMember | null =>
  state.host ?? state.members.find(member => member.isHost) ?? null;
export const hostNameOf = (state: Pick<JamViewState, 'host' | 'members'>): string | null => {
  const name = hostOf(state)?.name?.trim();
  return name ? name : null;
};

/** Mac wording: "Jam de X" / "Jam de Spotify". */
export const jamTitle = (state: Pick<JamViewState, 'host' | 'members'>, language?: AppLanguage): string => {
  const host = hostNameOf(state);
  return host ? text('jam.live.title', [host], language) : text('jam.live.titleNoHost', [], language);
};
export const badgeLabel = (state: Pick<JamViewState, 'host' | 'members'>, language?: AppLanguage): string => {
  const host = hostNameOf(state);
  return host ? text('jam.badge.label', [host], language) : text('jam.badge.labelNoHost', [], language);
};

export const initialOf = (name: string | null | undefined): string => {
  const first = [...(name?.trim() ?? '')][0];
  return first ? first.toUpperCase() : '?';
};
/** The same name always gets the same colour (port of `JamAvatarView.tint`). */
export function avatarTint(name: string | null | undefined): string {
  let seed = 0;
  for (const char of name ?? '') seed = (seed * 31 + (char.codePointAt(0) ?? 0)) % 360;
  return `hsl(${seed} 42% 40%)`;
}
/** Host first, then me, then the rest. */
export const orderedMembers = (members: JamMember[]): JamMember[] =>
  [...members].sort((a, b) => (a.isHost ? 0 : a.isMe ? 1 : 2) - (b.isHost ? 0 : b.isMe ? 1 : 2));

export const formatMs = (ms: number | null | undefined): string => {
  if (typeof ms !== 'number' || !Number.isFinite(ms) || ms <= 0) return '';
  const total = Math.round(ms / 1000);
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
};
export const formatSecs = (seconds: number | null | undefined): string => formatMs(typeof seconds === 'number' ? seconds * 1000 : null);
/** "3:20" / "1:02:03" → seconds. */
export function parseDuration(value: string | null | undefined): number | null {
  if (!value) return null;
  const parts = value.trim().split(':').map(Number);
  if (!parts.length || parts.some(part => !Number.isFinite(part) || part < 0)) return null;
  return parts.reduce((total, part) => total * 60 + part, 0);
}
export const signedMs = (value: number): string => (value > 0 ? `+${Math.round(value)}` : `${Math.round(value)}`);

export type JamSyncLabel = 'synced' | 'adjusting' | 'paused' | 'hostInactive' | 'searching' | 'noMatch' | 'waiting';
/** Port of the Mac status ladder (`JamPanelSnapshot.make`). */
export function syncLabel(state: JamViewState): JamSyncLabel {
  if (!state.hostActive) return 'hostInactive';
  if (!state.current) return 'waiting';
  if (!state.current.matched) return state.current.status === 'unavailable' ? 'noMatch' : 'searching';
  if (state.paused) return 'paused';
  return state.sync.status === 'adjusting' ? 'adjusting' : 'synced';
}

/** YouTube Music duration minus Spotify duration, in seconds; only a clear gap (>= 2 s) is worth a warning. */
export function durationDelta(track: JamTrackView | null): number | null {
  const secs = track?.matched?.durationSecs, ms = track?.durationMs;
  if (typeof secs !== 'number' || typeof ms !== 'number') return null;
  const delta = secs - ms / 1000;
  return Math.abs(delta) >= 2 ? delta : null;
}

export const matchedFromSong = (song: SongDto): JamMatchedSong => ({
  videoId: song.videoId, title: song.title, artists: song.artists, thumbnail: song.thumbnail, durationSecs: parseDuration(song.duration),
});

// MARK: Strings. The session logic emits `jam.notice.*`, `jam.error.*`, `jam.ended.*` and `jam.exit.*`; most map onto the
// shared (Mac) wording, the rest live under `windows.jam.*`. Unknown keys degrade to a generic string, never to a raw key.
const ALIASES: Record<string, string> = {
  'jam.notice.noHostDevice': 'jam.status.hostInactive',
  'jam.notice.noEquivalent': 'jam.pairing.noMatch',
  'jam.error.notSignedIn': 'jam.failure.noSession',
  'jam.error.pluginMissing': 'jam.failure.pluginMissing',
  'jam.error.linkInvalid': 'jam.failure.invalidLink',
  'jam.error.connection': 'jam.failure.network',
  'jam.error.generic': 'jam.failure.unknown',
  'jam.error.startFailed': 'jam.failure.startFailed',
  'jam.error.authRequired': 'jam.failure.authRequired',
  'jam.error.unavailable': 'jam.failure.unavailable',
  'jam.error.notAllowed': 'jam.failure.notAllowed',
  'jam.error.notFound': 'jam.failure.jamNotFound',
  'jam.error.rateLimited': 'jam.failure.rateLimited',
  'jam.error.rejected': 'jam.failure.rejected',
  'jam.error.unsupported': 'jam.failure.unsupported',
  'jam.ended.host': 'jam.ended.reason.host',
  'jam.ended.removed': 'jam.ended.reason.removed',
  'jam.ended.connection': 'jam.ended.reason.connection',
  'jam.ended.interrupted': 'jam.ended.reason.interrupted',
  'jam.exit.playOther': 'jam.exit.messageGeneric',
};
const FALLBACKS: Array<[prefix: string, key: string]> = [
  ['jam.error.', 'jam.failure.unknown'],
  ['jam.exit.', 'jam.exit.messageGeneric'],
  ['jam.ended.', 'jam.ended.reason.interrupted'],
  ['jam.notice.', 'windows.jam.notice.generic'],
];
/** `{name}` placeholders are positional here: the catalog uses `%@`, filled in the order the values arrive. */
export function jamText(key: string, values?: Record<string, string>, language?: AppLanguage): string {
  const args = Object.values(values ?? {});
  for (const candidate of [ALIASES[key], key, `windows.${key}`]) if (candidate && hasText(candidate)) return text(candidate, args, language);
  const fallback = FALLBACKS.find(([prefix]) => key.startsWith(prefix))?.[1];
  return text(fallback ?? 'windows.jam.notice.generic', [], language);
}
export const noticeText = (notice: JamNoticeView, language?: AppLanguage): string => jamText(notice.key, notice.values, language);
export type NoticeTone = 'success' | 'info' | 'warning';
export function noticeTone(key: string): NoticeTone {
  if (/\.(added|inserted|moved|removed|addedMany|insertedMany)$/.test(key)) return 'success';
  if (key.startsWith('jam.error.') || /noEquivalent|notApplied|rejected|stale|noSpotifyMatch/.test(key)) return 'warning';
  return 'info';
}

// MARK: Queue merge (port of `JamQueueMerge`): the Jam order is the truth, the native queue only holds matched tracks.
export interface JamQueueRow {
  /** Index in `state.queue`. */
  index: number;
  track: JamTrackView;
  /** Row number shown: the playing track is 1, the next one 2. */
  number: number;
  /** The native occurrence mirrored for this row, when the pairing is reliable (activation, context menu). */
  entry: QueueEntryDto | null;
  /** Index of `entry` in `playback.queue.items`. */
  nativeIndex: number | null;
}
export function mergeJamQueue(queue: JamTrackView[], playback: Pick<PlaybackStateDto, 'queue'>): JamQueueRow[] {
  const items = playback.queue.items, current = playback.queue.currentIndex;
  const upcoming = current === null ? [] : items.slice(current + 1);
  const matched = queue.filter(track => track.status === 'matched' && track.matched);
  const paired = matched.length === upcoming.length && matched.every((track, i) => track.matched?.videoId === upcoming[i].videoId);
  let cursor = 0;
  return queue.map((track, index) => {
    const isMatched = track.status === 'matched' && !!track.matched;
    const entry = paired && isMatched ? upcoming[cursor++] : null;
    return { index, track, number: index + 2, entry, nativeIndex: entry ? items.indexOf(entry) : null };
  });
}
export const trackTitle = (track: JamTrackView): string => track.matched?.title || track.title;
export const trackArtists = (track: JamTrackView): string => track.matched?.artists || track.artists;

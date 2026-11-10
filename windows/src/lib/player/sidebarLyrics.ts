import type { PlaybackStateDto } from '../types';
import type { LyricsDto, LyricsState } from './lyrics';

/** Same occurrence identity the Letras tab uses (account + queue entry + generation + video). */
export function lyricsOccurrence(session: number, playback: PlaybackStateDto): string {
  return JSON.stringify([session, playback.queue.items[playback.queue.currentIndex ?? -1]?.entryId, playback.generation, playback.currentTrack?.videoId]);
}
/**
 * The classic (LRC/plain) lyrics only when they belong to the current account, queue entry, generation and video,
 * so a same-video record from another account or occurrence never reaches the sample.
 */
export function currentClassicLyrics(state: LyricsState, playback: PlaybackStateDto, session: number): LyricsDto | null {
  if (!state.lyrics || !state.trackKey || !playback.currentTrack) return null;
  try {
    const [video, generation, scope] = JSON.parse(state.trackKey);
    if (video !== playback.currentTrack.videoId || generation !== playback.generation || typeof scope !== 'string') return null;
    const [account, entry] = JSON.parse(scope);
    if (account !== session || entry !== (playback.queue.items[playback.queue.currentIndex ?? -1]?.entryId ?? null)) return null;
    return state.lyrics;
  } catch { return null; }
}
/** Per-song lyric source chosen in the Letras tab (`lyrics.sources`); the sample honors the same choice. */
export function readLyricSources(storage: Pick<Storage, 'getItem'> | undefined = (() => { try { return globalThis.localStorage; } catch { return undefined; } })()): Record<string, string> {
  try {
    const value = JSON.parse(storage?.getItem('lyrics.sources') ?? '{}');
    return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  } catch { return {}; }
}
/** Keeps the active line centered: the first positioning of each mount/occurrence/layout is immediate (no travel). */
export function lyricsCenterPlan(previous: { occurrence: string; layout: string; centered: boolean } | null, next: { occurrence: string; layout: string }, reducedMotion: boolean): { animate: boolean; centered: boolean } {
  const settled = previous !== null && previous.occurrence === next.occurrence && previous.layout === next.layout && previous.centered;
  return { animate: settled && !reducedMotion, centered: true };
}

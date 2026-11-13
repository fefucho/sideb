// Port of JamMatcher.swift and JamLookup (JamQueueMatching.swift): picks the YouTube Music song
// that corresponds to a Spotify track. Exact sync needs the same recording, so duration closeness
// weighs as much as the names.
import type { JamPluginTrack } from './types';

/** The part of a YouTube Music song the matcher reads (`SongDto` satisfies it). */
export interface MatchSong {
  videoId: string;
  title: string;
  artists: string;
  duration: string | null;
  isVideo?: boolean;
}

export interface JamCandidate<S extends MatchSong = MatchSong> {
  song: S;
  score: number;
  /** YouTube Music duration minus Spotify duration, in seconds. */
  durationDelta: number | null;
  isConfident: boolean;
}

export const CONFIDENT_SCORE = 4;

export function matchQuery(track: Pick<JamPluginTrack, 'title' | 'artists'>): string {
  return [track.title, track.artists[0]].filter((part): part is string => !!part).join(' ');
}

/** Lowercased, accent-free, without bracketed or dash-suffixed version notes. */
export function normalize(value: string): string {
  let text = value.normalize('NFD').replace(/\p{M}+/gu, '').toLowerCase();
  for (const [open, close] of [['(', ')'], ['[', ']']]) {
    for (;;) {
      const start = text.indexOf(open);
      if (start < 0) break;
      const end = text.indexOf(close, start + 1);
      if (end < 0) break;
      text = text.slice(0, start) + text.slice(end + 1);
    }
  }
  const dash = text.indexOf(' - ');
  if (dash >= 0) text = text.slice(0, dash);
  return text.replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

/** `m:ss` or `h:mm:ss` to seconds; `null` for anything else. */
export function durationSeconds(duration: string | null | undefined): number | null {
  if (!duration) return null;
  const parts = duration.split(':');
  if (parts.length > 3 || parts.some(part => !/^\d+(\.\d+)?$/.test(part))) return null;
  return parts.reduce((total, part) => total * 60 + Number(part), 0);
}

export function rankCandidates<S extends MatchSong>(track: JamPluginTrack, candidates: S[]): JamCandidate<S>[] {
  const title = normalize(track.title ?? '');
  const artists = track.artists.map(normalize).filter(artist => artist);
  const wanted = track.durationMs === null || track.durationMs === undefined ? null : track.durationMs / 1000;
  const ranked = candidates.map((song, index) => {
    let score = 0;
    const candidateTitle = normalize(song.title);
    if (title && candidateTitle === title) score += 3;
    else if (title && candidateTitle && (candidateTitle.includes(title) || title.includes(candidateTitle))) score += 1.5;
    const candidateArtists = normalize(song.artists);
    if (artists.some(artist => candidateArtists.includes(artist))) score += 2;
    let delta: number | null = null;
    const actual = durationSeconds(song.duration);
    if (wanted !== null && actual !== null) {
      delta = actual - wanted;
      // The catalog reports whole seconds, so anything within one second is "the same".
      const gap = Math.abs(actual - wanted);
      if (gap < 1.6) score += 2;
      else if (gap < 4) score += 1;
      else if (gap < 10) score += 0.3;
      else score -= 1;
    }
    if (song.isVideo) score -= 1;
    return { index, candidate: { song, score, durationDelta: delta, isConfident: score >= CONFIDENT_SCORE } };
  });
  return ranked.sort((a, b) => b.candidate.score - a.candidate.score || a.index - b.index).map(entry => entry.candidate);
}

/** Outcome of one lookup. Only a search that actually completed can say "no match". */
export type JamLookupResult<S extends MatchSong = MatchSong> =
  | { kind: 'matched'; song: S; score: number }
  /** The search completed and nothing was confident enough. */
  | { kind: 'noMatch'; candidateCount: number; bestScore: number | null }
  /** The search threw (network, rate limit, cancellation, core not ready): nothing is known. */
  | { kind: 'failed'; reason: string };

export type JamSearch<S extends MatchSong = MatchSong> = { ok: true; ranked: JamCandidate<S>[] } | { ok: false; error: unknown };

/** Decides what a finished search means. A thrown error is never a "no match"; an empty successful result is. */
export function lookupResult<S extends MatchSong>(search: JamSearch<S>, override: string | null = null): JamLookupResult<S> {
  if (!search.ok) return { kind: 'failed', reason: errorText(search.error) };
  const best = search.ranked[0];
  if (best && (best.isConfident || override === best.song.videoId)) return { kind: 'matched', song: best.song, score: best.score };
  return { kind: 'noMatch', candidateCount: search.ranked.length, bestScore: best ? best.score : null };
}

export function errorText(error: unknown): string {
  if (error && typeof error === 'object' && 'code' in error && typeof error.code === 'string') return error.code;
  if (error instanceof Error) return error.message;
  return typeof error === 'string' ? error : 'error';
}

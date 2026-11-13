// Lazy matching of Jam tracks to YouTube Music (JamSessionController+Queue.swift). The current
// track is looked up at once; the queue goes through the planner (nearest first, few at a time).
// A failed or throwing search is retried with backoff and never cached as "unavailable".
import type { SongDto } from '../types';
import { lookupResult, matchQuery, rankCandidates, type JamSearch } from './matcher';
import { songToMatched, type JamCore, type MatchingApi, type Matched } from './model';
import { backoffMs, PLANNER, planMatches } from './planner';
import type { JamPluginTrack } from './types';

export function createMatching(core: JamCore): MatchingApi {
  const inFlight = new Set<string>();
  const attempts = new Map<string, number>();
  const retryAt = new Map<string, number>();
  let lastBackground = -Infinity;
  let wake: unknown = null;

  const matchOf = (uri: string): Matched | null => {
    const state = core.d.matches.get(uri);
    return state?.kind === 'matched' ? state.match : null;
  };

  function statusOf(uri: string) {
    const state = core.d.matches.get(uri);
    if (state) return state.kind;
    if (inFlight.has(uri)) return 'searching';
    // Out of attempts: shown as unavailable but never cached, so a resync can try again.
    return (attempts.get(uri) ?? 0) >= PLANNER.maxAttempts ? 'unavailable' : 'pending';
  }

  async function search(track: JamPluginTrack): Promise<JamSearch<SongDto>> {
    if (!track.title) return { ok: true, ranked: [] };
    try {
      const found = await core.raw<SongDto[]>('search_songs', { query: matchQuery(track) });
      return { ok: true, ranked: rankCandidates(track, found ?? []) };
    } catch (error) {
      return { ok: false, error };
    }
  }

  function start(track: JamPluginTrack): void {
    const token = core.d.token;
    const uri = track.uri;
    inFlight.add(uri);
    core.publishTracks();
    void search(track).then(result => {
      if (!core.isCurrent(token)) return;
      inFlight.delete(uri);
      const label = `${track.title ?? uri}`;
      const outcome = lookupResult(result, null);
      switch (outcome.kind) {
        case 'matched':
          core.d.matches.set(uri, { kind: 'matched', match: songToMatched(outcome.song), corrected: false });
          core.note(`match: ${label} -> ${outcome.song.title} (score ${outcome.score.toFixed(1)})`);
          break;
        case 'noMatch':
          core.d.matches.set(uri, { kind: 'unavailable' });
          core.note(`match: ${label} -> no confident equivalent (${outcome.candidateCount} candidates, best ${outcome.bestScore?.toFixed(1) ?? '-'})`);
          break;
        case 'failed': {
          const attempt = (attempts.get(uri) ?? 0) + 1;
          attempts.set(uri, attempt);
          retryAt.set(uri, core.now() + backoffMs(attempt));
          core.note(`match: ${label} -> search error (attempt ${attempt}/${PLANNER.maxAttempts}): ${outcome.reason}`);
          break;
        }
      }
      core.publishTracks();
      core.mirror.onMatch(uri);
      pump();
    });
  }

  function pump(): void {
    if (!core.isLive()) return;
    const now = core.now();
    let wakeAfter: number | null = null;
    const current = core.d.track;
    for (const track of current ? [current, ...core.d.queue] : core.d.queue) {
      const override = core.d.overrides.get(track.uri);
      if (override && !core.d.matches.has(track.uri)) core.d.matches.set(track.uri, { kind: 'matched', match: override, corrected: true });
    }
    // The current track bypasses the pacing: it is what the user is waiting to hear.
    if (current && !core.d.matches.has(current.uri) && !inFlight.has(current.uri) && (attempts.get(current.uri) ?? 0) < PLANNER.maxAttempts) {
      const due = retryAt.get(current.uri);
      if (due === undefined || due <= now) start(current);
      else wakeAfter = due - now;
    }
    const plan = planMatches({
      queue: core.d.queue.map(track => track.uri), settled: new Set(core.d.matches.keys()), inFlight, attempts, retryAt,
      lastBackgroundStart: lastBackground, now
    });
    if (plan.startsBackground) lastBackground = now;
    const byUri = new Map<string, JamPluginTrack>();
    for (const track of core.d.queue) if (!byUri.has(track.uri)) byUri.set(track.uri, track);
    for (const uri of plan.start) {
      const track = byUri.get(uri);
      if (track) start(track);
    }
    if (plan.wakeAfterMs !== null) wakeAfter = Math.min(wakeAfter ?? Infinity, plan.wakeAfterMs);
    if (wake !== null) core.sched.clearTimeout(wake);
    wake = null;
    if (wakeAfter !== null) {
      const token = core.d.token;
      wake = core.sched.setTimeout(() => {
        wake = null;
        if (core.isCurrent(token)) pump();
      }, Math.max(50, wakeAfter));
    }
  }

  return {
    statusOf,
    matchOf,
    pump,
    retryExhausted() {
      for (const [uri, count] of attempts) if (count >= PLANNER.maxAttempts) { attempts.delete(uri); retryAt.delete(uri); }
      pump();
    },
    reset() {
      inFlight.clear();
      attempts.clear();
      retryAt.clear();
      lastBackground = -Infinity;
      if (wake !== null) core.sched.clearTimeout(wake);
      wake = null;
    },
    setCorrected(uri, match) {
      core.d.overrides.set(uri, match);
      core.d.matches.set(uri, { kind: 'matched', match, corrected: true });
    }
  };
}

// Port of JamMatchPlanner (JamQueueMatching.swift): chooses which Jam tracks to look up next. The
// nearest `eagerCount` go as fast as the concurrency allows, the rest one at a time at a low
// steady rate. Pure (times are epoch ms) so the ordering can be tested.

export const PLANNER = {
  eagerCount: 15,
  maxConcurrent: 3,
  /** Minimum gap (ms) between lookups of tracks beyond the eager window. */
  backgroundIntervalMs: 1500,
  maxAttempts: 6
} as const;

/** Wait (ms) after the n-th failed attempt (1-based). */
export function backoffMs(afterAttempt: number): number {
  return [2000, 5000, 15000, 30000, 60000][Math.min(Math.max(afterAttempt, 1), 5) - 1];
}

export interface MatchPlan {
  start: string[];
  /** True when one of `start` is beyond the eager window. */
  startsBackground: boolean;
  /** When to plan again (ms from now) if nothing else triggers it: a retry or the background pace. */
  wakeAfterMs: number | null;
}

export interface MatchPlanInput {
  queue: string[];
  settled: ReadonlySet<string>;
  inFlight: ReadonlySet<string>;
  attempts: ReadonlyMap<string, number>;
  retryAt: ReadonlyMap<string, number>;
  lastBackgroundStart: number;
  now: number;
}

export function planMatches(input: MatchPlanInput): MatchPlan {
  const { queue, settled, inFlight, attempts, retryAt, lastBackgroundStart, now } = input;
  const plan: MatchPlan = { start: [], startsBackground: false, wakeAfterMs: null };
  let free = PLANNER.maxConcurrent - inFlight.size;
  const seen = new Set<string>();
  const wake = (delay: number) => { plan.wakeAfterMs = Math.min(plan.wakeAfterMs ?? delay, Math.max(50, delay)); };
  for (const [position, uri] of queue.entries()) {
    if (free <= 0) break;
    if (seen.has(uri)) continue;
    seen.add(uri);
    if (settled.has(uri) || inFlight.has(uri)) continue;
    if ((attempts.get(uri) ?? 0) >= PLANNER.maxAttempts) continue;
    const due = retryAt.get(uri);
    if (due !== undefined && due > now) { wake(due - now); continue; }
    if (position >= PLANNER.eagerCount) {
      if (plan.startsBackground) break;
      const ready = lastBackgroundStart + PLANNER.backgroundIntervalMs;
      if (ready > now) { wake(ready - now); break; }
      plan.startsBackground = true;
    }
    plan.start.push(uri);
    free -= 1;
  }
  return plan;
}

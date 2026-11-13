// Port of apple/Sources/SideB/Services/Jam/JamSyncEngine.swift.
//
// Pure state machine that decides how to bring the local audio onto the Jam's position. It owns no
// clock and touches no player: every tick receives the measured drift (local minus Jam, seconds),
// a monotonic timestamp (seconds) and whether the audio is really advancing, and returns what the
// caller must do. The shape of a correction is deliberately rigid: a short window after a real
// change, a seek for big gaps, fixed-rate bursts for small ones, then LOCK (hands off) or give up.

/** Every threshold lives here so tuning is a one-place change. */
export const SyncTuning = {
  /** |drift| (s) at or below which the position is considered matched. */
  lockDrift: 0.025,
  /** Residual (s) accepted when the budget is used up. */
  acceptableResidual: 0.2,
  /** |drift| (s) above which a seek is used instead of a rate burst. */
  seekThreshold: 0.25,
  /** Time (s) to wait after a seek before judging the result. */
  seekSettle: 0.8,
  maxSeeksPerWindow: 2,
  /** Fixed rate offset of a burst (0.05 = 0.95x or 1.05x). */
  burstRateDelta: 0.05,
  burstMaxDuration: 3.0,
  burstMinDuration: 0.15,
  /** Time (s) at rate 1.0 after a burst before re-measuring. */
  burstSettle: 0.3,
  maxBurstsPerWindow: 2,
  /** A burst that removes less than this fraction of the drift marks rate correction ineffective. */
  minBurstImprovement: 0.4,
  /** Window budget (s): afterwards the engine finalizes (accept or last seek). */
  windowBudget: 6.0,
  /** Absolute cap (s) of one window; it locks unconditionally here. */
  hardCap: 8.0,
  /** A locked engine reopens only for |drift| (s) above this sustained for `reopenSustain`. */
  reopenDrift: 0.35,
  reopenSustain: 1.5,
  reopenCooldown: 20.0,
  /** Number of drift samples whose median drives decisions. */
  sampleCount: 3,
  /** Learned seek landing bias is clamped to +/- this (s). */
  maxSeekBias: 0.5,
  /** Prior for the seek landing bias (s): a seek tends to land behind, so aim slightly ahead. */
  initialSeekBias: -0.1,
  /** Longest time step (s) a single tick may add to the engine clock. */
  maxStep: 0.5
} as const;

export type SyncAction =
  | { kind: 'none' }
  /** Seek to `target + compensation` (seconds). */
  | { kind: 'seek'; compensation: number }
  /** Set the player rate and leave it unchanged until told otherwise. */
  | { kind: 'setRate'; rate: number }
  /** Rate back to 1.0; stop touching the audio. */
  | { kind: 'lock' };

export type SyncMode = 'locked' | 'measuring' | 'seeking' | 'burst' | 'settling';
export type SyncLockReason = 'converged' | 'accepted' | 'finalSeek' | 'hardCap';

export interface SyncSummary {
  duration: number;
  seeks: number;
  bursts: number;
  residualMs: number;
  reason: SyncLockReason;
  rateIneffective: boolean;
}

export function summaryText(s: SyncSummary): string {
  const sign = s.residualMs >= 0 ? '+' : '-';
  return `${s.duration.toFixed(1)} s, ${s.seeks} seek, ${s.bursts} bursts, residual ${sign}${Math.abs(s.residualMs).toFixed(0)} ms (${s.reason})${s.rateIneffective ? ', rate ineffective' : ''}`;
}

const NONE: SyncAction = { kind: 'none' };

export class JamSyncEngine {
  mode: SyncMode = 'locked';
  lastSummary: SyncSummary | null = null;
  rateIneffective = false;
  /** Set by the tick that reopened a window on its own (sustained drift); cleared on the next tick. */
  didReopen = false;
  seekBias: number = SyncTuning.initialSeekBias;

  private clock = 0;
  private lastNow: number | null = null;
  private samples: number[] = [];
  private windowStart = -Infinity;
  private seeks = 0;
  private bursts = 0;
  private hasLearnedBias = false;
  private itemKey: string | null = null;
  private strayStart: number | null = null;
  private rate = 1;
  private needsRateReset = false;
  private seekUntil = 0;
  private seekCompensation = 0;
  private lockAfterSeek = false;
  private finalSeekDone = false;
  private burstUntil = 0;
  private burstStartAbs = 0;
  private settleUntil = 0;

  get isAdjusting(): boolean { return this.mode !== 'locked'; }

  /** Opens a correction window after a real change (new track, jump, resume, nudge). */
  begin(): void {
    this.mode = 'measuring';
    this.samples = [];
    this.windowStart = this.clock;
    this.seeks = 0;
    this.bursts = 0;
    this.finalSeekDone = false;
    this.lockAfterSeek = false;
    this.strayStart = null;
    if (this.rate !== 1) this.needsRateReset = true;
  }

  /** Forgets the window without a summary (e.g. playback paused). Keeps learned values. */
  cancel(): void {
    this.mode = 'locked';
    this.samples = [];
    this.strayStart = null;
    if (this.rate !== 1) this.needsRateReset = true;
  }

  /** A different item resets the per-item rate verdict. */
  setItem(key: string): void {
    if (key === this.itemKey) return;
    this.itemKey = key;
    this.rateIneffective = false;
  }

  tick(drift: number, now: number, advancing: boolean): SyncAction {
    this.didReopen = false;
    const dt = this.lastNow === null ? 0 : Math.min(Math.max(now - this.lastNow, 0), SyncTuning.maxStep);
    this.lastNow = now;
    // Time that is not audio advancing (buffering, pending seek) neither counts nor decides.
    if (!advancing || !Number.isFinite(drift)) return NONE;
    this.clock += dt;
    this.samples.push(drift);
    if (this.samples.length > SyncTuning.sampleCount) this.samples.splice(0, this.samples.length - SyncTuning.sampleCount);
    if (this.needsRateReset) {
      this.needsRateReset = false;
      this.rate = 1;
      return { kind: 'setRate', rate: 1 };
    }
    return this.mode === 'locked' ? this.tickLocked() : this.tickWindow();
  }

  // MARK: Locked

  private tickLocked(): SyncAction {
    if (this.samples.length < SyncTuning.sampleCount || Math.abs(this.median) <= SyncTuning.reopenDrift) {
      this.strayStart = null;
      return NONE;
    }
    if (this.strayStart === null) this.strayStart = this.clock;
    if (this.clock - this.strayStart >= SyncTuning.reopenSustain && this.clock - this.windowStart >= SyncTuning.reopenCooldown) {
      this.begin();
      this.didReopen = true;
    }
    return NONE;
  }

  // MARK: Window

  private tickWindow(): SyncAction {
    const elapsed = this.clock - this.windowStart;
    if (elapsed >= SyncTuning.hardCap) return this.finish('hardCap');

    switch (this.mode) {
      case 'seeking': {
        if (this.clock < this.seekUntil) return NONE;
        const residual = this.median;
        // Where the seek really landed versus where it was asked to: reused by the next seek.
        const landing = residual - this.seekCompensation;
        const blended = this.hasLearnedBias ? this.seekBias * 0.5 + landing * 0.5 : landing;
        this.seekBias = Math.min(Math.max(blended, -SyncTuning.maxSeekBias), SyncTuning.maxSeekBias);
        this.hasLearnedBias = true;
        if (this.lockAfterSeek) return this.finish('finalSeek');
        this.mode = 'measuring';
        break;
      }
      case 'burst':
        if (!(this.clock >= this.burstUntil || elapsed >= SyncTuning.windowBudget)) return NONE;
        this.mode = 'settling';
        this.settleUntil = this.clock + SyncTuning.burstSettle;
        this.samples = [];
        this.rate = 1;
        return { kind: 'setRate', rate: 1 };
      case 'settling': {
        if (this.clock < this.settleUntil) return NONE;
        const latest = this.samples.at(-1);
        if (latest !== undefined && this.burstStartAbs > 0) {
          const improvement = (this.burstStartAbs - Math.abs(latest)) / this.burstStartAbs;
          if (improvement < SyncTuning.minBurstImprovement) this.rateIneffective = true;
        }
        this.mode = 'measuring';
        break;
      }
      default:
        break;
    }
    return this.measure(elapsed);
  }

  private measure(elapsed: number): SyncAction {
    if (this.samples.length < SyncTuning.sampleCount) return NONE;
    const m = this.median;
    if (Math.abs(m) <= SyncTuning.lockDrift) return this.finish('converged');

    const big = Math.abs(m) > SyncTuning.seekThreshold;
    const exhausted = big ? this.seeks >= SyncTuning.maxSeeksPerWindow
      : this.rateIneffective || this.bursts >= SyncTuning.maxBurstsPerWindow;
    if (elapsed >= SyncTuning.windowBudget || exhausted) {
      if (Math.abs(m) <= SyncTuning.acceptableResidual) return this.finish('accepted');
      if (this.finalSeekDone) return this.finish('accepted');
      this.finalSeekDone = true;
      this.lockAfterSeek = true;
      return this.startSeek();
    }
    if (big) return this.startSeek();
    // Fixed-rate burst: one rate, held until the drift should be gone, never adjusted midway.
    const duration = Math.min(SyncTuning.burstMaxDuration, Math.max(SyncTuning.burstMinDuration, Math.abs(m) / SyncTuning.burstRateDelta));
    this.bursts += 1;
    this.burstStartAbs = Math.abs(m);
    this.burstUntil = this.clock + duration;
    this.mode = 'burst';
    this.rate = m > 0 ? 1 - SyncTuning.burstRateDelta : 1 + SyncTuning.burstRateDelta;
    return { kind: 'setRate', rate: this.rate };
  }

  private startSeek(): SyncAction {
    this.seeks += 1;
    this.seekCompensation = -this.seekBias;
    this.seekUntil = this.clock + SyncTuning.seekSettle;
    this.mode = 'seeking';
    this.samples = [];
    this.rate = 1;
    return { kind: 'seek', compensation: this.seekCompensation };
  }

  private finish(reason: SyncLockReason): SyncAction {
    this.lastSummary = {
      duration: this.clock - this.windowStart, seeks: this.seeks, bursts: this.bursts,
      residualMs: (this.samples.length ? this.median : 0) * 1000, reason, rateIneffective: this.rateIneffective
    };
    this.mode = 'locked';
    this.rate = 1;
    this.samples = [];
    this.strayStart = null;
    this.lockAfterSeek = false;
    return { kind: 'lock' };
  }

  private get median(): number {
    const sorted = [...this.samples].sort((a, b) => a - b);
    return sorted.length ? sorted[Math.floor(sorted.length / 2)] : 0;
  }
}

/** Bounded projection between real libmpv samples; never publishes application state. */
export class KaraokeClock {
  private position = 0;
  private observed = 0;
  private running = false;
  private pending = false;
  private frame: number | null = null;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private listeners = new Set<(ms: number) => boolean | void>();
  private slow = false;
  private lastFrame = -Infinity;
  private boundaries: readonly number[] = [];
  private offset = 0;
  constructor(private now = () => performance.now()) {}
  sample(now = this.now()) {
    // Freeze at the bounded projection when samples stop; never jump backwards to
    // the old anchor when age crosses the stale threshold.
    const age = Math.max(0, now - this.observed);
    return this.position + (this.running && !this.pending ? Math.min(age, 250) : 0);
  }
  observe(position: number, playing: boolean, pending: boolean, _key: string) {
    this.position = Number.isFinite(position) ? Math.max(0, position * 1000) : 0;
    this.observed = this.now(); this.running = playing; this.pending = pending;
    this.pulse();
  }
  setSlow(slow: boolean) { if(this.slow!==slow){this.slow = slow;this.pulse();} }
  /** Document boundaries are prepared once, never inferred from a visual word. */
  setBoundaries(boundaries: readonly number[], offset = 0) {
    this.boundaries = boundaries; this.offset = offset; this.pulse();
  }
  subscribe(listener: (ms: number) => boolean | void) {
    this.listeners.add(listener);
    this.pulse();
    return () => { this.listeners.delete(listener); if (!this.listeners.size) this.stop(); };
  }
  private pulse = () => {
    this.stop();
    const now = this.now();
    const ms = this.sample(now);
    let animate = false;
    for (const listener of this.listeners) animate = listener(ms) || animate;
    if (!this.listeners.size || !this.running || this.pending || typeof document === 'undefined' || document.hidden || now - this.observed >= 250) return;
    if (animate) {
      this.frame = requestAnimationFrame(this.animate);
    } else {
      // A static viewport needs only the next real boundary. New libmpv samples
      // reconcile independently and wake us again; do not poll an idle context.
      const shifted = ms + this.offset;
      let lo = 0, hi = this.boundaries.length;
      while (lo < hi) { const mid = (lo + hi) >>> 1; if (this.boundaries[mid] <= shifted) lo = mid + 1; else hi = mid; }
      const delay = (this.boundaries[lo] ?? Infinity) - shifted;
      const remaining = 250 - Math.max(0, now - this.observed);
      if (delay <= remaining) this.timer = setTimeout(this.pulse, Math.max(1, delay));
    }
  };
  private animate = () => {
    if (this.slow && this.now() - this.lastFrame < 1000 / 30) {
      this.frame = requestAnimationFrame(this.animate); return;
    }
    this.lastFrame = this.now(); this.pulse();
  };
  private stop() {
    if (this.frame !== null) cancelAnimationFrame(this.frame);
    if (this.timer !== null) clearTimeout(this.timer);
    this.frame = null; this.timer = null;
  }
  dispose() { this.stop(); this.listeners.clear(); }
}

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
  setSlow(slow: boolean) { this.slow = slow; }
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
    if (!this.listeners.size || !this.running || this.pending || typeof document === 'undefined' || document.hidden || now - this.observed >= 400) return;
    if (animate) {
      this.frame = requestAnimationFrame(() => {
        if (this.slow && this.now() - this.lastFrame < 32) { this.frame = requestAnimationFrame(this.pulse); return; }
        this.lastFrame = this.now(); this.pulse();
      });
    } else {
      // Keep real short-word/gap boundaries even without an active visible sweep.
      this.timer = setTimeout(this.pulse, 16);
    }
  };
  private stop() {
    if (this.frame !== null) cancelAnimationFrame(this.frame);
    if (this.timer !== null) clearTimeout(this.timer);
    this.frame = null; this.timer = null;
  }
  dispose() { this.stop(); this.listeners.clear(); }
}

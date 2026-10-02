interface ScrollContainer { scrollTop: number; scrollHeight: number; clientHeight: number }
interface AnimationFrames {
  request: (callback: FrameRequestCallback) => number;
  cancel: (id: number) => void;
}

// macOS centerCurrentLine uses spring(response: 0.65, dampingFraction: 0.94).
const response = 650;
const damping = 0.94;
const frequency = 2 * Math.PI / (response / 1000);
const dampedFrequency = frequency * Math.sqrt(1 - damping * damping);
function springProgress(milliseconds: number): number {
  const seconds = milliseconds / 1000;
  return 1 - Math.exp(-damping * frequency * seconds)
    * (Math.cos(dampedFrequency * seconds)
      + damping / Math.sqrt(1 - damping * damping) * Math.sin(dampedFrequency * seconds));
}
const finalProgress = springProgress(response);

/** Animates only the lyric container, with cancellable timing independent of WebView2. */
export class LyricScroller {
  private frame: number | null = null;
  private revision = 0;

  constructor(private frames: AnimationFrames = {
    request: callback => requestAnimationFrame(callback),
    cancel: id => cancelAnimationFrame(id),
  }) {}

  cancel(): void {
    ++this.revision;
    if (this.frame !== null) this.frames.cancel(this.frame);
    this.frame = null;
  }

  center(container: ScrollContainer, requestedTop: number, animate: boolean): void {
    this.cancel();
    const target = Math.max(0, Math.min(requestedTop, Math.max(0, container.scrollHeight - container.clientHeight)));
    const from = container.scrollTop;
    if (!animate || Math.abs(target - from) < 0.5) { container.scrollTop = target; return; }
    const revision = this.revision;
    let started: number | null = null;
    const step: FrameRequestCallback = timestamp => {
      if (revision !== this.revision) return;
      started ??= timestamp;
      const elapsed = Math.min(response, Math.max(0, timestamp - started));
      container.scrollTop = from + (target - from) * springProgress(elapsed) / finalProgress;
      if (elapsed < response) this.frame = this.frames.request(step);
      else { container.scrollTop = target; this.frame = null; }
    };
    this.frame = this.frames.request(step);
  }
}

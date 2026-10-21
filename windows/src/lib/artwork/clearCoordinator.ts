export type AnimatedArtworkRelease = () => Promise<void>;

/** Keeps active WebView file sources leased until every registered player has removed them. */
export class AnimatedArtworkClearCoordinator {
  private readonly releases = new Set<AnimatedArtworkRelease>();
  private readonly pendingReleases = new Set<Promise<void>>();
  private active: Promise<number> | null = null;
  clearing = false;

  register(release: AnimatedArtworkRelease) {
    this.releases.add(release);
    // A consumer mounted after the snapshot must inherit the clear block.
    if (this.clearing) this.releaseDuringClear(release);
    return () => this.releases.delete(release);
  }

  private releaseDuringClear(release: AnimatedArtworkRelease) {
    // Call synchronously so a new consumer is blocked before its first effect.
    let operation: Promise<void>;
    try { operation = Promise.resolve(release()); } catch (error) { operation = Promise.reject(error); }
    this.pendingReleases.add(operation);
    // Keep rejection handled while the clear operation drains all releases.
    void operation.catch(() => {});
  }

  clear(clearFiles: () => Promise<number>): Promise<number> {
    if (this.active) return this.active;
    this.clearing = true;
    this.active = (async () => {
      for (const release of this.releases) this.releaseDuringClear(release);
      let failure: unknown;
      while (this.pendingReleases.size) {
        const batch = [...this.pendingReleases];
        const results = await Promise.allSettled(batch);
        for (const operation of batch) this.pendingReleases.delete(operation);
        for (const result of results) if (result.status === 'rejected') failure ??= result.reason;
      }
      if (failure !== undefined) throw failure;
      return clearFiles();
    })().finally(() => { this.active = null; this.clearing = false; });
    return this.active;
  }
}

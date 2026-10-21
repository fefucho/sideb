/** One fullscreen consumer. All asynchronous work belongs to a captured lease, never a global pending slot. */
export class AnimatedArtworkController<Request, Asset> {
  private key = '';
  private metadataKey = '';
  private request: Request | null = null;
  private canPrepare = false;
  private attempted = false;
  private blocked = false;
  private disposed = false;
  private timer: ReturnType<typeof setTimeout> | undefined;
  private idleTimer: ReturnType<typeof setTimeout> | undefined;
  private lease: { id: string; job: Promise<Asset | null> } | null = null;
  private barrier: Promise<void> = Promise.resolve();
  private asset: Asset | null = null;
  constructor(private readonly deps: {
    prepare: (request: Request, id: string) => Promise<Asset | null>;
    cancel: (id: string) => Promise<void>;
    publish: (asset: Asset | null, id: string | null) => void;
    detach: () => Promise<void>;
    id: () => string;
    debounceMs?: number;
    idleMs?: number;
    isClearing?: () => boolean;
  }) {}

  update(key: string, request: Request | null, enabled: boolean, canPrepare: boolean, metadataKey = key) {
    if (this.disposed) return;
    if (key !== this.key || (!this.asset && metadataKey !== this.metadataKey && !this.blocked)) {
      const changedAlbum = key !== this.key;
      this.key = key; this.attempted = false;
      if (changedAlbum) this.blocked = false;
      void this.release().catch(() => {});
    }
    this.metadataKey = metadataKey;
    this.request = request; this.canPrepare = enabled && canPrepare;
    if (this.deps.isClearing?.()) { void this.clear().catch(() => {}); return; }
    if (!enabled) { this.attempted = false; void this.release().catch(() => {}); return; }
    if (!this.canPrepare) {
      this.stopTimer();
      if (this.asset && this.idleTimer === undefined) {
        this.idleTimer = setTimeout(() => {
          this.idleTimer = undefined;
          this.attempted = false;
          void this.release().catch(() => {});
        }, this.deps.idleMs ?? 30_000);
      }
      if (this.lease && !this.asset) { this.attempted = false; void this.release().catch(() => {}); }
      return;
    }
    this.stopIdleTimer();
    this.schedule();
  }

  private stopIdleTimer() { if (this.idleTimer !== undefined) clearTimeout(this.idleTimer); this.idleTimer = undefined; }
  private stopTimer() { if (this.timer !== undefined) clearTimeout(this.timer); this.timer = undefined; }
  private schedule() {
    if (this.disposed || this.blocked || this.deps.isClearing?.() || !this.canPrepare || !this.request || this.attempted || this.lease || this.timer !== undefined) return;
    const key = this.key;
    this.timer = setTimeout(() => {
      this.timer = undefined;
      void this.barrier.then(() => {
        if (this.disposed || key !== this.key || this.blocked || this.deps.isClearing?.() || !this.canPrepare || !this.request || this.attempted || this.lease) return;
        this.attempted = true;
        const id = this.deps.id();
        const job = this.deps.prepare(this.request, id);
        const lease = { id, job }; this.lease = lease;
        void job.then(asset => {
          if (this.lease !== lease || this.disposed || this.blocked) return;
          this.asset = asset;
          if (asset) this.deps.publish(asset, id);
          else void this.release().catch(() => {});
        }).catch(() => { if (this.lease === lease) void this.release().catch(() => {}); });
      });
    }, this.deps.debounceMs ?? 300);
  }

  /** Detach before releasing an open file; cold cancellation is immediate and awaited by clear. */
  private release(): Promise<void> {
    this.stopTimer(); this.stopIdleTimer();
    const lease = this.lease; const hadAsset = this.asset !== null;
    this.lease = null; this.asset = null;
    this.deps.publish(null, null);
    const detached = this.deps.detach();
    const cancelled = lease && !hadAsset ? this.deps.cancel(lease.id) : null;
    const cleanup = async () => {
      await detached;
      if (lease) {
        if (cancelled) await cancelled;
        else await this.deps.cancel(lease.id);
        await lease.job.catch(() => null);
      }
    };
    const operation = Promise.all([this.barrier, cleanup()]).then(() => {});
    this.barrier = operation.catch(() => {});
    return operation;
  }
  fail() { this.attempted = true; return this.release(); }
  clear() { this.blocked = true; return this.release(); }
  dispose() { this.disposed = true; return this.release(); }
}

import type { PlaybackTrackDto } from '../types';
import { emptyGeniusState, type GeniusState, type GeniusTrack, type GeniusResolution, type GeniusCandidate, type GeniusAnnotations, type GeniusLyrics, type GeniusMetrics } from './types';
type Rpc = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
type Preferences = Pick<Storage, 'getItem' | 'setItem'>;

/** Requests are logically cancelled per track/session and per operation. Native HTTP stays under the shared core rate gate. */
export class GeniusController {
  private state = emptyGeniusState();
  private track: GeniusTrack | null = null;
  private epoch = 0;
  private tokens = new Map<string, number>();
  private disposed = false;
  private opened = false;
  private playbackSeen = false;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private cacheTask: Promise<void> = Promise.resolve();
  private annotationTask: Promise<void> = Promise.resolve();
  private failedAnnotationPage: number | null = null;
  // Empty results and failed attempts are terminal until an explicit retry or a new identity.
  private resolutionAttempted = false;
  private lyricsAttempted = false;
  private annotationsAttempted = false;
  private lyricsFailed = false;
  constructor(private rpc: Rpc, private publish: (state: GeniusState) => void, private preferences?: Preferences) {
    try { this.state.automaticFetch = preferences?.getItem('sideb.genius.auto.v1') === 'true'; this.state.diagnostics = preferences?.getItem('sideb.genius.diagnostics.v1') === 'true'; } catch { /* Optional preference storage. */ }
    this.emit();
  }
  get snapshot(): GeniusState { return structuredClone(this.state); }
  private emit(): void { if (!this.disposed) this.publish(this.snapshot); }
  private start(channel: string): () => boolean {
    const epoch = this.epoch; const token = (this.tokens.get(channel) ?? 0) + 1; this.tokens.set(channel, token);
    return () => !this.disposed && this.epoch === epoch && this.tokens.get(channel) === token;
  }
  private error(key = 'genius.unavailable'): void { this.state.error = { key, args: [] }; }
  setTrack(track: PlaybackTrackDto | null, generation: number, session: string | number = 0): void {
    const key = track ? JSON.stringify([session, generation, track.videoId, track.title, track.artists, track.album]) : null;
    if (this.state.trackKey === key || this.disposed) return;
    this.reset(); this.state.trackKey = key;
    this.track = track ? { videoId: track.videoId, title: track.title, artists: track.artists, album: track.album ?? null, durationSeconds: track.duration && Number.isFinite(track.duration) ? Math.max(0, Math.round(track.duration)) : null, isUpload: 'isUpload' in track && track.isUpload === true } : null;
    this.emit();
    if (this.track) this.cacheTask = this.probeCache();
  }
  private async probeCache(): Promise<void> {
    const valid = this.start('cache'); const track = this.track;
    try {
      const cached = await this.rpc<GeniusResolution | null>('genius_cached', { track });
      if (!valid() || this.state.resolution || !cached) return;
      this.apply(cached);
      await this.contents(true, false);
    } catch { /* A cache miss/unavailable cache must not initiate network or expose an error. */ }
  }
  playbackStarted(): void {
    if (this.playbackSeen) return; this.playbackSeen = true;
    if (!this.state.automaticFetch || this.opened) return;
    this.timer = setTimeout(() => { this.timer = null; void this.resolve(false); }, 1000);
  }
  async ensureNow(): Promise<void> {
    this.opened = true; if (this.timer) clearTimeout(this.timer); this.timer = null;
    const epoch = this.epoch; await this.cacheTask;
    if (epoch !== this.epoch || this.disposed) return;
    if (!this.state.resolution) await this.resolve(false);
    else if (this.state.resolution.song) await this.contents(false, false);
  }
  async refresh(): Promise<void> { await this.resolve(true); }
  private async resolve(force: boolean): Promise<void> {
    if (!this.track || this.disposed) return;
    const epoch = this.epoch;
    if (!force) await this.cacheTask;
    if (epoch !== this.epoch || !this.track || this.disposed) return;
    if (!force && (this.resolutionAttempted || this.state.phase === 'loading')) return;
    this.resolutionAttempted = true;
    const valid = this.start('match'); const track = this.track; this.tokens.set('cache', (this.tokens.get('cache') ?? 0) + 1);
    if (!this.state.resolution) this.state.phase = 'loading'; this.state.error = null; this.emit();
    try {
      const resolution = await this.rpc<GeniusResolution>('genius_resolve', { track, force });
      if (!valid()) return; this.apply(resolution); await this.contents(false, force);
    } catch { if (valid()) { if (!this.state.resolution) this.state.phase = 'error'; this.error(); this.emit(); } }
  }
  private apply(resolution: GeniusResolution): void {
    if (this.state.resolution?.song?.id !== resolution.song?.id) {
      for (const channel of ['annotations', 'lyrics']) this.tokens.set(channel, (this.tokens.get(channel) ?? 0) + 1);
      this.state.annotations = []; this.state.lyrics = []; this.state.nextPage = null;
      this.state.loadingAnnotations = false; this.state.loadingLyrics = false;
      this.failedAnnotationPage = null;
      this.lyricsAttempted = false; this.annotationsAttempted = false; this.lyricsFailed = false;
    }
    this.state.resolution = resolution; this.state.phase = resolution.status; this.state.error = null;
    if (resolution.status === 'matched') { this.tokens.set('report', (this.tokens.get('report') ?? 0) + 1); this.state.reporting = false; this.state.reportSaved = false; }
    this.emit();
  }
  async search(query: string): Promise<void> {
    if (!query.trim() || !this.track) return;
    const valid = this.start('search'); this.state.searching = true; this.state.error = null; this.emit();
    try { const items = await this.rpc<GeniusCandidate[]>('genius_search', { query: query.trim() }); if (valid()) this.state.searchResults = items; }
    catch { if (valid()) this.error(); }
    finally { if (valid()) { this.state.searching = false; this.emit(); } }
  }
  async choose(candidate: GeniusCandidate): Promise<void> {
    if (!this.track) return;
    const valid = this.start('match'); this.tokens.set('cache', (this.tokens.get('cache') ?? 0) + 1);
    const track = this.track;
    try { const result = await this.rpc<GeniusResolution>('genius_choose', { track, songId: candidate.id }); if (!valid()) return; this.apply(result); this.state.searchResults = []; await this.contents(false, false); }
    catch { if (valid()) { this.error(); this.emit(); } }
  }
  async clearChoice(): Promise<void> {
    if (!this.track) return;
    const valid = this.start('match'); const track = this.track;
    try { await this.rpc('genius_clear_choice', { track }); if (!valid()) return;
      for (const channel of ['cache', 'annotations', 'lyrics', 'search']) this.tokens.set(channel, (this.tokens.get(channel) ?? 0) + 1);
      this.state.resolution = null; this.state.annotations = []; this.state.lyrics = []; this.state.nextPage = null; this.state.phase = 'idle'; this.state.loadingAnnotations = false; this.state.loadingLyrics = false; this.state.searching = false; this.emit(); await this.resolve(true); }
    catch { if (valid()) { this.error(); this.emit(); } }
  }
  private async contents(cached: boolean, force: boolean): Promise<void> {
    const song = this.state.resolution?.song; if (!song) return;
    if (force) {
      for (const channel of ['annotations', 'lyrics']) this.tokens.set(channel, (this.tokens.get(channel) ?? 0) + 1);
      this.state.loadingAnnotations = false; this.state.loadingLyrics = false;
      this.lyricsAttempted = false; this.annotationsAttempted = false; this.lyricsFailed = false; this.failedAnnotationPage = null;
    }
    const annotations = this.state.loadingAnnotations ? this.annotationTask : (this.annotationTask = this.loadAnnotations(cached, force));
    await Promise.allSettled([annotations, this.loadLyrics(cached, force)]);
  }
  private async loadLyrics(cached: boolean, force: boolean): Promise<void> {
    const song = this.state.resolution?.song; if (!song || (!cached && !song.url) || this.state.loadingLyrics || (!force && this.lyricsAttempted)) return;
    if (!cached) this.lyricsAttempted = true;
    this.lyricsFailed = false;
    const valid = this.start('lyrics'); this.state.loadingLyrics = !cached; this.emit();
    try { const result = await this.rpc<GeniusLyrics | null>('genius_lyrics', { songId: song.id, songUrl: song.url, force, cached }); if (valid() && result) { this.lyricsAttempted = true; this.state.lyrics = result.lines; } }
    catch { if (valid() && !cached) { this.lyricsFailed = true; this.error(); } }
    finally { if (valid()) { this.state.loadingLyrics = false; this.emit(); } }
  }
  private async loadAnnotations(cached: boolean, force: boolean, page = 1): Promise<void> {
    const song = this.state.resolution?.song; if (!song || this.state.loadingAnnotations || (page === 1 && !force && this.annotationsAttempted)) return;
    if (!cached && page === 1) this.annotationsAttempted = true;
    const valid = this.start('annotations'); this.state.loadingAnnotations = !cached; this.emit();
    try {
      const result = await this.rpc<GeniusAnnotations | null>('genius_annotations', { songId: song.id, page, force, cached });
      if (valid() && result) { if (page === 1) this.annotationsAttempted = true; this.failedAnnotationPage = null; const items = page === 1 ? [] : this.state.annotations; const seen = new Set(items.map(x => x.id)); this.state.annotations = [...items, ...result.items.filter(x => { if (seen.has(x.id)) return false; seen.add(x.id); return true; })]; this.state.nextPage = result.nextPage; }
    } catch { if (valid() && !cached) { this.failedAnnotationPage = page; this.error(); } }
    finally { if (valid()) { this.state.loadingAnnotations = false; this.emit(); } }
  }
  async loadMoreAnnotations(): Promise<void> {
    if (this.state.loadingAnnotations) { await this.annotationTask; return; }
    if (this.state.nextPage) await (this.annotationTask = this.loadAnnotations(false, false, this.state.nextPage));
  }
  async ensureAnnotation(referentId: number): Promise<void> {
    const epoch = this.epoch; const songId = this.state.resolution?.song?.id;
    await this.annotationTask;
    if (epoch !== this.epoch || songId !== this.state.resolution?.song?.id || this.disposed) return;
    const seen = new Set<number>();
    while (this.state.nextPage && !this.state.annotations.some(a => a.referentId === referentId || a.id === referentId)) {
      if (epoch !== this.epoch || songId !== this.state.resolution?.song?.id || this.disposed || this.state.loadingAnnotations || seen.has(this.state.nextPage)) return;
      seen.add(this.state.nextPage); await this.loadMoreAnnotations();
      if (this.state.error) return;
    }
  }
  async retryContents(): Promise<void> {
    this.state.error = null;
    if (!this.state.resolution?.song) { await this.resolve(true); return; }
    if (this.lyricsFailed || !this.state.lyrics.length) { this.lyricsAttempted = false; this.lyricsFailed = false; }
    if (this.failedAnnotationPage !== null && this.failedAnnotationPage > 1) await (this.annotationTask = this.loadAnnotations(false, false, this.failedAnnotationPage));
    else if (this.failedAnnotationPage === 1 || !this.state.annotations.length) this.annotationsAttempted = false;
    await this.contents(false, false);
  }
  /** Aggregate counters only. Reading diagnostics never resolves a song or starts provider HTTP. */
  async getMetrics(): Promise<GeniusMetrics | null> {
    const valid = this.start('metrics');
    try { const metrics = await this.rpc<GeniusMetrics>('genius_metrics'); return valid() ? metrics : null; }
    catch { return null; }
  }
  async reportCurrentMiss(): Promise<void> {
    if (!this.track || this.state.reporting || this.state.reportSaved || !['ambiguous', 'notFound'].includes(this.state.phase)) return;
    const valid = this.start('report'); const track = this.track; const status = this.state.phase; const candidateIds = this.state.resolution?.candidates.map(x => x.id) ?? [];
    this.state.reporting = true; this.state.error = null; this.emit();
    try { await this.rpc('genius_report_miss', { track, status, candidateIds }); if (valid()) this.state.reportSaved = true; }
    catch { if (valid()) this.error('genius.error.saveTrack'); }
    finally { if (valid()) { this.state.reporting = false; this.emit(); } }
  }
  setAutomaticFetch(enabled: boolean): void {
    this.state.automaticFetch = enabled; try { this.preferences?.setItem('sideb.genius.auto.v1', String(enabled)); } catch { /* Session preference remains valid. */ }
    if (!enabled && this.timer) { clearTimeout(this.timer); this.timer = null; } this.emit();
    if (enabled && this.playbackSeen) void this.ensureNow();
  }
  setDiagnostics(enabled: boolean): void { this.state.diagnostics = enabled; try { this.preferences?.setItem('sideb.genius.diagnostics.v1', String(enabled)); } catch { /* Optional storage. */ } this.emit(); }
  reset(): void {
    ++this.epoch; this.tokens.clear(); if (this.timer) clearTimeout(this.timer); this.timer = null;
    const { automaticFetch, diagnostics } = this.state; this.state = { ...emptyGeniusState(), automaticFetch, diagnostics };
    this.resolutionAttempted = false; this.lyricsAttempted = false; this.annotationsAttempted = false; this.lyricsFailed = false;
    this.track = null; this.opened = false; this.playbackSeen = false; this.cacheTask = Promise.resolve(); this.annotationTask = Promise.resolve(); this.failedAnnotationPage = null; this.emit();
  }
  dispose(): void { this.reset(); this.disposed = true; }
}

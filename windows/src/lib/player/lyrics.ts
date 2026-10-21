import type { PlaybackTrackDto } from '../types';

export interface LyricLineDto { timeMs: number | null; endTimeMs: number | null; text: string }
export interface LyricsDto { provider: string; isSynced: boolean; lines: LyricLineDto[] }
export interface LyricsState {
  status: 'idle' | 'loading' | 'ready' | 'empty' | 'error';
  trackKey: string | null;
  lyrics: LyricsDto | null;
  error: string | null;
}
type LyricsRpc = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
export const emptyLyricsState = (): LyricsState => ({ status: 'idle', trackKey: null, lyrics: null, error: null });

/** Mirrors macOS LyricTiming, including untimed lines and unsorted timestamps. */
export function activeLyricIndex(lyrics: LyricsDto, seconds: number): number | null {
  if (!lyrics.isSynced || !Number.isFinite(seconds)) return null;
  const time = Math.max(0, seconds) * 1000;
  let first: { index: number; start: number } | null = null;
  let active: { index: number; start: number } | null = null;
  for (const [index, line] of lyrics.lines.entries()) {
    const start = line.timeMs;
    if (start === null || !Number.isFinite(start) || start < 0) continue;
    if (first === null || start < first.start) first = { index, start };
    if (start <= time && (active === null || start >= active.start)) active = { index, start };
  }
  return (active ?? first)?.index ?? null;
}

export function lyricSeekSeconds(line: LyricLineDto, duration?: number | null, offsetMs = 0): number | null {
  if (line.timeMs === null || !Number.isFinite(line.timeMs) || line.timeMs < 0 || !Number.isFinite(offsetMs)) return null;
  const target = Math.max(0, (line.timeMs - offsetMs) / 1000);
  return typeof duration === 'number' && Number.isFinite(duration) && duration > 0 ? Math.min(duration, target) : target;
}

/** Track generations invalidate pending lyrics without touching audio or queue state. */
export class LyricsController {
  private state = emptyLyricsState();
  private track: PlaybackTrackDto | null = null;
  private duration: number | null = null;
  private revision = 0;
  private disposed = false;
  private signature: string | null = null;

  constructor(private rpc: LyricsRpc, private publish: (state: LyricsState) => void) { this.emit(); }
  get snapshot(): LyricsState {
    return { ...this.state, lyrics: this.state.lyrics ? { ...this.state.lyrics, lines: this.state.lyrics.lines.map(line => ({ ...line })) } : null };
  }
  private emit() { if (!this.disposed) this.publish(this.snapshot); }

  setTrack(track: PlaybackTrackDto | null, generation: number, duration?: number, occurrence?: string): void {
    if (this.disposed) return;
    const key = track ? JSON.stringify(occurrence === undefined ? [track.videoId, generation] : [track.videoId, generation, occurrence]) : null;
    this.track = track ? { ...track } : null;
    const candidate = typeof duration === 'number' && Number.isFinite(duration) && duration > 0 ? duration : track?.duration;
    this.duration = candidate && Number.isFinite(candidate) && candidate > 0 ? candidate : null;
    const signature = track ? JSON.stringify([track.title, track.artists, track.album ?? null, this.duration === null ? null : Math.round(this.duration)]) : null;
    if (this.state.trackKey === key) {
      if (signature !== this.signature) {
        this.signature = signature;
        if (track) void this.load();
      }
      return;
    }
    this.signature = signature;
    ++this.revision;
    this.state = { ...emptyLyricsState(), trackKey: key };
    if (track) void this.load(); else this.emit();
  }

  async retry(): Promise<void> { if (!this.disposed && this.track) await this.load(); }
  reset(): void {
    ++this.revision;
    this.track = null;
    this.duration = null;
    this.signature = null;
    this.state = emptyLyricsState();
    this.emit();
  }
  dispose(): void { this.reset(); this.disposed = true; }

  private async load(): Promise<void> {
    const track = this.track;
    if (!track || this.disposed) return;
    const revision = ++this.revision;
    const key = this.state.trackKey;
    const previous = this.state.lyrics;
    this.state = { status: 'loading', trackKey: key, lyrics: previous, error: null };
    this.emit();
    try {
      const lyrics = await this.rpc<LyricsDto | null>('get_lyrics', {
        videoId: track.videoId, title: track.title, artists: track.artists,
        album: track.album ?? null, duration: this.duration,
      });
      if (revision !== this.revision || this.disposed) return;
      const visible = lyrics?.lines.length ? lyrics : previous;
      this.state = { status: visible?.lines.length ? 'ready' : 'empty', trackKey: key, lyrics: visible, error: null };
    } catch (error) {
      if (revision !== this.revision || this.disposed) return;
      const message = error && typeof error === 'object' && 'message' in error && typeof error.message === 'string'
        ? error.message : 'No se pudieron cargar las letras. Comprobá la conexión e intentá de nuevo.';
      this.state = { status: 'error', trackKey: key, lyrics: previous, error: message };
    }
    this.emit();
  }
}

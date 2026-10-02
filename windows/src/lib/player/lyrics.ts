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

export function lyricSeekSeconds(line: LyricLineDto, duration: number): number | null {
  if (line.timeMs === null || !Number.isFinite(line.timeMs) || !Number.isFinite(duration) || duration <= 0) return null;
  return Math.min(duration, Math.max(0, line.timeMs / 1000));
}

/** Track generations invalidate pending lyrics without touching audio or queue state. */
export class LyricsController {
  private state = emptyLyricsState();
  private track: PlaybackTrackDto | null = null;
  private duration: number | null = null;
  private revision = 0;
  private disposed = false;

  constructor(private rpc: LyricsRpc, private publish: (state: LyricsState) => void) { this.emit(); }
  get snapshot(): LyricsState {
    return { ...this.state, lyrics: this.state.lyrics ? { ...this.state.lyrics, lines: this.state.lyrics.lines.map(line => ({ ...line })) } : null };
  }
  private emit() { if (!this.disposed) this.publish(this.snapshot); }

  setTrack(track: PlaybackTrackDto | null, generation: number, duration?: number): void {
    if (this.disposed) return;
    const key = track ? JSON.stringify([track.videoId, generation]) : null;
    this.track = track ? { ...track } : null;
    const candidate = duration && duration > 0 ? duration : track?.duration;
    this.duration = candidate && Number.isFinite(candidate) && candidate > 0 ? candidate : null;
    if (this.state.trackKey === key) return;
    ++this.revision;
    this.state = { ...emptyLyricsState(), trackKey: key };
    if (track) void this.load(); else this.emit();
  }

  async retry(): Promise<void> { if (!this.disposed && this.track) await this.load(); }
  reset(): void {
    ++this.revision;
    this.track = null;
    this.duration = null;
    this.state = emptyLyricsState();
    this.emit();
  }
  dispose(): void { this.reset(); this.disposed = true; }

  private async load(): Promise<void> {
    const track = this.track;
    if (!track || this.disposed) return;
    const revision = ++this.revision;
    const key = this.state.trackKey;
    this.state = { status: 'loading', trackKey: key, lyrics: null, error: null };
    this.emit();
    try {
      const lyrics = await this.rpc<LyricsDto | null>('get_lyrics', {
        videoId: track.videoId, title: track.title, artists: track.artists,
        album: track.album ?? null, duration: this.duration,
      });
      if (revision !== this.revision || this.disposed) return;
      this.state = { status: lyrics?.lines.length ? 'ready' : 'empty', trackKey: key, lyrics, error: null };
    } catch (error) {
      if (revision !== this.revision || this.disposed) return;
      const message = error && typeof error === 'object' && 'message' in error && typeof error.message === 'string'
        ? error.message : 'No se pudieron cargar las letras. Comprobá la conexión e intentá de nuevo.';
      this.state = { status: 'error', trackKey: key, lyrics: null, error: message };
    }
    this.emit();
  }
}

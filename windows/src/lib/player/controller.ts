import type { PlaybackProgressDto, PlaybackStateDto, PlaybackTrackDto, QueueEntryDto, QueueStateDto, SongDto } from '../types';

export type PlayerRpc = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
export type PlayerUnlisten = () => void | Promise<void>;
export type PlayerListen = <T>(event: string, handler: (event: { payload: T }) => void) => Promise<PlayerUnlisten>;
export type PlaybackSnapshot = { state: PlaybackStateDto; confirmedVolume: number; error: string | null };
export type PlayerSong = Pick<SongDto, 'videoId' | 'title' | 'artists' | 'thumbnail' | 'duration'> & Partial<Pick<SongDto, 'artistId' | 'albumId' | 'album' | 'artistRuns' | 'isUpload'>> | PlaybackTrackDto | QueueEntryDto;
export type PlaybackQueueSource = { kind: string; id: string | null; title: string | null };
export interface PlaySongOptions {
  queueItems?: PlayerSong[];
  queueIndex?: number | null;
  queueSource?: PlaybackQueueSource | null;
  preserveQueue?: boolean;
  shuffle?: boolean;
}

export function collectionEntryId(source: PlaybackQueueSource, song: SongDto, index: number) {
  const id = source.kind === 'playlist' ? (source.id ?? '').trim().replace(/^VL/, '') : source.id ?? '';
  const occurrence = source.kind === 'history' && song.historyOccurrenceId
    ? `listen:${song.historyOccurrenceId}` : song.setVideoId ?? `index:${index}`;
  return ['collection', source.kind, id, occurrence, song.videoId].map(encodeURIComponent).join('|');
}

/** Sends canonical occurrence order to Rust; shuffle selects only the initial track here. */
export function prepareCollectionPlayback(items: SongDto[], selectedIndex: number, source: PlaybackQueueSource,
  shuffle = false, fallbackThumbnail: string | null = null, fallbackArtist = '', random = Math.random): { song: QueueEntryDto; options: PlaySongOptions } {
  const indexed = items.map((song, originalIndex) => ({ song, originalIndex })).filter(({ song }) => song.videoId.trim());
  const entries = indexed.map(({ song, originalIndex }, index) => ({ ...entryFor({ ...song,
    artists: song.artists || fallbackArtist, thumbnail: song.thumbnail || fallbackThumbnail }, index),
    entryId: collectionEntryId(source, song, originalIndex) }));
  if (!entries.length) throw new Error('No hay canciones disponibles para reproducir.');
  const selected = indexed.findIndex(entry => entry.originalIndex === selectedIndex);
  const queueIndex = shuffle ? Math.floor(random() * entries.length) : Math.max(0, selected);
  return { song: entries[queueIndex], options: { queueItems: entries, queueIndex, queueSource: source, shuffle } };
}

const audioIdle = Promise.resolve();
const emptyQueue = (): QueueStateDto => ({ items: [], currentIndex: null, source: null, revision: 0 });
export function emptyPlaybackData(): PlaybackStateDto {
  return { isPlaying: false, isLoading: false, isEnded: false, isShuffle: false, isRepeat: false, position: 0, duration: 0, volume: 100,
    exponentialVolume: false, currentTrack: null, error: null, generation: 0, queue: emptyQueue() };
}

/** Matches the duration parsing previously used by the Windows playback shell. */
export function parseDuration(value: string): number | null {
  const parts = value.split(':').map(Number);
  if (parts.some((part) => !Number.isFinite(part))) return null;
  return parts.reduce((total, part) => total * 60 + part, 0);
}

function errorMessage(error: unknown, fallback: string): string {
  if (error && typeof error === 'object' && 'message' in error && typeof error.message === 'string') return error.message;
  if (typeof error === 'string') return error;
  return fallback;
}
function cloneState(state: PlaybackStateDto): PlaybackStateDto {
  return { ...state, isShuffle: state.isShuffle ?? false, isRepeat: state.isRepeat ?? false,
    currentTrack: state.currentTrack ? { ...state.currentTrack, artistRuns: state.currentTrack.artistRuns?.map(run => ({ ...run })) ?? [] } : null,
    queue: { ...state.queue, radio: state.queue.radio ? { ...state.queue.radio } : null, source: state.queue.source ? { ...state.queue.source } : null,
      items: state.queue.items.map((item) => ({ ...item, artistRuns: item.artistRuns?.map(run => ({ ...run })) ?? [] })) } };
}
function songDuration(song: PlayerSong): number | null {
  const duration = song.duration;
  return typeof duration === 'number' ? duration : duration ? parseDuration(duration) : null;
}
function entryFor(song: PlayerSong, index: number): QueueEntryDto {
  const withEntry = song as Partial<QueueEntryDto>;
  return { entryId: withEntry.entryId || createEntryId(index), videoId: song.videoId, title: song.title,
    sourceOccurrenceId: withEntry.sourceOccurrenceId ?? null,
    artists: song.artists, thumbnail: song.thumbnail, duration: songDuration(song),
    artistId: song.artistId ?? null, albumId: song.albumId ?? null, album: song.album ?? null,
    artistRuns: song.artistRuns?.map(run => ({ ...run })) ?? [], isUpload: song.isUpload ?? false };
}
let localEntrySequence = 0;
function createEntryId(index: number): string {
  const uuid = globalThis.crypto?.randomUUID?.();
  return uuid ?? `playback-${Date.now()}-${++localEntrySequence}-${index}`;
}

type AudioIntent = { command: 'set_playback_volume' | 'set_playback_muted' | 'set_exponential_volume';
  args: Record<string, unknown>; order: number; scope: number; generation: number };

/** Owns the playback snapshot while Rust remains authoritative for queue and audio state. */
export class PlaybackController {
  private state = emptyPlaybackData();
  private error: string | null = null;
  private publish: (snapshot: PlaybackSnapshot) => void;
  private eventRevision = 0;
  private stateEventRevision = 0;
  private operationRevision = new Map<string, number>();
  private confirmedVolume = 100;
  private audioRevision = 0;
  private lastAudible = 100;
  private intendedVolume: number | null = null;
  private audioScope = 0;
  private audioOrder = 0;
  private audioLevel: AudioIntent | null = null;
  private audioMode: AudioIntent | null = null;
  private audioFlight: AudioIntent | null = null;
  private audioDrain: Promise<void> | null = null;
  private audioLastSent = -Infinity;
  private audioWake: (() => void) | null = null;
  private modeQueue: Promise<void> = Promise.resolve();
  private seekQueue: Promise<void> = Promise.resolve();
  private connectionRevision = 0;
  private connectStarted = false;
  private unlisteners = new Set<PlayerUnlisten>();
  private listeners: PlayerListen;

  constructor(private rpc: PlayerRpc, listen: PlayerListen, publish: (snapshot: PlaybackSnapshot) => void) {
    this.listeners = listen;
    this.publish = publish;
    this.emit();
  }

  get snapshot(): PlaybackSnapshot { return { state: cloneState(this.state), confirmedVolume: this.confirmedVolume, error: this.error }; }

  private emit() { this.publish(this.snapshot); }
  private issue(key: string) {
    const revision = (this.operationRevision.get(key) ?? 0) + 1;
    this.operationRevision.set(key, revision);
    return revision;
  }
  private current(key: string, revision: number) { return this.operationRevision.get(key) === revision; }
  private acceptAudio(next: PlaybackStateDto): boolean {
    if (next.generation !== this.state.generation || (next.audioRevision ?? 0) < this.audioRevision) return false;
    this.audioRevision = next.audioRevision ?? 0;
    this.confirmedVolume = next.volume;
    if (next.volume > 0) this.lastAudible = next.volume;
    this.state = { ...this.state, volume: this.intendedVolume ?? next.volume,
      exponentialVolume: next.exponentialVolume ?? false, audioRevision: this.audioRevision };
    return true;
  }
  private acceptSeek(next: PlaybackStateDto): boolean {
    if (next.generation !== this.state.generation || (next.seekRevision ?? 0) <= (this.state.seekRevision ?? 0)) return false;
    this.state = { ...this.state, seekRevision: next.seekRevision ?? 0,
      seekPending: next.seekPending ?? null, seekError: next.seekError ?? null };
    return true;
  }
  private acceptState(next: PlaybackStateDto, audio = true): boolean {
    if (next.generation < this.state.generation) return false;
    if (next.generation === this.state.generation && next.queue.revision < this.state.queue.revision) {
      if (audio && this.acceptAudio(next)) this.emit();
      return false;
    }
    if (next.generation !== this.state.generation) {
      this.cancelVolumeInput();
      this.audioRevision = 0;
    }
    const previousSeek = next.generation === this.state.generation && (next.seekRevision ?? 0) < (this.state.seekRevision ?? 0)
      ? { seekRevision: this.state.seekRevision, seekPending: this.state.seekPending,
          seekError: this.state.seekError, position: this.state.position } : {};
    const previousAudio = { volume: this.state.volume, exponentialVolume: this.state.exponentialVolume,
      audioRevision: this.audioRevision };
    this.state = { ...cloneState(next), ...previousSeek };
    if (!audio || !this.acceptAudio(next)) this.state = { ...this.state, ...previousAudio };
    this.error = next.error;
    this.emit();
    return true;
  }
  private acceptResponse(next: PlaybackStateDto, eventRevision: number, audio = false): boolean {
    audio ||= (next.audioRevision ?? 0) > this.audioRevision;
    if (this.eventRevision !== eventRevision && next.generation <= this.state.generation) {
      // Audio and queue revisions are independent; neither is allowed to rewind progress.
      const audioAccepted = audio && this.acceptAudio(next);
      const seekAccepted = this.acceptSeek(next);
      if (next.generation === this.state.generation && next.queue.revision > this.state.queue.revision) {
        const normalized = cloneState(next);
        this.state = { ...this.state, queue: normalized.queue, canNext: normalized.canNext, sourceLoad: normalized.sourceLoad,
          currentTrack: normalized.currentTrack && normalized.currentTrack.videoId === this.state.currentTrack?.videoId
            ? normalized.currentTrack : this.state.currentTrack };
        this.emit(); return true;
      }
      if (audioAccepted || seekAccepted) this.emit();
      return false;
    }
    return this.acceptState(next, audio || next.generation !== this.state.generation);
  }
  private fail(key: string, revision: number, eventRevision: number, cause: unknown, fallback: string) {
    if (!this.current(key, revision) || this.eventRevision !== eventRevision) return;
    this.error = errorMessage(cause, fallback);
    this.emit();
  }

  /** Subscribes to Rust events first, then fetches a snapshot that cannot replace a newer event. */
  async connect(): Promise<void> {
    if (this.connectStarted) return;
    this.connectStarted = true;
    const connection = ++this.connectionRevision;
    const eventRevisionAtStart = this.eventRevision;
    const audioOrderAtStart = this.audioOrder;
    await Promise.all([
      this.attachListener<PlaybackStateDto>('playback-state-changed', (state) => {
        this.eventRevision++;
        if (this.acceptState(state)) this.stateEventRevision++;
      }, connection),
      this.attachListener<PlaybackProgressDto>('playback-progress', (progress) => this.acceptProgress(progress), connection),
    ]);
    if (connection !== this.connectionRevision) return;
    try {
      const state = await this.rpc<PlaybackStateDto>('get_playback_state');
      if (connection === this.connectionRevision) this.acceptResponse(state, eventRevisionAtStart, this.audioOrder === audioOrderAtStart);
    } catch { /* Preserve the current snapshot when startup state is temporarily unavailable. */ }
  }

  private async attachListener<T>(name: string, handler: (payload: T) => void, connection: number) {
    try {
      const unlisten = await this.listeners<T>(name, (event) => {
        if (connection === this.connectionRevision) handler(event.payload);
      });
      if (connection !== this.connectionRevision) await safelyUnlisten(unlisten);
      else this.unlisteners.add(unlisten);
    } catch { /* Playback remains usable through command snapshots if an event listener cannot attach. */ }
  }

  private acceptProgress(progress: PlaybackProgressDto) {
    this.eventRevision++;
    if (progress.generation !== this.state.generation || this.state.isLoading
      || (progress.seekRevision ?? 0) < (this.state.seekRevision ?? 0)) return;
    this.state = { ...this.state, position: progress.position,
      duration: progress.duration > 0 ? progress.duration : this.state.duration };
    this.emit();
  }

  invalidatePending() {
    this.cancelVolumeInput();
    for (const key of this.operationRevision.keys()) this.issue(key);
  }

  async playSong(song: PlayerSong, options: PlaySongOptions = {}): Promise<void> {
    if (!song.videoId.trim()) return;
    const revision = this.issue('play-song');
    const eventRevision = this.eventRevision;
    this.error = null;
    this.state = { ...this.state, error: null };
    this.emit();
    const preserveQueue = options.preserveQueue ?? false;
    const entries = preserveQueue ? null : (options.queueItems ?? [song]).map(entryFor);
    let queueIndex = options.queueIndex ?? null;
    if (entries && queueIndex === null) {
      const matched = entries.findIndex((entry) => entry.videoId === song.videoId);
      queueIndex = matched >= 0 ? matched : 0;
    }
    try {
      const state = await this.rpc<PlaybackStateDto>('play_song', {
        videoId: song.videoId.trim(), isUpload: song.isUpload ?? false, title: song.title || null, artists: song.artists || null,
        artistId: song.artistId ?? null, artistRuns: song.artistRuns?.map(run => ({ ...run })) ?? [],
        albumId: song.albumId ?? null, album: song.album ?? null,
        thumbnail: song.thumbnail ?? null, queueItems: entries,
        queueCurrentIndex: queueIndex, queueSource: entries ? options.queueSource ?? {
          kind: 'song', id: song.videoId.trim(), title: song.title || null,
        } : null, preserveQueue,
        shuffle: preserveQueue ? null : options.shuffle ?? false,
        queueEntryId: preserveQueue ? (song as Partial<QueueEntryDto>).entryId ?? (queueIndex == null ? null : this.state.queue.items[queueIndex]?.entryId) ?? null : null,
      });
      if (this.current('play-song', revision)) this.acceptResponse(state, eventRevision);
    } catch (cause) {
      const fresh = this.current('play-song', revision) && this.eventRevision === eventRevision;
      this.fail('play-song', revision, eventRevision, cause, 'No se pudo iniciar la reproducción de la canción.');
      if (fresh) throw new Error(errorMessage(cause, 'No se pudo iniciar la reproducción de la canción.'));
    }
  }

  async playQueueIndex(index: number): Promise<void> {
    const entry = this.state.queue.items[index];
    if (!entry) return;
    return this.playSong(entry, { preserveQueue: true, queueIndex: index });
  }

  async startRadio(song: SongDto, onAcceptedGeneration?: (generation: number) => void): Promise<void> {
    const revision = this.issue('play-song');
    const eventRevision = this.eventRevision;
    try {
      const next = await this.rpc<PlaybackStateDto>('start_song_radio', { song });
      if (this.current('play-song', revision)) { onAcceptedGeneration?.(next.generation); this.acceptResponse(next, eventRevision); }
    } catch (cause) {
      this.fail('play-song', revision, eventRevision, cause, 'No se pudo iniciar la radio.');
      if (this.current('play-song', revision)) throw new Error(errorMessage(cause, 'No se pudo iniciar la radio.'));
    }
  }

  async enqueue(songs: PlayerSong[], position: 'next' | 'end') {
    return this.queueCommand('enqueue_tracks', { items: songs.map(entryFor), position });
  }
  async removeQueueEntry(entryId: string) {
    return this.queueCommand('remove_queue_entry', { entryId });
  }
  async moveQueueEntry(entryId: string, beforeEntryId: string | null) {
    return this.queueCommand('move_queue_entry', { entryId, beforeEntryId });
  }
  async beginProgressiveSource(source: {kind: 'playlist' | 'library' | 'search' | 'search-radio'; id: string | null; continuation: string | null}) {
    return this.queueCommand('begin_queue_source', { ...source, expectedGeneration: this.state.generation });
  }
  async retrySource() { return this.queueCommand('retry_queue_source', {}); }
  async startSourceRadio(items: PlayerSong[], source: PlaybackQueueSource, playlistId: string, selectedIndex = 0) {
    return this.queueCommand('start_source_radio', { items: items.map(entryFor), source, playlistId, selectedIndex });
  }
  async filterDislikedRecommendations(videoId: string) { return this.queueCommand('filter_disliked_recommendations', { videoId, expectedGeneration: this.state.generation }); }
  setMuted(muted: boolean): Promise<void> {
    // A mute replaces unsent wheel/slider targets. Native unmute remains responsible for
    // restoring the last applied positive value, including 1%.
    this.intendedVolume = muted ? 0 : this.audioFlight?.command === 'set_playback_volume'
      && Number(this.audioFlight.args.volume) > 0 ? Number(this.audioFlight.args.volume) : this.lastAudible;
    return this.scheduleAudio('set_playback_muted', { muted });
  }
  setExponentialVolume(enabled: boolean): Promise<void> {
    return this.scheduleAudio('set_exponential_volume', { enabled });
  }
  async retryRadio() { return this.queueCommand('retry_radio', {}); }

  /** Queue mutations must report failure to menus without marking playable audio as broken. */
  private async queueCommand(command: string, args: Record<string, unknown>) {
    const eventRevision = this.eventRevision;
    const next = await this.rpc<PlaybackStateDto>(command, args);
    this.acceptResponse(next, eventRevision);
  }

  async next(): Promise<void> { return this.command('next', 'next_track', {}, 'No se pudo avanzar la cola.'); }
  async previous(): Promise<void> { return this.command('previous', 'previous_track', {}, 'No se pudo retroceder en la cola.'); }

  async setShuffle(enabled: boolean): Promise<void> {
    return this.setMode('shuffle', 'set_shuffle', enabled, 'No se pudo cambiar el modo aleatorio.');
  }
  async setRepeat(enabled: boolean): Promise<void> {
    return this.setMode('repeat', 'set_repeat', enabled, 'No se pudo cambiar la repetición.');
  }
  private setMode(key: 'shuffle' | 'repeat', command: 'set_shuffle' | 'set_repeat', enabled: boolean, fallback: string): Promise<void> {
    const revision = this.issue(key);
    const scheduled = this.modeQueue.then(async () => {
      if (!this.current(key, revision)) return;
      await this.applyMode(key, command, enabled, fallback, revision);
    });
    this.modeQueue = scheduled.catch(() => {});
    return scheduled;
  }

  private async applyMode(key: 'shuffle' | 'repeat', command: 'set_shuffle' | 'set_repeat', enabled: boolean, fallback: string, revision: number) {
    const eventRevision = this.eventRevision;
    const stateEventRevision = this.stateEventRevision;
    this.error = null;
    this.state = { ...this.state, error: null };
    this.emit();
    try {
      const next = await this.rpc<PlaybackStateDto>(command, { enabled });
      if (!this.current(key, revision)) return;
      this.acceptResponse(next, eventRevision);
      if (this.current(key, revision) && this.stateEventRevision === stateEventRevision
        && next.generation === this.state.generation) {
        // The response may have a stale progress position or mode bit for the other
        // control. acceptResponse merges newer queue/progress state; then apply only
        // this serialized command's authoritative bit.
        const field = key === 'shuffle' ? 'isShuffle' : 'isRepeat';
        this.state = { ...this.state, [field]: next[field] ?? false };
        this.emit();
      } else this.acceptResponse(next, eventRevision);
    } catch (cause) {
      if (!this.current(key, revision)) return;
      const message = errorMessage(cause, fallback);
      this.error = message;
      this.emit();
      throw new Error(message);
    }
  }

  async toggle(): Promise<void> {
    if ((this.state.isEnded || this.state.error || this.error) && this.state.currentTrack) return this.retry();
    const pause = this.state.isPlaying || this.state.isLoading;
    return this.command('toggle', pause ? 'pause_playback' : 'resume_playback', {}, 'Error al cambiar el estado de reproducción.');
  }

  async retry(): Promise<void> {
    const track = this.state.currentTrack;
    if (!track) return;
    return this.playSong(track, { preserveQueue: true, queueIndex: this.state.queue.currentIndex });
  }

  async seek(seconds: number): Promise<void> {
    if (!Number.isFinite(seconds) || seconds < 0) return;
    const entry = this.state.queue.items[this.state.queue.currentIndex ?? -1];
    if (!entry) return;
    const generation = this.state.generation;
    const auth = this.state.authGeneration ?? 0;
    const revision = this.issue('seek');
    // Serialize dispatch, coalescing unsent cues. Only native snapshots describe
    // pending/observed state; accepting an RPC never assigns the requested target.
    const scheduled = this.seekQueue.then(async () => {
      if (!this.current('seek', revision) || this.state.generation !== generation
        || (this.state.authGeneration ?? 0) !== auth
        || this.state.queue.items[this.state.queue.currentIndex ?? -1]?.entryId !== entry.entryId) return;
      const eventRevision = this.eventRevision;
      try {
        const next = await this.rpc<PlaybackStateDto>('seek_playback_identified', {
          seconds, expectedGeneration: generation, expectedAuthGeneration: auth, expectedEntryId: entry.entryId,
        });
        if (this.current('seek', revision) && this.state.generation === generation) this.acceptResponse(next, eventRevision);
      } catch (cause) { this.fail('seek', revision, eventRevision, cause, 'Error al cambiar la posición de reproducción.'); }
    });
    this.seekQueue = scheduled.catch(() => {});
    return scheduled;
  }

  setVolume(volume: number): Promise<void> {
    if (!Number.isFinite(volume)) return audioIdle;
    const target = Math.max(0, Math.min(100, volume));
    if (target === (this.intendedVolume ?? this.confirmedVolume)) return this.audioDrain ?? audioIdle;
    this.intendedVolume = target;
    return this.scheduleAudio('set_playback_volume', { volume: target });
  }

  adjustVolume(delta: number): Promise<void> {
    if (!Number.isFinite(delta)) return audioIdle;
    return this.setVolume((this.intendedVolume ?? this.confirmedVolume) + delta);
  }

  /** Invalidates unsent work and callbacks, but retains the in-flight lane until it settles. */
  cancelVolumeInput(): void {
    this.audioScope++;
    this.audioLevel = this.audioMode = null;
    this.intendedVolume = null;
    this.state = { ...this.state, volume: this.confirmedVolume };
    this.audioWake?.();
    this.emit();
  }

  private scheduleAudio(command: AudioIntent['command'], args: Record<string, unknown>): Promise<void> {
    const intent = { command, args, order: ++this.audioOrder, scope: this.audioScope, generation: this.state.generation };
    if (command === 'set_exponential_volume') this.audioMode = intent;
    else this.audioLevel = intent;
    this.error = null;
    if (this.intendedVolume !== null) this.state = { ...this.state, volume: this.intendedVolume };
    this.emit();
    if (!this.audioDrain) {
      // Assign the shared promise before starting: synchronous publishers may enqueue input.
      let resolve!: () => void;
      this.audioDrain = new Promise<void>(done => { resolve = done; });
      const finish = () => {
        // Input can arrive in the microtask between the last ACK and drain completion.
        if (this.audioLevel || this.audioMode) { void this.drainAudio().then(finish); return; }
        this.audioDrain = null; resolve();
      };
      void this.drainAudio().then(finish);
    }
    return this.audioDrain;
  }

  private async drainAudio(): Promise<void> {
    while (this.audioLevel || this.audioMode) {
      // Leading input is immediate; later targets are coalesced to at most 60 dispatches/s.
      const delay = 1000 / 60 - (Date.now() - this.audioLastSent);
      if (delay > 0) await new Promise<void>(resolve => {
        const timer = setTimeout(() => { this.audioWake = null; resolve(); }, Math.ceil(delay));
        this.audioWake = () => { clearTimeout(timer); this.audioWake = null; resolve(); };
      });
      const level = this.audioLevel, mode = this.audioMode;
      const intent = level && (!mode || level.order < mode.order) ? level : mode;
      if (!intent) continue;
      if (intent === level) this.audioLevel = null; else this.audioMode = null;
      if (intent.scope !== this.audioScope || intent.generation !== this.state.generation) continue;
      this.audioFlight = intent;
      this.audioLastSent = Date.now();
      const eventRevision = this.eventRevision;
      try {
        const next = await this.rpc<PlaybackStateDto>(intent.command, { ...intent.args, expectedGeneration: intent.generation });
        if (intent.scope !== this.audioScope || intent.generation !== this.state.generation) continue;
        // Merge queue/progress with their existing guards, then independently confirm audio.
        // Interleaved full DTOs can have newer queue/progress and older audio than this ACK.
        this.acceptResponse(next, eventRevision);
        if (intent.scope !== this.audioScope || next.generation !== this.state.generation) continue;
        if (!this.audioLevel) this.intendedVolume = null;
        this.acceptAudio(next);
        this.state = { ...this.state, volume: this.intendedVolume ?? this.confirmedVolume };
        this.error = next.error;
        this.emit();
      } catch (cause) {
        if (intent.scope !== this.audioScope || intent.generation !== this.state.generation) continue;
        this.audioLevel = this.audioMode = null;
        this.intendedVolume = null;
        const message = errorMessage(cause, intent.command === 'set_exponential_volume'
          ? 'No se pudo cambiar el volumen exponencial.' : 'Error al cambiar el volumen.');
        this.state = { ...this.state, volume: this.confirmedVolume };
        this.error = message;
        this.emit();
        // Read once to reconcile a failed/partially applied request; never retry the write.
        try {
          const next = await this.rpc<PlaybackStateDto>('get_playback_state');
          if (intent.scope === this.audioScope && next.generation === this.state.generation) {
            this.acceptResponse(next, eventRevision);
            this.acceptAudio(next);
          }
        } catch { /* Keep the last confirmed value if the runtime is unavailable. */ }
        if (intent.scope === this.audioScope) { this.error = message; this.emit(); }
      } finally { this.audioFlight = null; }
    }
  }

  private async command(key: string, command: string, args: Record<string, unknown>, fallback: string) {
    const revision = this.issue(key);
    const eventRevision = this.eventRevision;
    try {
      const state = await this.rpc<PlaybackStateDto>(command, args);
      if (this.current(key, revision)) this.acceptResponse(state, eventRevision);
    } catch (cause) { this.fail(key, revision, eventRevision, cause, fallback); }
  }

  async dispose(): Promise<void> {
    ++this.connectionRevision;
    this.connectStarted = false;
    this.invalidatePending();
    const pending = [...this.unlisteners];
    this.unlisteners.clear();
    await Promise.all(pending.map(safelyUnlisten));
  }
}

async function safelyUnlisten(unlisten: PlayerUnlisten): Promise<void> {
  try { await unlisten(); } catch { /* Cleanup is best effort and idempotent. */ }
}

// Queue mirror (JamSessionController+Queue.swift): the native queue stays authoritative. A track
// change loads `[current, ...matched upcoming]` with `play_song`; when only the upcoming list (or
// its matches) changes `jam_replace_upcoming` swaps what follows without touching the audio.
import type { PlaybackStateDto, QueueEntryDto } from '../types';
import { jamIdOf, matchedEntry, type JamCore, type MirrorApi } from './model';
import { identities } from './queueMapping';
import { JAM_QUEUE_SOURCE_KIND } from './types';

/** Debounce of upcoming replacements: lookups settle in bursts. */
const REPLACE_DELAY_MS = 300;
/** Minimum gap between corrective replacements triggered by playback snapshots. */
const REPLACE_COOLDOWN_MS = 1000;

export function createMirror(core: JamCore): MirrorApi {
  let chain: Promise<void> = Promise.resolve();
  let pending = 0;
  let replaceTimer: unknown = null;
  let lastReplace = -Infinity;
  /** Signature of the last upcoming list sent to the native queue: never resent unchanged. */
  let lastPushed = '';
  const occurrence = (entry: QueueEntryDto) => jamIdOf(entry) ?? entry.entryId;
  const signature = (entries: QueueEntryDto[]) => entries.map(entry => `${occurrence(entry)}=${entry.videoId}`).join(',');
  /** `jam_replace_upcoming` only works while the native queue belongs to a Jam. */
  const jamSource = () => core.d.playback?.queue.source?.kind === JAM_QUEUE_SOURCE_KIND;

  const native = (): { entry: QueueEntryDto | null; upcoming: QueueEntryDto[] } => {
    const queue = core.d.playback?.queue;
    const index = queue?.currentIndex ?? null;
    if (!queue || index === null) return { entry: null, upcoming: [] };
    return { entry: queue.items[index] ?? null, upcoming: queue.items.slice(index + 1) };
  };

  /** The entries the native queue should hold: current first, then every upcoming track that has a match. */
  function desired(): { current: QueueEntryDto | null; upcoming: QueueEntryDto[] } {
    const track = core.d.track;
    if (!track) return { current: null, upcoming: [] };
    const ids = identities(track.uri, core.d.queue.map(item => item.uri));
    const currentMatch = core.matching.matchOf(track.uri);
    const upcoming: QueueEntryDto[] = [];
    for (const [index, item] of core.d.queue.entries()) {
      const match = core.matching.matchOf(item.uri);
      if (match) upcoming.push(matchedEntry(match, ids.queue[index].entryId));
    }
    return { current: currentMatch && ids.current ? matchedEntry(currentMatch, ids.current.entryId) : null, upcoming };
  }

  function enqueue(job: () => Promise<void>): void {
    pending += 1;
    chain = chain.then(job).catch(error => core.note(`mirror error: ${error instanceof Error ? error.message : 'failed'}`)).finally(() => { pending -= 1; });
  }

  const observe = (state: PlaybackStateDto | undefined) => { if (state) core.d.playback = state; };

  async function load(token: number, uri: string, force: boolean): Promise<void> {
    if (!core.isCurrent(token) || core.d.track?.uri !== uri) return;
    const { current, upcoming } = desired();
    if (!current) {
      // No equivalent (yet): stay silent instead of playing something unrelated.
      if (core.matching.statusOf(uri) === 'unavailable') core.sync.pauseLocal();
      return;
    }
    const { entry } = native();
    if (!force && entry && jamSource() && jamIdOf(entry) !== null && entry.videoId === current.videoId) {
      // The local player already advanced to this track by itself (end of file): only sync.
      core.note('mirror: player already on the new track, not reloading');
      core.sync.begin();
      await replaceUpcoming(token, uri);
      return;
    }
    core.note(`mirror: loading ${current.title}`);
    const paused = core.d.anchor?.paused ?? true;
    try {
      const state = await core.raw<PlaybackStateDto>('play_song', {
        videoId: current.videoId, isUpload: current.isUpload ?? false, title: current.title, artists: current.artists,
        artistId: current.artistId ?? null, artistRuns: current.artistRuns ?? [], albumId: current.albumId ?? null,
        album: current.album ?? null, thumbnail: current.thumbnail, contentRating: current.contentRating,
        queueItems: [current, ...upcoming], queueCurrentIndex: 0,
        queueSource: { kind: JAM_QUEUE_SOURCE_KIND, id: null, title: 'Spotify Jam' },
        preserveQueue: false, shuffle: false, startPaused: paused || core.d.locallyPaused
      });
      observe(state);
      lastPushed = signature(upcoming);
    } catch (error) {
      core.note(`mirror: play_song failed (${(error as { code?: string })?.code ?? 'error'})`);
      return;
    }
    core.sync.begin();
  }

  async function replaceUpcoming(token: number, uri: string): Promise<void> {
    if (!core.isCurrent(token) || core.d.track?.uri !== uri) return;
    const { current, upcoming } = desired();
    const now = native();
    if (!current || !now.entry || !jamSource() || jamIdOf(now.entry) === null || now.entry.videoId !== current.videoId) return;
    const same = upcoming.length === now.upcoming.length
      && upcoming.every((entry, index) => occurrence(entry) === occurrence(now.upcoming[index]) && entry.videoId === now.upcoming[index].videoId);
    if (same) return;
    lastReplace = core.now();
    lastPushed = signature(upcoming);
    try {
      observe(await core.raw<PlaybackStateDto>('jam_replace_upcoming', { items: upcoming }));
    } catch (error) {
      // E.g. JAM_QUEUE_NOT_ACTIVE: something else owns the queue now. Not retried until the list changes.
      core.note(`mirror: jam_replace_upcoming failed (${(error as { code?: string })?.code ?? 'error'})`);
    }
  }

  function scheduleReplace(): void {
    if (replaceTimer !== null) core.sched.clearTimeout(replaceTimer);
    const token = core.d.token;
    replaceTimer = core.sched.setTimeout(() => {
      replaceTimer = null;
      const uri = core.d.track?.uri;
      if (core.isCurrent(token) && uri) enqueue(() => replaceUpcoming(token, uri));
    }, REPLACE_DELAY_MS);
  }

  function loadCurrent(force: boolean): void {
    const uri = core.d.track?.uri;
    if (!uri) return;
    const token = core.d.token;
    enqueue(() => load(token, uri, force));
  }

  return {
    onTrackChange() {
      if (core.d.track) loadCurrent(false);
      else core.sync.pauseLocal();
    },
    onQueueChange: scheduleReplace,
    onMatch(uri) {
      if (uri === core.d.track?.uri) loadCurrent(false);
      scheduleReplace();
    },
    loadCurrent,
    onPlayback() {
      if (!core.isLive() || pending > 0 || replaceTimer !== null || core.now() - lastReplace < REPLACE_COOLDOWN_MS) return;
      const track = core.d.track;
      if (!track || !core.matching.matchOf(track.uri)) return;
      const { entry, upcoming } = native();
      const want = desired().upcoming;
      if (signature(want) === lastPushed) return;
      const aligned = entry && jamSource() && jamIdOf(entry) !== null && entry.videoId === core.matching.matchOf(track.uri)?.view.videoId;
      if (aligned && (want.length !== upcoming.length || want.some((item, index) => occurrence(item) !== occurrence(upcoming[index])))) scheduleReplace();
    },
    busy: () => pending > 0,
    nativeCurrentEntryId: () => {
      return jamSource() ? jamIdOf(native().entry) : null;
    },
    stop() {
      if (replaceTimer !== null) core.sched.clearTimeout(replaceTimer);
      replaceTimer = null;
      lastPushed = '';
    }
  };
}

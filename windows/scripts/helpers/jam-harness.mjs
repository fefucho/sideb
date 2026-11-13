// Fakes for the Jam session tests: virtual time and timers, an rpc/listen pair, and a small model
// of the native player (queue, position, speed) that answers the commands the Jam issues.
export const flush = async () => { for (let i = 0; i < 4; i += 1) await new Promise(resolve => setImmediate(resolve)); };

export function fakeTime(start = 1_000_000) {
  let t = start, seq = 0;
  const timers = new Map();
  const schedule = {
    setTimeout(fn, ms) { const id = ++seq; timers.set(id, {at: t + Math.max(0, ms), fn, id}); return id; },
    clearTimeout(id) { timers.delete(id); }
  };
  return {
    now: () => t,
    schedule,
    get pending() { return timers.size; },
    /** Runs timers in order up to `ms` later, letting promises settle after each. */
    async advance(ms) {
      const end = t + ms;
      for (;;) {
        await flush();
        const next = [...timers.values()].filter(timer => timer.at <= end).sort((a, b) => a.at - b.at || a.id - b.id)[0];
        if (!next) break;
        timers.delete(next.id);
        t = Math.max(t, next.at);
        next.fn();
      }
      t = end;
      await flush();
    }
  };
}

export const song = (videoId, title, artists, duration = '3:00', extra = {}) =>
  ({videoId, title, artists, album: null, duration, thumbnail: null, isVideo: false, artistId: null, albumId: null, ...extra});

export const track = (n, extra = {}) => ({
  uri: `spotify:track:${n}`, title: `Title ${n}`, artists: [`Artist ${n}`], album: null, durationMs: 180000, isrc: null, provider: null, ...extra
});

/** The Spotify track `n` always has the YouTube Music song `yt-n`. */
export const catalog = n => song(`yt-${n}`, `Title ${n}`, `Artist ${n}`, '3:00');

export function fakeApp({time, search = query => { const n = /Title (\w+)/.exec(query)?.[1]; return n ? [catalog(n)] : []; }, seekLanding = -0.12, rateWorks = true} = {}) {
  const calls = [];
  const listeners = new Map();
  const handlers = new Map();
  let nativeIds = 0;
  /** Like the Rust queue: every entry gets a fresh opaque id; `sourceOccurrenceId` is the only identity that survives. */
  const fresh = item => ({...item, entryId: `native-${++nativeIds}`});
  const player = {source: null, items: [], currentIndex: null, playing: false, base: 0, at: 0, speed: 1, generation: 1, revision: 1, loading: false, jamSpeed: 1};
  const position = () => player.playing ? player.base + ((time.now() - player.at) / 1000) * player.speed : player.base;
  const settle = () => { player.base = position(); player.at = time.now(); };
  const state = () => ({
    isPlaying: player.playing, isLoading: player.loading, isEnded: false, isShuffle: false, isRepeat: false, position: position(),
    duration: 180, volume: 100, currentTrack: null, error: null, generation: player.generation, authGeneration: 0,
    queue: {items: player.items, currentIndex: player.currentIndex, source: player.source, revision: player.revision}
  });
  const current = () => player.items[player.currentIndex ?? -1] ?? null;
  const base = {
    jam_status: () => ({pluginAvailable: true, running: false, signedIn: true}),
    jam_join: () => undefined, jam_leave: () => undefined, jam_send: () => undefined,
    jam_set_speed: ({speed}) => { settle(); player.speed = rateWorks ? speed : 1; player.jamSpeed = speed; },
    jam_clock: () => ({positionSecs: position(), atEpochMs: time.now(), isPlaying: player.playing, isLoading: player.loading,
      videoId: current()?.videoId ?? null, entryId: current()?.entryId ?? null, generation: player.generation, authGeneration: 0, speed: player.speed}),
    search_songs: ({query}) => search(query),
    get_playback_state: () => state(),
    play_song: args => {
      player.items = (args.queueItems ?? player.items).map(fresh); player.source = args.queueSource ?? player.source; player.currentIndex = args.queueCurrentIndex ?? 0;
      player.playing = !args.startPaused; player.base = 0; player.at = time.now(); player.generation += 1; player.revision += 1;
      return state();
    },
    jam_replace_upcoming: ({items}) => {
      if (player.source?.kind !== 'jam') throw {code: 'JAM_QUEUE_NOT_ACTIVE', message: 'not a jam queue'};
      player.items = [...player.items.slice(0, (player.currentIndex ?? 0) + 1), ...items.map(fresh)]; player.revision += 1; return state();
    },
    pause_playback: () => { settle(); player.playing = false; return state(); },
    resume_playback: () => { settle(); player.playing = true; return state(); },
    seek_playback_identified: ({seconds, expectedGeneration, expectedEntryId}) => {
      if (expectedGeneration !== player.generation || expectedEntryId !== current()?.entryId) throw {code: 'SEEK_STALE', message: 'stale seek'};
      settle(); player.base = seconds + (player.playing ? seekLanding : 0); return state(); },
    next_track: () => state(), previous_track: () => state()
  };
  const rpc = async (command, args) => {
    calls.push({command, args});
    const handler = handlers.get(command) ?? base[command];
    if (!handler) throw {code: 'UNKNOWN_COMMAND', message: command};
    return handler(args);
  };
  const listen = async (event, handler) => {
    listeners.set(event, handler);
    return () => listeners.delete(event);
  };
  return {
    rpc, listen, calls, player, state, position,
    /** Overrides a command. */
    on: (command, handler) => handlers.set(command, handler),
    emit: payload => listeners.get('jam-event')?.({payload}),
    callsOf: command => calls.filter(call => call.command === command),
    sent: () => calls.filter(call => call.command === 'jam_send').map(call => call.args.message),
    /** A plugin `state` event for a position that is true now. */
    jamState({track: t = track(1), queue = [], positionMs = 0, paused = false, revision = 'r1'} = {}) {
      return {type: 'state', track: t, positionMs, atLocalMs: time.now(), paused, durationMs: 180000, queue, queueRevision: revision, previousCount: 0, shuffle: false, clockOffsetMs: 0};
    }
  };
}

export const joined = (extra = {}) => ({type: 'joined', protocolVersion: 2, members: [{id: 'h', name: 'Host', isHost: true}, {id: 'me', name: 'Me', isCurrentUser: true}], canControl: true, queueOnly: false, hostDevice: 'phone', hostActive: true, ...extra});

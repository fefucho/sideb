import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/player/controller.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { PlaybackController, emptyPlaybackData, prepareCollectionPlayback } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

function deferred() {
  let resolve; let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function state(generation, options = {}) {
  return { ...emptyPlaybackData(), generation, ...options,
    queue: { ...emptyPlaybackData().queue, ...(options.queue ?? {}) } };
}
const song = (videoId) => ({ videoId, title: videoId, artists: 'Artist', thumbnail: null, duration: '3:21' });
async function settle() { await new Promise((resolve) => setTimeout(resolve, 0)); }

test('exponential volume is native state and keeps slider percent and mute commands unchanged', async () => {
  let native = state(1, { volume: 13, exponentialVolume: false });
  const calls = [];
  const player = new PlaybackController(async (command, args) => {
    calls.push({command,args});
    if(command==='set_exponential_volume') native={...native,exponentialVolume:args.enabled};
    if(command==='set_playback_volume') native={...native,volume:args.volume};
    return structuredClone(native);
  },async()=>()=>{},()=>{});
  await player.connect(); await player.setExponentialVolume(true);
  assert.equal(player.snapshot.state.exponentialVolume,true);assert.equal(player.snapshot.state.volume,13);
  await player.setVolume(7);assert.equal(calls.at(-1).args.volume,7);
  assert.equal(player.snapshot.state.exponentialVolume,true);
  await player.setMuted(true);assert.equal(calls.at(-1).command,'set_playback_muted');assert.deepEqual(calls.at(-1).args,{muted:true});
});

test('failed exponential volume retains accepted mode and can be retried', async () => {
  let failed=true;
  const player=new PlaybackController(async(command)=>{
    if(command==='set_exponential_volume'&&failed)throw new Error('No se pudo cambiar el volumen exponencial.');
    return state(1,{volume:9,exponentialVolume:command==='set_exponential_volume'});
  },async()=>()=>{},()=>{});
  await player.connect();await player.setExponentialVolume(true);
  assert.equal(player.snapshot.state.exponentialVolume,false);assert.equal(player.snapshot.state.volume,9);
  assert.match(player.snapshot.error,/volumen exponencial/);
  failed=false;await player.setExponentialVolume(true);
  assert.equal(player.snapshot.state.exponentialVolume,true);assert.equal(player.snapshot.error,null);
});

test('exponential mode response preserves newer progress and yields to a newer native state', async()=>{
  const listeners=new Map(), response=deferred();
  const player=new PlaybackController(async command=>command==='get_playback_state'?state(4,{position:8}):response.promise,
    async(event,callback)=>{listeners.set(event,callback);return()=>{};},()=>{});
  await player.connect();const changing=player.setExponentialVolume(true);
  listeners.get('playback-progress')({payload:{generation:4,position:12,duration:200}});
  response.resolve(state(4,{position:8,exponentialVolume:true}));await changing;
  assert.equal(player.snapshot.state.position,12);assert.equal(player.snapshot.state.exponentialVolume,true);
  const later=deferred();const otherListeners=new Map();
  const other=new PlaybackController(async command=>command==='get_playback_state'?state(4):later.promise,
    async(event,callback)=>{otherListeners.set(event,callback);return()=>{};},()=>{});
  await other.connect();const stale=other.setExponentialVolume(true);
  otherListeners.get('playback-state-changed')({payload:state(5,{exponentialVolume:false})});
  later.resolve(state(4,{exponentialVolume:true}));await stale;
  assert.equal(other.snapshot.state.generation,5);assert.equal(other.snapshot.state.exponentialVolume,false);
});

test('initial shuffle chooses from the full catalog without destroying canonical order', async () => {
  const songs = Array.from({ length: 2000 }, (_, index) => song(`song-${index}`));
  const original = structuredClone(songs);
  const source = { kind: 'playlist', id: 'LM', title: 'Likes' };
  const prepared = prepareCollectionPlayback(songs, 0, source, true, null, '', () => 0.875);
  assert.equal(prepared.options.queueIndex, 1750);
  assert.equal(prepared.song.videoId, 'song-1750');
  assert.deepEqual(prepared.options.queueItems.map(entry => entry.videoId), songs.map(entry => entry.videoId));
  assert.equal(new Set(prepared.options.queueItems.map(entry => entry.entryId)).size, 2000);
  assert.deepEqual(songs, original);
  let args;
  const player = new PlaybackController(async (_command, input) => { args = input; return state(1); }, async () => () => {}, () => {});
  await player.playSong(prepared.song, prepared.options);
  assert.equal(args.shuffle, true);
  assert.equal(args.queueCurrentIndex, 1750);
  assert.equal(args.videoId, args.queueItems[1750].videoId);
  assert.deepEqual(args.queueItems.map(entry => entry.videoId), songs.map(entry => entry.videoId));
});

test('all collection sources retain selected occurrences after filtering unavailable tracks', () => {
  const songs = [song(''), song('same'), song('same'), song('last')];
  for (const kind of ['album', 'artist', 'playlist', 'library', 'history', 'mix']) {
    const source = { kind, id: 'collection', title: 'Collection' };
    const prepared = prepareCollectionPlayback(songs, 2, source, false, 'artwork', 'Fallback artist');
    assert.deepEqual(prepared.options.queueItems.map(entry => entry.videoId), ['same', 'same', 'last']);
    assert.equal(prepared.options.queueIndex, 1);
    assert.equal(prepared.song.entryId, prepared.options.queueItems[1].entryId);
    assert.notEqual(prepared.options.queueItems[0].entryId, prepared.song.entryId);
    assert.equal(prepared.song.thumbnail, 'artwork');
    assert.equal(prepared.song.duration, 201);
    assert.equal(prepared.options.shuffle, false);
    assert.deepEqual(prepared.options.queueSource, source);
  }
  assert.throws(() => prepareCollectionPlayback([song(' ')], 0, null), /No hay canciones disponibles/);
});

test('collection playback passes shuffle atomically and queue selection preserves its mode', async () => {
  const calls = [];
  const items = ['older-like', 'recent-like'].map(videoId => ({ ...song(videoId), entryId: videoId, duration: 201 }));
  const player = new PlaybackController(async (command, args) => {
    calls.push({ command, args });
    return state(calls.length, { isShuffle: args.shuffle ?? true, queue: { items, currentIndex: 0 } });
  }, async () => () => {}, () => {});
  await player.playSong(items[0], { queueItems: items, queueIndex: 0, queueSource: { kind: 'playlist', id: 'LM', title: 'Likes' }, shuffle: true });
  assert.equal(calls[0].args.shuffle, true);
  assert.equal(player.snapshot.state.isShuffle, true);
  await player.playQueueIndex(1);
  assert.equal(calls[1].args.shuffle, null);
  assert.equal(calls[1].args.preserveQueue, true);
  await player.playSong(song('normal'));
  assert.equal(calls[2].args.shuffle, false);
  assert.equal(player.snapshot.state.isShuffle, false);
});

test('queue metadata survives RPC normalization and queue actions preserve freshest progress', async () => {
  const listeners = new Map(); let published; const enqueued = deferred(); let args;
  const player = new PlaybackController(async (command, input) => {
    if (command === 'get_playback_state') return state(2, { position: 10, isPlaying: true });
    if (command === 'enqueue_tracks') { args = input; return enqueued.promise; }
    throw new Error(command);
  }, async (event, handler) => { listeners.set(event, handler); return () => {}; }, next => published = next);
  await player.connect();
  const artistRuns = [{ text: 'Daft Punk', id: 'UC-daft' }, { text: 'Pharrell Williams', id: 'UC-pharrell' }];
  const pending = player.enqueue([{ ...song('v'), artistId: 'artist', artistRuns, albumId: 'album', album: 'Album' }], 'next');
  assert.equal(args.items[0].artistId, 'artist'); assert.equal(args.items[0].albumId, 'album'); assert.equal(args.items[0].duration, 201);
  assert.deepEqual(args.items[0].artistRuns, artistRuns);
  listeners.get('playback-progress')({ payload: { generation: 2, position: 12, duration: 201 } });
  enqueued.resolve(state(2, { position: 10, queue: { revision: 1, items: args.items } }));
  await pending;
  assert.equal(published.state.position, 12); assert.equal(published.state.queue.items[0].album, 'Album');
  published.state.queue.items[0].artistRuns[1].id = 'changed-by-consumer';
  assert.equal(player.snapshot.state.queue.items[0].artistRuns[1].id, 'UC-pharrell');
});

test('play, radio and retry preserve individual artist links and album metadata', async () => {
  const artistRuns = [{ text: 'Daft Punk', id: 'UC-daft' }, { text: 'Pharrell Williams', id: 'UC-pharrell' }];
  const track = { ...song('dance'), artists: 'Daft Punk & Pharrell Williams', artistRuns,
    album: 'Random Access Memories', albumId: 'MPRE-album', artistId: 'UC-daft' };
  const calls = [];
  const player = new PlaybackController(async (command, args) => {
    calls.push({ command, args });
    return state(2, { currentTrack: { ...track, duration: 201 }, queue: { items: [{ ...track, entryId: 'occurrence', duration: 201 }], currentIndex: 0 } });
  }, async () => () => {}, () => {});
  await player.playSong(track);
  assert.deepEqual(calls[0].args.artistRuns, artistRuns);
  assert.deepEqual(calls[0].args.queueItems[0].artistRuns, artistRuns);
  assert.equal(calls[0].args.album, track.album);
  await player.retry();
  assert.deepEqual(calls[1].args.artistRuns, artistRuns);
  assert.equal(calls[1].args.queueEntryId, 'occurrence');
  await player.startRadio(track);
  assert.deepEqual(calls[2].args.song.artistRuns, artistRuns);
  assert.equal(calls[2].args.song.albumId, track.albumId);
});

test('radio metadata arriving after progress enriches the current track without rewinding it', async () => {
  const listeners = new Map(); const radio = deferred();
  const track = { ...song('dance'), duration: 201 };
  const entry = { ...track, entryId: 'seed' };
  const player = new PlaybackController(async command => {
    if (command === 'get_playback_state') return state(3, { currentTrack: track, position: 20, isPlaying: true,
      queue: { items: [entry], currentIndex: 0 } });
    if (command === 'retry_radio') return radio.promise;
    throw new Error(command);
  }, async (event, handler) => { listeners.set(event, handler); return () => {}; }, () => {});
  await player.connect();
  const pending = player.retryRadio();
  listeners.get('playback-progress')({ payload: { generation: 3, position: 22, duration: 201 } });
  const metadata = { artistRuns: [{ text: 'Daft Punk', id: 'UC-daft' }, { text: 'Pharrell Williams', id: 'UC-pharrell' }],
    album: 'Random Access Memories', albumId: 'MPRE-album' };
  radio.resolve(state(3, { currentTrack: { ...track, ...metadata }, position: 20,
    queue: { items: [{ ...entry, ...metadata }], currentIndex: 0, revision: 1 } }));
  await pending;
  assert.equal(player.snapshot.state.position, 22);
  assert.equal(player.snapshot.state.isPlaying, true);
  assert.equal(player.snapshot.state.currentTrack.album, metadata.album);
  assert.deepEqual(player.snapshot.state.currentTrack.artistRuns, metadata.artistRuns);
  assert.equal(player.snapshot.state.queue.items[0].entryId, 'seed');
});
test('failed queue mutation reports to caller without marking playing audio as failed', async () => {
  let published;
  const player = new PlaybackController(async command => {
    if (command === 'get_playback_state') return state(1, { isPlaying: true });
    throw new Error('cannot remove current');
  }, async () => () => {}, next => published = next);
  await player.connect(); await assert.rejects(player.removeQueueEntry('current'), /cannot remove/);
  assert.equal(published.state.isPlaying, true); assert.equal(published.error, null);
});
test('selecting a duplicate song passes its stable occurrence ID to Rust', async () => {
  let args;
  const items = ['first', 'second'].map(entryId => ({ ...song('same'), entryId, duration: 201 }));
  const player = new PlaybackController(async (command, input) => {
    if (command === 'get_playback_state') return state(1, { queue: { items, currentIndex: 0 } });
    args = input; return state(2, { queue: { items, currentIndex: 1 } });
  }, async () => () => {}, () => {});
  await player.connect(); await player.playQueueIndex(1);
  assert.equal(args.queueEntryId, 'second'); assert.equal(args.preserveQueue, true); assert.equal(args.queueItems, null);
});

test('queue reorder uses occurrence IDs and preserves newer progress without playing again', async () => {
  const listeners = new Map(); const moved = deferred(); const calls = [];
  const items = ['first', 'active', 'last'].map(entryId => ({ ...song('same'), entryId, duration: 201 }));
  const player = new PlaybackController(async (command, args) => {
    calls.push({ command, args });
    if (command === 'get_playback_state') return state(4, { isPlaying: true, position: 30,
      currentTrack: { ...song('same'), duration: 201 }, queue: { items, currentIndex: 1, revision: 8 } });
    if (command === 'move_queue_entry') return moved.promise;
    throw new Error(command);
  }, async (event, handler) => { listeners.set(event, handler); return () => {}; }, () => {});
  await player.connect();
  const pending = player.moveQueueEntry('first', null);
  assert.deepEqual(calls[1], { command: 'move_queue_entry', args: { entryId: 'first', beforeEntryId: null } });
  assert.deepEqual(player.snapshot.state.queue.items.map(entry => entry.entryId), ['first', 'active', 'last']);
  listeners.get('playback-progress')({ payload: { generation: 4, position: 31, duration: 201 } });
  moved.resolve(state(4, { isPlaying: true, position: 30, currentTrack: { ...song('same'), duration: 201 },
    queue: { items: [items[1], items[2], items[0]], currentIndex: 0, revision: 9 } }));
  await pending;
  assert.deepEqual(player.snapshot.state.queue.items.map(entry => entry.entryId), ['active', 'last', 'first']);
  assert.equal(player.snapshot.state.queue.currentIndex, 0);
  assert.equal(player.snapshot.state.generation, 4);
  assert.equal(player.snapshot.state.position, 31);
  assert.equal(player.snapshot.state.isPlaying, true);
  assert.equal(calls.length, 2);
});

test('stale reorder destination reports failure and leaves playable snapshot intact', async () => {
  let args;
  const player = new PlaybackController(async (command, input) => {
    if (command === 'get_playback_state') return state(4, { isPlaying: true, position: 30 });
    args = input;
    throw new Error('destination no longer in queue');
  }, async () => () => {}, () => {});
  await player.connect();
  const before = player.snapshot;
  await assert.rejects(player.moveQueueEntry('first', 'stale'), /destination/);
  assert.deepEqual(args, { entryId: 'first', beforeEntryId: 'stale' });
  assert.deepEqual(player.snapshot, before);
});

test('initial snapshot cannot replace a newer playback state event', async () => {
  const snapshot = deferred(); const listeners = new Map(); let published;
  const player = new PlaybackController(async (command) => {
    assert.equal(command, 'get_playback_state'); return snapshot.promise;
  }, async (name, handler) => {
    listeners.set(name, handler); return () => {};
  }, (next) => { published = next; });

  const connecting = player.connect();
  await settle();
  listeners.get('playback-state-changed')({ payload: state(4, { isPlaying: true, position: 24, currentTrack: { ...song('new'), duration: 201 } }) });
  snapshot.resolve(state(4, { currentTrack: { ...song('old'), duration: 1 } }));
  await connecting;
  assert.equal(published.state.generation, 4);
  assert.equal(published.state.currentTrack.videoId, 'new');
  assert.equal(published.state.isPlaying, true);
  assert.equal(published.state.position, 24);
});

test('newer play request wins when RPC replies arrive out of order', async () => {
  const calls = []; let published;
  const player = new PlaybackController((command, args) => {
    const wait = deferred(); calls.push({ command, args, ...wait }); return wait.promise;
  }, async () => () => {}, (next) => { published = next; });
  const older = player.playSong(song('old'));
  const newer = player.playSong(song('new'));
  assert.equal(calls[0].args.queueItems[0].duration, 201);
  assert.deepEqual(calls[1].args.queueSource, { kind: 'song', id: 'new', title: 'new' });
  calls[1].resolve(state(2, { currentTrack: { ...song('new'), duration: 201 } }));
  await newer;
  calls[0].resolve(state(1, { currentTrack: { ...song('old'), duration: 201 } }));
  await older;
  assert.equal(published.state.currentTrack.videoId, 'new');
  assert.equal(published.error, null);
});

test('stale play failure does not publish or reject after a newer play succeeds', async () => {
  const calls = []; let published;
  const player = new PlaybackController((command) => {
    const wait = deferred(); calls.push(wait); return wait.promise;
  }, async () => () => {}, (next) => { published = next; });
  const old = player.playSong(song('old'));
  const current = player.playSong(song('current'));
  calls[1].resolve(state(7, { currentTrack: { ...song('current'), duration: 10 } }));
  await current;
  calls[0].reject(new Error('old failure'));
  await old;
  assert.equal(published.state.currentTrack.videoId, 'current');
  assert.equal(published.error, null);
});

test('only latest rapid toggle and volume replies can replace state', async () => {
  const calls = []; let published;
  const player = new PlaybackController((command, args) => {
    const wait = deferred(); calls.push({ command, args, ...wait }); return wait.promise;
  }, async () => () => {}, (next) => { published = next; });
  const firstToggle = player.toggle(); const secondToggle = player.toggle();
  assert.deepEqual(calls.slice(0, 2).map((call) => call.command), ['resume_playback', 'resume_playback']);
  calls[1].resolve(state(2, { isPlaying: true })); await secondToggle;
  calls[0].resolve(state(1, { isPlaying: false })); await firstToggle;
  assert.equal(published.state.isPlaying, true);

  const firstVolume = player.setVolume(10); const secondVolume = player.setVolume(35);
  calls[3].resolve(state(2, { volume: 35 })); await secondVolume;
  calls[2].resolve(state(2, { volume: 10 })); await firstVolume;
  assert.equal(published.state.volume, 35);
});

test('stale state events cannot overwrite generation or queue revision', () => {
  let listener; let published;
  const player = new PlaybackController(async () => state(0), async (name, handler) => {
    if (name === 'playback-state-changed') listener = handler;
    return () => {};
  }, (next) => { published = next; });
  const connect = player.connect();
  return settle().then(() => {
    listener({ payload: state(3, { queue: { revision: 8 } }) });
    listener({ payload: state(3, { queue: { revision: 7 }, isPlaying: true }) });
    assert.equal(published.state.queue.revision, 8);
    assert.equal(published.state.isPlaying, false);
    return connect;
  });
});

test('dispose unlistens subscriptions that resolve after teardown', async () => {
  const registrations = [deferred(), deferred()]; let index = 0; let calls = 0;
  const player = new PlaybackController(async () => state(0), async () => registrations[index++].promise, () => {});
  const connecting = player.connect();
  await player.dispose();
  registrations.forEach((registration) => registration.resolve(() => { calls++; }));
  await connecting;
  assert.equal(calls, 2);
});

test('account invalidation drops command callbacks without mutating player snapshot', async () => {
  const response = deferred(); let published;
  const player = new PlaybackController(async (command) => command === 'next_track' ? response.promise : state(0), async () => () => {}, (next) => { published = next; });
  const request = player.next();
  player.invalidatePending();
  response.resolve(state(8, { currentTrack: { ...song('from-old-account'), duration: 201 } }));
  await request;
  assert.equal(published.state.currentTrack, null);
  assert.equal(published.state.generation, 0);
});

test('progress applies only to current generation and skips loading states', () => {
  let progress; let stateChanged; let published;
  const player = new PlaybackController(async () => state(5), async (name, handler) => {
    if (name === 'playback-progress') progress = handler;
    if (name === 'playback-state-changed') stateChanged = handler;
    return () => {};
  }, (next) => { published = next; });
  const connecting = player.connect();
  return settle().then(async () => {
    progress({ payload: { generation: 4, position: 20, duration: 99 } });
    assert.equal(published.state.position, 0);
    progress({ payload: { generation: 5, position: 20, duration: 99 } });
    assert.equal(published.state.position, 20);
    assert.equal(published.state.duration, 99);
    stateChanged({ payload: state(5, { isLoading: true, position: 20, duration: 99 }) });
    progress({ payload: { generation: 5, position: 25, duration: 99 } });
    assert.equal(published.state.position, 20);
    await connecting;
  });
});

test('legacy playback snapshots default missing mode flags to false', async () => {
  const legacy = state(2, { isPlaying: true });
  delete legacy.isShuffle;
  delete legacy.isRepeat;
  const player = new PlaybackController(async () => legacy, async () => () => {}, () => {});
  await player.connect();
  assert.equal(player.snapshot.state.isShuffle, false);
  assert.equal(player.snapshot.state.isRepeat, false);
});

test('shuffle and repeat send explicit native arguments and accept authoritative flags', async () => {
  const calls = [];
  const player = new PlaybackController(async (command, args) => {
    calls.push({ command, args });
    if (command === 'get_playback_state') return state(4, { isPlaying: true, position: 31, duration: 201 });
    if (command === 'set_shuffle') return state(4, { isPlaying: true, position: 31, duration: 201, isShuffle: true });
    if (command === 'set_repeat') return state(4, { isPlaying: true, position: 31, duration: 201, isShuffle: true, isRepeat: true });
    throw new Error(command);
  }, async () => () => {}, () => {});
  await player.connect();
  await player.setShuffle(true);
  await player.setRepeat(true);
  assert.deepEqual(calls.slice(1), [
    { command: 'set_shuffle', args: { enabled: true } },
    { command: 'set_repeat', args: { enabled: true } },
  ]);
  assert.equal(player.snapshot.state.isShuffle, true);
  assert.equal(player.snapshot.state.isRepeat, true);
  assert.equal(player.snapshot.state.position, 31);
  assert.equal(player.snapshot.state.isPlaying, true);
});

test('repeat RPC merges its mode bit after progress without rewinding the playback snapshot', async () => {
  const listeners = new Map();
  const response = deferred();
  let published;
  const player = new PlaybackController(async command => {
    if (command === 'get_playback_state') return state(6, { isPlaying: true, position: 40, duration: 201 });
    if (command === 'set_repeat') return response.promise;
    throw new Error(command);
  }, async (event, handler) => { listeners.set(event, handler); return () => {}; }, next => published = next);
  await player.connect();
  const pending = player.setRepeat(true);
  await settle();
  listeners.get('playback-progress')({ payload: { generation: 6, position: 42, duration: 201 } });
  response.resolve(state(6, { isPlaying: false, position: 40, duration: 201, isRepeat: true }));
  await pending;
  assert.equal(published.state.isRepeat, true);
  assert.equal(published.state.position, 42);
  assert.equal(published.state.isPlaying, true);
});

test('shuffle response applies a newer queue and its capabilities while keeping progress received during the RPC', async () => {
  const listeners = new Map();
  const response = deferred();
  let published;
  const before = [{ ...song('a'), entryId: 'a', duration: 201 }, { ...song('b'), entryId: 'b', duration: 201 }];
  const after = [before[0], { ...song('c'), entryId: 'c', duration: 201 }];
  const player = new PlaybackController(async command => {
    if (command === 'get_playback_state') return state(8, { isPlaying: true, position: 50, duration: 201,
      queue: { revision: 4, items: before, currentIndex: 0 } });
    if (command === 'set_shuffle') return response.promise;
    throw new Error(command);
  }, async (event, handler) => { listeners.set(event, handler); return () => {}; }, next => published = next);
  await player.connect();
  const pending = player.setShuffle(true);
  await settle();
  listeners.get('playback-progress')({ payload: { generation: 8, position: 54, duration: 201 } });
  response.resolve(state(8, { isPlaying: false, isShuffle: true, position: 50, duration: 201,
    canNext: true, sourceLoad: {loading:false,error:null,canRetry:false,hasMore:true,loadedCount:2},
    queue: { revision: 5, items: after, currentIndex: 1 } }));
  await pending;
  assert.equal(published.state.isShuffle, true);
  assert.deepEqual(published.state.queue.items.map(item => item.entryId), ['a', 'c']);
  assert.equal(published.state.queue.currentIndex, 1);
  assert.equal(published.state.canNext, true);
  assert.equal(published.state.sourceLoad.hasMore, true);
  assert.equal(published.state.position, 54);
  assert.equal(published.state.isPlaying, true);
});

test('shuffle and repeat mode RPCs serialize so delayed snapshots preserve both flags', async () => {
  const shuffleResponse = deferred();
  const repeatResponse = deferred();
  const calls = [];
  const player = new PlaybackController(async (command, args) => {
    if (command === 'get_playback_state') return state(9);
    calls.push({ command, args });
    if (command === 'set_shuffle') return shuffleResponse.promise;
    if (command === 'set_repeat') return repeatResponse.promise;
    throw new Error(command);
  }, async () => () => {}, () => {});
  await player.connect();
  const shuffle = player.setShuffle(true);
  const repeat = player.setRepeat(true);
  await settle();
  assert.deepEqual(calls, [{ command: 'set_shuffle', args: { enabled: true } }]);
  shuffleResponse.resolve(state(9, { isShuffle: true, isRepeat: false }));
  await settle();
  assert.deepEqual(calls, [
    { command: 'set_shuffle', args: { enabled: true } },
    { command: 'set_repeat', args: { enabled: true } },
  ]);
  repeatResponse.resolve(state(9, { isShuffle: true, isRepeat: true }));
  await Promise.all([shuffle, repeat]);
  assert.equal(player.snapshot.state.isShuffle, true);
  assert.equal(player.snapshot.state.isRepeat, true);
});

test('a later full playback event beats a stale mode response, and mode failures stay visible', async () => {
  const listeners = new Map();
  const response = deferred();
  let failRepeat = false;
  let published;
  const player = new PlaybackController(async command => {
    if (command === 'get_playback_state') return state(7);
    if (command === 'set_shuffle') return response.promise;
    if (command === 'set_repeat' && failRepeat) throw new Error('repeat unavailable');
    throw new Error(command);
  }, async (event, handler) => { listeners.set(event, handler); return () => {}; }, next => published = next);
  await player.connect();
  const pendingShuffle = player.setShuffle(true);
  await settle();
  listeners.get('playback-state-changed')({ payload: state(7, { isShuffle: true }) });
  response.resolve(state(7, { isShuffle: false }));
  await pendingShuffle;
  assert.equal(published.state.isShuffle, true);

  failRepeat = true;
  await assert.rejects(player.setRepeat(true), /repeat unavailable/);
  assert.equal(published.error, 'repeat unavailable');
});

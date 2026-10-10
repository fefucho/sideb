import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const source = await readFile(new URL('../src/lib/account/controller.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { AccountController, appendSongs } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const song = (id, extra = {}) => ({ videoId: id, title: id, artists: 'Artist', album: null, duration: null, thumbnail: null, isVideo: false, artistId: null, albumId: null, ...extra });
const playlist = items => ({ id: 'LM', title: 'Tus Me Gusta', items, continuation: null, thumbnail: null, subtitle: null, description: null, owned: false, inLibrary: false });
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; }

test('account reset discards old library response and metadata', async () => {
  const request = deferred(); let data;
  const account = new AccountController(() => request.promise, next => data = next);
  account.reset(true); const load = account.load('songs'); account.reset(false);
  request.resolve({ items: [song('private', { library: { addToken: 'opaque' } })], continuation: 'private-token' });
  await load; assert.equal(data.loggedIn, false); assert.deepEqual(data.songs, []); assert.equal(data.songContinuation, null);
});
test('failed like keeps server state, exposes error and prevents double submission', async () => {
  const mutation = deferred(); const calls = []; let data;
  const account = new AccountController(async (command, args) => {
    calls.push({ command, args }); if (command === 'get_playlist') return playlist([song('a')]);
    if (command === 'rate_song') return mutation.promise;
  }, next => data = next);
  account.reset(true); await account.hydrateLikes();
  const first = account.toggleLike(song('a')); await account.toggleLike(song('a'));
  assert.equal(calls.filter(call => call.command === 'rate_song').length, 1);
  mutation.reject({ message: 'Provider unavailable' }); await first;
  assert.equal(data.likedIds.has('a'), true); assert.equal(data.pendingIds.size, 0); assert.equal(data.actionError, 'Provider unavailable');
  assert.equal(calls.at(-1).args.rating, 'INDIFFERENT');
});
test('dislike sends DISLIKE and removes the liked state, restoring it when the provider fails', async () => {
  const mutation = deferred(); const calls = []; let data;
  const account = new AccountController(async (command, args) => {
    calls.push({ command, args }); if (command === 'get_playlist') return playlist([song('a')]);
    if (command === 'rate_song') return mutation.promise;
  }, next => data = next);
  account.reset(true); await account.hydrateLikes();
  const pending = account.dislike(song('a'));
  assert.equal(data.likedIds.has('a'), false); assert.equal(data.pendingIds.has('a'), true);
  assert.equal(calls.at(-1).args.rating, 'DISLIKE');
  mutation.reject(new Error('Provider unavailable')); assert.equal(await pending, false);
  assert.equal(data.likedIds.has('a'), true); assert.equal(data.pendingIds.size, 0);
  assert.equal(data.actionError, 'Provider unavailable');
});
test('saving a song uses its feedback token independently of like IDs', async () => {
  const saved = song('a', { library: { inLibrary: false, addToken: 'opaque-add', removeToken: 'opaque-remove' } });
  const calls = []; let data;
  const account = new AccountController(async (command, args) => {
    calls.push({ command, args });
    if (command === 'get_library_songs') return { items: [{ ...saved, library: { ...saved.library, inLibrary: true } }], continuation: null };
  }, next => data = next);
  account.reset(true); await account.toggleSaved(saved);
  assert.equal(calls[0].command, 'apply_song_library_action'); assert.equal(calls[0].args.token, 'opaque-add');
  assert.equal(calls.some(call => call.command === 'rate_song'), false); assert.equal(data.likedIds.size, 0); assert.equal(data.songs[0].library.inLibrary, true);
});
test('pagination retries errors and stops repeating tokens without discarding repeated tracks', async () => {
  let tries = 0; let data;
  const account = new AccountController(async command => {
    if (command === 'get_library_songs') return { items: [song('a', { setVideoId: 'entry1' })], continuation: 'page2' };
    if (++tries === 1) throw new Error('temporary');
    return { items: [song('a', { setVideoId: 'entry1' }), song('a', { setVideoId: 'entry2' })], continuation: 'page2' };
  }, next => data = next);
  account.reset(true); await account.load('songs');
  assert.equal(tries,1); assert.equal(data.songs.length,1); assert.ok(data.errors.songs);
  assert.equal(data.songContinuation, 'page2'); await account.loadMoreSongs();
  assert.equal(data.songContinuation, null); assert.equal(data.songs.length, 2);
  assert.equal(appendSongs([song('a')], [song('a')]).length, 2);
});
test('stale mutation success cannot update next account', async () => {
  const mutation = deferred(); let data;
  const account = new AccountController(async command => command === 'get_playlist' ? playlist([song('a')]) : mutation.promise, next => data = next);
  account.reset(true); await account.hydrateLikes(); const pending = account.toggleLike(song('a'));
  account.reset(true); mutation.resolve(); await pending;
  assert.equal(data.likedIds.size, 0); assert.equal(data.pendingIds.size, 0);
});
test('older like pages cannot resurrect a like removed during hydration', async () => {
  const page = deferred(); let data; const calls = [];
  const account = new AccountController(async (command, args) => {
    calls.push({command,args});
    if (command === 'get_playlist') return {...playlist([song('a')]),continuation:'older'};
    if (command === 'get_playlist_continuation') return page.promise;
  }, next => data = next);
  account.reset(true); const hydration = account.hydrateLikes();
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(data.likedIds.has('a'), true);
  await account.toggleLike(song('a'));
  page.resolve({items:[song('a'),song('b')],continuation:null}); await hydration;
  assert.equal(data.likedIds.has('a'), false); assert.equal(data.likedIds.has('b'), true);
  assert.equal(calls.find(call => call.command === 'rate_song').args.rating, 'INDIFFERENT');
});

test('2000 hydrated likes remain available for global shuffle without fetching pages again', async () => {
  const tracks = Array.from({ length: 2000 }, (_, index) => song(`song-${index}`, { setVideoId: `entry-${index}` }));
  const calls = []; let data;
  const account = new AccountController(async (command, args) => {
    calls.push({ command, args });
    if (command === 'get_playlist') return { ...playlist(tracks.slice(0, 100)), continuation: '100' };
    const offset = Number(args.token);
    return { items: tracks.slice(offset, offset + 100), continuation: offset + 100 < tracks.length ? String(offset + 100) : null };
  }, next => data = next);
  account.reset(true);
  await account.hydrateLikes();
  assert.equal(data.likedIds.size, 2000);
  await account.openPlaylist('LM');
  assert.equal(data.playlist.items.length, 100);
  const resolved = await account.resolvePlaylistTracks('VLLM');
  assert.deepEqual(resolved.map(item => item.setVideoId), tracks.map(item => item.setVideoId));
  assert.equal((await account.resolvePlaylistTracks('LM')).length, 2000);
  assert.equal(calls.length, 20);
  account.reset(false);
  await assert.rejects(account.resolvePlaylistTracks('LM'), /Iniciá sesión/);
  account.reset(true);
  await account.resolvePlaylistTracks('LM');
  assert.equal(calls.length, 40);
});

test('play during likes hydration shares the pending catalog and retains older pages', async () => {
  const page = deferred(); const calls = [];
  const account = new AccountController(async (command, args) => {
    calls.push({ command, args });
    if (command === 'get_playlist') return { ...playlist([song('new')]), continuation: 'older' };
    return page.promise;
  }, () => {});
  account.reset(true);
  const hydration = account.hydrateLikes();
  await new Promise(resolve => setTimeout(resolve, 0));
  const resolving = account.resolvePlaylistTracks('LM');
  page.resolve({ items: [song('old')], continuation: null });
  await hydration;
  assert.deepEqual((await resolving).map(item => item.videoId), ['new', 'old']);
  assert.equal(calls.length, 2);
});

test('refresh and successful unlike invalidate the playback catalog', async () => {
  let tracks = [song('a'), song('b')]; let fetches = 0;
  const account = new AccountController(async (command, args) => {
    if (command === 'get_playlist') { ++fetches; return playlist([...tracks]); }
    if (command === 'rate_song') tracks = tracks.filter(item => item.videoId !== args.videoId);
  }, () => {});
  account.reset(true);
  await account.hydrateLikes();
  await account.toggleLike(song('a'));
  assert.deepEqual((await account.resolvePlaylistTracks('LM')).map(item => item.videoId), ['b']);
  assert.equal(fetches, 2);
  tracks = [song('external-like'), ...tracks];
  await account.refreshPlaylist('LM');
  assert.deepEqual((await account.resolvePlaylistTracks('LM')).map(item => item.videoId), ['external-like', 'b']);
});

test('a stale hydration cannot populate the next account playback catalog', async () => {
  const page = deferred(); let fetches = 0;
  const account = new AccountController(async command => {
    if (command === 'get_playlist') return ++fetches === 1
      ? { ...playlist([song('private')]), continuation: 'older' } : playlist([song('next-account')]);
    return page.promise;
  }, () => {});
  account.reset(true);
  const hydration = account.hydrateLikes();
  await new Promise(resolve => setTimeout(resolve, 0));
  const resolving = account.resolvePlaylistTracks('LM');
  account.reset(true);
  page.resolve({ items: [song('private-older')], continuation: null });
  await hydration;
  assert.deepEqual(await resolving, []);
  assert.deepEqual((await account.resolvePlaylistTracks('LM')).map(item => item.videoId), ['next-account']);
});


test('library preload reaches one hundred, keeps accepted prefix on failure and rejects old account pages',async()=>{
  let data;const pending=deferred();let pages=0;
  const account=new AccountController(async command=>command==='get_library_songs'?{items:Array.from({length:50},(_,i)=>song(`first${i}`)),continuation:'second'}:pending.promise,next=>data=next);
  account.reset(true);const load=account.load('songs');await new Promise(resolve=>setTimeout(resolve,0));
  assert.equal(data.songs.length,50);account.reset(true);pending.resolve({items:[song('old-private')],continuation:null});await load;
  assert.equal(data.songs.length,0);
  const active=new AccountController(async command=>command==='get_library_songs'?{items:Array.from({length:50},(_,i)=>song(`first${i}`)),continuation:'second'}:{items:Array.from({length:50},(_,i)=>song(`next${i}`)),continuation:'third'},next=>data=next);
  active.reset(true);await active.load('songs');assert.equal(data.songs.length,100);assert.equal(data.songContinuation,'third');
});

test('saved albums use stable alphabetical order, playlists retain provider order',async()=>{
  let data;const cards=[{id:'z',title:'Zulu'},{id:'b',title:'Árbol'},{id:'a',title:'Árbol'}];
  const account=new AccountController(async()=>cards,next=>data=next);account.reset(true);await account.load('albums');
  assert.deepEqual(data.albums.map(c=>c.id),['b','a','z']);await account.load('playlists');assert.deepEqual(data.playlists.map(c=>c.id),['z','b','a']);
});

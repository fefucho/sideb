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
  account.reset(true); await account.load('songs'); await account.loadMoreSongs();
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

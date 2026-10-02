import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/account/controller.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { AccountController } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const song = (videoId, setVideoId) => ({ videoId, setVideoId, title: videoId, artists: 'Artist', album: null, duration: null, thumbnail: null, isVideo: false, artistId: null, albumId: null });
const playlist = (items, continuation = null) => ({ id: 'VLp', title: 'Playlist', items, continuation, thumbnail: null, subtitle: null, description: null, owned: true, inLibrary: false, privacy: 'PRIVATE', collaborative: false, sort: 'default', sortEditable: true });
function deferred() { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; }

test('resolve playlist follows pages and retains repeated songs with distinct occurrence IDs', async () => {
  const calls = [];
  const account = new AccountController(async (command, args) => {
    calls.push({ command, args });
    if (command === 'get_playlist') return playlist([song('same', 'entry-a')], 'page-2');
    return { items: [song('same', 'entry-a'), song('same', 'entry-b')], continuation: null };
  }, () => {});
  account.reset(true);
  const tracks = await account.resolvePlaylistTracks('VLp');
  assert.deepEqual(tracks.map(item => item.setVideoId), ['entry-a', 'entry-b']);
  assert.equal(calls.filter(item => item.command === 'get_playlist_continuation').length, 1);
});

test('a looping continuation fails instead of returning a partial playlist for global shuffle', async () => {
  const account = new AccountController(async command => command === 'get_playlist'
    ? playlist([song('first', 'first')], 'next')
    : { items: [song('second', 'second')], continuation: 'next' }, () => {});
  account.reset(true);
  await assert.rejects(account.resolvePlaylistTracks('VLp'), /repitió una página/);
});

test('playback reuses displayed pages and the complete catalog on subsequent plays', async () => {
  const calls = [];
  const account = new AccountController(async (command, args) => {
    calls.push({ command, args });
    if (command === 'get_playlist') return playlist([song('first', 'first')], 'next');
    return { items: [song('older', 'older')], continuation: null };
  }, () => {});
  account.reset(true);
  await account.openPlaylist('VLp');
  await account.loadMorePlaylist();
  const tracks = await account.resolvePlaylistTracks('VLp');
  assert.deepEqual(tracks.map(item => item.videoId), ['first', 'older']);
  tracks.pop();
  assert.equal((await account.resolvePlaylistTracks('p')).length, 2);
  assert.equal(calls.length, 2);
});

test('page errors remain recoverable and never cache a partial playback catalog', async () => {
  let tries = 0;
  const account = new AccountController(async command => {
    if (command === 'get_playlist') return playlist([song('first', 'first')], 'next');
    if (++tries === 1) throw new Error('network down');
    return { items: [song('older', 'older')], continuation: null };
  }, () => {});
  account.reset(true);
  await assert.rejects(account.resolvePlaylistTracks('VLp'), /network down/);
  assert.equal((await account.resolvePlaylistTracks('VLp')).length, 2);
  assert.equal(tries, 2);
});

test('guest playback can resolve a public playlist while Me Gusta remains protected', async () => {
  const account = new AccountController(async (command) => {
    assert.equal(command, 'get_playlist');
    return playlist([song('public-song', 'public-entry')]);
  }, () => {});
  account.reset(false);
  assert.equal((await account.resolvePlaylistTracks('VLpublic')).length, 1);
  await assert.rejects(account.resolvePlaylistTracks('LM'), /Iniciá sesión/);
  await assert.rejects(account.resolvePlaylistTracks('VLLM'), /Iniciá sesión/);
});

test('resolve playlist returns no partial queue when session changes between pages', async () => {
  const page = deferred(); let data;
  const account = new AccountController(async command => command === 'get_playlist'
    ? playlist([song('first', 'first')], 'next') : page.promise, next => data = next);
  account.reset(true);
  const resolving = account.resolvePlaylistTracks('VLp');
  await new Promise(resolve => setTimeout(resolve, 0));
  account.reset(false);
  page.resolve({ items: [song('second', 'second')], continuation: null });
  assert.deepEqual(await resolving, []);
  assert.equal(data.loggedIn, false);
});

test('playlist mutations send occurrence identity, guard repeat submission and surface failures', async () => {
  const mutation = deferred(); const calls = []; let data;
  const account = new AccountController(async (command, args) => { calls.push({ command, args }); return mutation.promise; }, next => data = next);
  account.reset(true);
  const entry = song('video', 'occurrence-7');
  const first = account.removeFromPlaylist('VLp', entry);
  await assert.rejects(account.removeFromPlaylist('VLp', entry), /cambio en curso/);
  assert.deepEqual(calls[0], { command: 'remove_from_playlist', args: { playlistId: 'VLp', videoId: 'video', setVideoId: 'occurrence-7' } });
  mutation.resolve(); await first;
  assert.equal(data.pendingIds.size, 0);
  const failure = new AccountController(async () => { throw new Error('network down'); }, next => data = next);
  failure.reset(true);
  await assert.rejects(failure.editPlaylistDetails('VLp', { name: 'Changed', description: '', privacy: 'PRIVATE' }), /network down/);
  assert.equal(data.actionError, 'network down'); assert.equal(data.pendingIds.size, 0);
});

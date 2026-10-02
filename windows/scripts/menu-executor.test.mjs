import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const source = await readFile(new URL('../src/lib/menu/executor.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { MenuExecutor } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const playlist = { kind: 'playlist', card: { id: 'PL', title: 'Playlist', thumbnail: null } };
test('bulk menu action delegates full playlist resolution and preserves occurrences', async () => {
  const songs = [{ videoId: 'same', setVideoId: 'a' }, { videoId: 'same', setVideoId: 'b' }]; let added;
  const executor = new MenuExecutor({ begin: () => () => true, resolvePlaylist: async () => songs, enqueue: async (tracks, position) => added = { tracks, position } });
  await executor.execute({ type: 'enqueue-next' }, playlist, {});
  assert.deepEqual(added, { tracks: songs, position: 'next' });
});
test('late collection load does not supersede a later playback or navigation intent', async () => {
  let valid = true, resolve, plays = 0;
  const executor = new MenuExecutor({ begin: () => () => valid, resolvePlaylist: () => new Promise(yes => resolve = yes), play: async () => plays++ });
  const pending = executor.execute({ type: 'play' }, playlist, {});
  valid = false; resolve([{ videoId: 'old' }]); await pending;
  assert.equal(plays, 0);
});
test('radio action uses core-resolved artist endpoint, then a song radio seed', async () => {
  const calls = []; let seed;
  const executor = new MenuExecutor({ begin: () => () => true, rpc: async (command, args) => {
    calls.push({ command, args }); return command === 'get_artist' ? { radioPlaylistId: 'RDartist' } : [{ videoId: 'song' }];
  }, radio: async song => seed = song });
  await executor.execute({ type: 'radio' }, { kind: 'artist', card: { id: 'UCartist', title: 'Artist' } }, {});
  assert.equal(calls[1].args.playlistId, 'RDartist'); assert.equal(seed.videoId, 'song');
});
test('remove song from playlist passes full occurrence metadata and origin, sharing canonicalizes VL only', async () => {
  let removed, url;
  const executor = new MenuExecutor({ begin: () => () => true, removePlaylistSong: async (...args) => removed = args, copy: async value => url = value });
  const song = { videoId: 'same', setVideoId: 'second' };
  await executor.execute({ type: 'remove-playlist' }, { kind: 'song', song }, { playlistId: 'PL' });
  assert.deepEqual(removed, ['PL', song]);
  await executor.execute({ type: 'share' }, { kind: 'playlist', card: { id: 'VLPLcase' } }, {});
  assert.equal(url, 'https://music.youtube.com/playlist?list=PLcase');
});

import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const source = await readFile(new URL('../src/lib/menu/executor.ts', import.meta.url), 'utf8');
const metadataSource=await readFile(new URL("../src/lib/detail/metadata.ts",import.meta.url),"utf8");
const metadataJS=ts.transpileModule(metadataSource,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const metadataURL=`data:text/javascript;base64,${Buffer.from(metadataJS).toString("base64")}`;
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText.replace("'../detail/metadata'",JSON.stringify(metadataURL));
const { MenuExecutor } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const playlist = { kind: 'playlist', card: { id: 'PL', title: 'Playlist', thumbnail: null } };
test('bulk menu action delegates full playlist resolution and preserves occurrences', async () => {
  const songs = [{ videoId: 'same', setVideoId: 'a' }, { videoId: 'same', setVideoId: 'b' }]; let added;
  const executor = new MenuExecutor({ begin: () => () => true, resolvePlaylist: async () => songs, enqueue: async (tracks, position) => added = { tracks, position } });
  await executor.execute({ type: 'enqueue-next' }, playlist, {});
  assert.deepEqual(added, { tracks: songs, position: 'next' });
});
test('playlist and album shuffle menus pass the canonical full collection and shuffle intent', async () => {
  const tracks = [{ videoId: 'first', title: 'First' }, { videoId: 'same', title: 'Second', setVideoId: 'a' }, { videoId: 'same', title: 'Third', setVideoId: 'b' }];
  const plays = [];
  const executor = new MenuExecutor({ begin: () => () => true, resolvePlaylist: async () => tracks,
    play: async (...args) => plays.push(args) });
  await executor.execute({ type: 'shuffle' }, playlist, {});
  await executor.execute({ type: 'shuffle' }, { kind: 'album', card: { id: 'album-id', title: 'Album', thumbnail: null },
    detail: { items: tracks, browseId: 'album-id', title: 'Album', thumbnail: null, artist: 'Artist', artistId: 'artist-id' } }, {});
  assert.equal(plays.length, 2);
  for (const [songs, _source, shuffle] of plays) {
    assert.deepEqual(songs.map(song => song.title), ['First', 'Second', 'Third']);
    assert.equal(shuffle, true);
    assert.equal(songs[1].setVideoId, 'a');
    assert.equal(songs[2].setVideoId, 'b');
  }
});
test('late collection load does not supersede a later playback or navigation intent', async () => {
  let valid = true, resolve, plays = 0;
  const executor = new MenuExecutor({ begin: () => () => valid, resolvePlaylist: () => new Promise(yes => resolve = yes), play: async () => plays++ });
  const pending = executor.execute({ type: 'play' }, playlist, {});
  valid = false; resolve([{ videoId: 'old' }]); await pending;
  assert.equal(plays, 0);
});
test('source-card playback forwards its scope through the deferred collection load', async () => {
  let navigation = 0, playIntent = 0, release, plays = 0;
  const observed = [];
  const executor = new MenuExecutor({
    begin: (play, origin) => {
      observed.push({ play, origin });
      const capturedNavigation = navigation, capturedIntent = playIntent;
      return () => capturedIntent === playIntent && (origin.playbackScope === 'source' || capturedNavigation === navigation);
    },
    resolvePlaylist: (_id, _valid, resolutionOrigin) => {
      assert.equal(resolutionOrigin, origin);
      return new Promise(resolve => release = resolve);
    },
    play: async () => plays++
  });
  const origin = { playbackScope: 'source' };
  const first = executor.execute({ type: 'play' }, playlist, origin);
  navigation++; release([{ videoId: 'first' }]); await first;
  assert.equal(plays, 1);
  assert.deepEqual(observed[0], { play: true, origin });
  const second = executor.execute({ type: 'play' }, playlist, origin);
  playIntent++; release([{ videoId: 'obsolete' }]); await second;
  assert.equal(plays, 1);
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

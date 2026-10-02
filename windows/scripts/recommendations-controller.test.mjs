import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/player/recommendations.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { RecommendationsController } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const track = (videoId, fields = {}) => ({ videoId, title: videoId, artists: 'Artist', thumbnail: null, duration: 120, artistId: 'artist', albumId: 'album', album: 'Album', ...fields });
const song = (videoId) => ({ ...track(videoId), duration: '2:00', artistRuns: [{ text: 'Artist', id: 'artist' }], isVideo: false });
const card = (id, kind = 'artist') => ({ kind, id, title: id, subtitle: null, thumbnail: null, duration: null });
const artist = (topSongs = [], sections = []) => ({ name: 'Artist name', topSongs, sections });
const album = (items = []) => ({ title: 'Album name', items });
function deferred() { let resolve; let reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }
function setup(handler) {
  const calls = []; let snapshot;
  const controller = new RecommendationsController(async (command, args) => { calls.push([command, args]); return handler(command, args); }, value => { snapshot = value; });
  return { controller, calls, snapshot: () => snapshot };
}
const emptyHandler = command => command === 'get_artist' ? artist() : command === 'get_album' ? album() : [];

test('recommendations load all four Mac shelves without the current song and retain metadata', async () => {
  const { controller, calls, snapshot } = setup(command => ({
    get_related_tracks: [song('current'), song('similar')], get_related_artists: [card('related')],
    get_artist: artist([song('current'), song('popular')]), get_album: album([song('current'), song('album-song')]),
  })[command]);
  controller.setTrack(track('current')); await controller.load();
  assert.equal(calls.length, 4);
  const data = snapshot().data;
  assert.deepEqual(data.artistSongs.map(song => song.videoId), ['popular']);
  assert.deepEqual(data.albumSongs.map(song => song.videoId), ['album-song']);
  assert.deepEqual(data.similarSongs.map(song => song.videoId), ['similar']);
  assert.equal(data.relatedArtists[0].id, 'related');
  assert.equal(data.similarSongs[0].artistRuns[0].id, 'artist');
  assert.equal(data.similarSongs[0].albumId, 'album');
  assert.equal(data.artistName, 'Artist name');
  assert.equal(data.albumTitle, 'Album name');
  assert.equal(snapshot().loading, false); assert.equal(snapshot().error, null);
});

test('related artists use artist-profile fallback when the song endpoint is empty', async () => {
  const { controller, snapshot } = setup(command => command === 'get_artist'
    ? artist([], [{ title: 'A los fans también les gusta', items: [card('artist-related'), card('not-artist', 'album')] }]) : emptyHandler(command));
  controller.setTrack(track('current')); await controller.load();
  assert.deepEqual(snapshot().data.relatedArtists.map(card => card.id), ['artist-related']);
});

test('late requests cannot replace a newer song', async () => {
  const late = deferred();
  const { controller, snapshot } = setup((command, args) => command === 'get_related_tracks' && args.videoId === 'old' ? late.promise : emptyHandler(command));
  controller.setTrack(track('old')); const oldLoad = controller.load();
  controller.setTrack(track('new')); await controller.load();
  late.resolve([song('stale')]); await oldLoad;
  assert.equal(snapshot().data.loadedVideoId, 'new'); assert.deepEqual(snapshot().data.similarSongs, []);
});

test('account reset discards pending responses and private data', async () => {
  const late = deferred();
  const { controller, snapshot } = setup(command => command === 'get_related_tracks' ? late.promise : emptyHandler(command));
  controller.setTrack(track('private')); const load = controller.load(); controller.reset();
  late.resolve([song('private-related')]); await load;
  assert.deepEqual(snapshot(), { loading: false, error: null, data: null });
});

test('partial errors keep successful shelves and retry only on explicit refresh', async () => {
  let broken = true;
  const { controller, snapshot, calls } = setup(command => {
    if (command === 'get_related_tracks') { if (broken) throw new Error('signed-provider-url'); return [song('recovered')]; }
    return command === 'get_album' ? album([song('available')]) : emptyHandler(command);
  });
  controller.setTrack(track('current')); await controller.load();
  assert.equal(snapshot().data.albumSongs[0].videoId, 'available');
  assert.match(snapshot().error, /reintentar/); assert.doesNotMatch(snapshot().error, /signed-provider/);
  const count = calls.length;
  for (let index = 0; index < 4; index++) { controller.setTrack(track('current')); await controller.load(); }
  assert.equal(calls.length, count);
  broken = false; await controller.load(true);
  assert.equal(snapshot().error, null); assert.equal(snapshot().data.similarSongs[0].videoId, 'recovered');
});

test('same-song metadata enrichment adds album shelf and progress does not reload', async () => {
  const { controller, calls, snapshot } = setup(command => command === 'get_album' ? album([song('album-song')]) : emptyHandler(command));
  controller.setTrack(track('current', { artistId: null, albumId: null, album: null })); await controller.load();
  assert.equal(calls.length, 2);
  controller.setTrack(track('current')); await controller.load();
  assert.equal(calls.length, 6); assert.equal(snapshot().data.albumSongs[0].videoId, 'album-song');
  controller.setTrack(track('current')); await controller.load(); assert.equal(calls.length, 6);
});

test('refresh rotates related songs like Mac and coalesces repeated lazy loads', async () => {
  const late = deferred(); let first = true;
  const songs = Array.from({ length: 6 }, (_, index) => song(`similar-${index}`));
  const { controller, calls, snapshot } = setup(command => command === 'get_related_tracks' ? (first ? late.promise : songs) : emptyHandler(command));
  controller.setTrack(track('current')); const load = controller.load(); const same = controller.load();
  assert.equal(same, load); assert.equal(calls.length, 4);
  late.resolve(songs); await load; first = false;
  await controller.load(true);
  assert.deepEqual(snapshot().data.similarSongs.map(song => song.videoId), ['similar-4', 'similar-5', 'similar-0', 'similar-1', 'similar-2', 'similar-3']);
});

test('all-empty responses remain an empty state and exported snapshots cannot mutate the controller', async () => {
  const { controller, snapshot } = setup(command => command === 'get_related_tracks' ? [song('related')] : emptyHandler(command));
  controller.setTrack(track('current')); await controller.load();
  snapshot().data.similarSongs[0].artistRuns[0].text = 'mutated';
  assert.equal(controller.snapshot.data.similarSongs[0].artistRuns[0].text, 'Artist');
  const empty = setup(emptyHandler); empty.controller.setTrack(track('empty')); await empty.controller.load();
  assert.deepEqual(empty.snapshot().data.similarSongs, []); assert.equal(empty.snapshot().error, null);
});

test('album shelves enrich missing metadata from their detail without rewriting guest credits', async () => {
  const guest = { ...song('guest'), artists: 'Artist & Guest', artistRuns: [{ text: 'Artist', id: 'artist' }, { text: 'Guest', id: 'guest-id' }], album: null, albumId: null };
  const { controller, snapshot } = setup(command => command === 'get_album'
    ? { ...album([guest]), browseId: 'album', artistId: 'artist', artist: 'Artist', artistRuns: [{ text: 'Artist', id: 'artist' }] }
    : emptyHandler(command));
  controller.setTrack(track('current')); await controller.load();
  const result = snapshot().data.albumSongs[0];
  assert.equal(result.album, 'Album name'); assert.equal(result.albumId, 'album');
  assert.deepEqual(result.artistRuns.map(run => run.id), ['artist', 'guest-id']);
});

test('failed explicit refresh retains previously loaded usable shelves', async () => {
  let failed = false;
  const { controller, snapshot } = setup(command => {
    if (failed) throw new Error('provider-unavailable');
    return command === 'get_related_tracks' ? [song('retained')] : emptyHandler(command);
  });
  controller.setTrack(track('current')); await controller.load(); failed = true; await controller.load(true);
  assert.equal(snapshot().data.similarSongs[0].videoId, 'retained'); assert.match(snapshot().error, /reintentar/);
});

import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/catalog/controller.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { CatalogController, emptyCatalogData } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

function deferred() {
  let resolve; let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const album = (browseId) => ({ browseId, title: browseId, artist: null, subtitle: null, secondSubtitle: null,
  description: null, thumbnail: null, items: [], artistId: null, playlistId: null, inLibrary: false, sections: [] });
const artist = (channelId) => ({ channelId, name: channelId, thumbnail: null, description: null, subscribers: null,
  monthlyListeners: null, subscribed: false, radioPlaylistId: null, topSongs: [], topSongsId: null, sections: [] });
const card = (id) => ({ kind: 'album', id, title: id, subtitle: null, thumbnail: null, duration: null });

test('late album cannot replace current artist state', async () => {
  const albumResponse = deferred(); let snapshot;
  const controller = new CatalogController((command) => command === 'get_album' ? albumResponse.promise : Promise.resolve(artist('artist-current')), (data) => { snapshot = data; });
  const albumLoad = controller.openAlbum('album-old');
  await controller.openArtist('artist-current');
  albumResponse.resolve(album('album-old'));
  await albumLoad;
  assert.equal(snapshot.artistId, 'artist-current');
  assert.equal(snapshot.artist.name, 'artist-current');
  assert.equal(snapshot.album, null);
  assert.equal(snapshot.albumLoading, false);
});

test('navigation away cancels a pending catalog grid response', async () => {
  const gridResponse = deferred(); let snapshot;
  const controller = new CatalogController(async (command) => command === 'get_browse_grid' ? gridResponse.promise : album('next-album'), (data) => { snapshot = data; });
  const gridLoad = controller.openGrid('browse-id', 'params', 'Albums');
  const previousIdentity = controller.captureIdentity();
  controller.invalidate();
  assert.equal(controller.isCurrentIdentity(previousIdentity), false);
  assert.equal(snapshot.loading, false);
  gridResponse.resolve([card('stale-card')]);
  await gridLoad;
  assert.deepEqual(snapshot.items, []);
  assert.equal(snapshot.target.id, 'browse-id');
});

test('reset discards pending artist response and clears all catalog destinations', async () => {
  const response = deferred(); let snapshot;
  const controller = new CatalogController(() => response.promise, (data) => { snapshot = data; });
  const pending = controller.openArtist('private-account-artist');
  controller.reset();
  response.resolve(artist('private-account-artist'));
  await pending;
  assert.deepEqual(snapshot, emptyCatalogData());
});

test('restoring a navigation snapshot invalidates pending loads without keeping loading flags', async () => {
  const response = deferred(); let snapshot;
  const controller = new CatalogController(() => response.promise, (data) => { snapshot = data; });
  const pending = controller.openAlbum('album-pending');
  const restored = { ...emptyCatalogData(), album: album('album-saved'), albumId: 'album-saved',
    artist: artist('artist-saved'), artistId: 'artist-saved', items: [card('card-saved')],
    target: { id: 'browse-saved', params: null, title: 'Saved grid' }, albumLoading: true, artistLoading: true, loading: true };
  controller.restore(restored);
  response.resolve(album('late-album'));
  await pending;
  assert.equal(snapshot.albumId, 'album-saved');
  assert.equal(snapshot.album.title, 'album-saved');
  assert.equal(snapshot.artist.name, 'artist-saved');
  assert.equal(snapshot.items[0].id, 'card-saved');
  assert.equal(snapshot.albumLoading || snapshot.artistLoading || snapshot.loading, false);
});

test('album and artist updates publish cloned immutable snapshots', async () => {
  let snapshot; const controller = new CatalogController(async (command) => command === 'get_album' ? album('album') : artist('artist'), (data) => { snapshot = data; });
  await controller.openAlbum('album');
  const original = snapshot.album;
  controller.updateAlbum((value) => ({ ...value, inLibrary: true }));
  assert.equal(snapshot.album.inLibrary, true);
  assert.equal(original.inLibrary, false);
  await controller.openArtist('artist');
  controller.updateArtist((value) => ({ ...value, subscribed: true }));
  assert.equal(snapshot.artist.subscribed, true);
});

test('failed destination load records its view error and clears loading', async () => {
  let snapshot;
  const controller = new CatalogController(async () => { throw { message: 'catalog unavailable' }; }, (data) => { snapshot = data; });
  await controller.openGrid('browse', null, 'Browse');
  assert.equal(snapshot.error, 'catalog unavailable');
  assert.equal(snapshot.loading, false);
});

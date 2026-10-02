import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const source = await readFile(new URL('../src/lib/menu/policy.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { menuItems } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const facts = { loggedIn: true, likedIds: new Set(), playlists: [] };
const card = id => ({ id, kind: 'playlist', title: id, thumbnail: null, subtitle: null, duration: null });
const song = { videoId: 'v', title: 'Song', artists: 'Artist', artistId: 'artist', albumId: 'album', setVideoId: 'occurrence' };
const actions = items => items.filter(item => item.action).map(item => item.action.type);
test('current queue occurrence cannot be played-next or removed but duplicate occurrence can', () => {
  const current = actions(menuItems({ kind: 'song', song, entryId: 'a' }, { currentQueueEntryId: 'a' }, facts));
  assert.ok(!current.includes('play')); assert.ok(!current.includes('remove-queue')); assert.ok(!current.includes('enqueue-next'));
  assert.ok(actions(menuItems({ kind: 'song', song, entryId: 'b' }, { currentQueueEntryId: 'a' }, facts)).includes('remove-queue'));
});
test('guest mutations are disabled and tokens are required for library action', () => {
  const items = menuItems({ kind: 'song', song }, {}, { ...facts, loggedIn: false });
  assert.ok(items.find(item => item.id === 'like').disabled);
  assert.ok(items.find(item => item.id === 'add-playlist').disabled);
  assert.ok(!actions(items).includes('save-song'));
});
test('LM, dynamic radios and unknown ownership do not expose editor or deletion', () => {
  for (const target of [
    { kind: 'playlist', card: card('LM'), detail: { owned: true, sortEditable: true } },
    { kind: 'playlist', card: card('RDmix'), detail: { owned: true, sortEditable: true } },
    { kind: 'playlist', card: card('PLunknown') },
  ]) {
    const list = actions(menuItems(target, {}, facts));
    assert.ok(!list.includes('edit-playlist')); assert.ok(!list.includes('delete-playlist'));
  }
  const radio = actions(menuItems({ kind: 'playlist', card: card('RDmix') }, {}, facts));
  assert.ok(!radio.includes('enqueue-end')); assert.ok(!radio.includes('shuffle'));
});
test('owned playlist has editor, ordered sort submenu and deletion', () => {
  const list = menuItems({ kind: 'playlist', card: card('PLown'), detail: { owned: true, sortEditable: true, sort: 'artist' } }, {}, facts);
  assert.ok(actions(list).includes('edit-playlist'));
  assert.deepEqual(list.find(item => item.id === 'sort-playlist').children.map(item => item.action.sort), ['default','newest','oldest','title','artist','album']);
  assert.ok(list.find(item => item.id === 'sort-playlist').children.find(item => item.checked).action.sort === 'artist');
});
test('remove playlist song requires ownership and exact occurrence ID; current destination links hidden', () => {
  assert.ok(actions(menuItems({ kind: 'song', song }, { playlistOwned: true, playlistId: 'PL', view: 'album_detail', currentId: 'album' }, facts)).includes('remove-playlist'));
  assert.ok(!actions(menuItems({ kind: 'song', song: { ...song, setVideoId: null } }, { playlistOwned: true, playlistId: 'PL' }, facts)).includes('remove-playlist'));
  assert.ok(!actions(menuItems({ kind: 'song', song }, { view: 'album_detail', currentId: 'album' }, facts)).includes('open-album'));
});

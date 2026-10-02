import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/menu/types.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { songFromHome, songFromQueue, targetFromCard } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const artistRuns = [{ text: 'Daft Punk', id: 'UC-daft' }, { text: 'Pharrell Williams', id: 'UC-pharrell' }];
const metadata = { title: 'Lose Yourself to Dance', artists: 'Daft Punk & Pharrell Williams', artistRuns,
  artistId: 'UC-daft', album: 'Random Access Memories', albumId: 'MPRE-album', thumbnail: null };

test('Home, queue and catalog menu conversions preserve album and both artist destinations', () => {
  const home = songFromHome({ ...metadata, id: 'dance', kind: 'song', subtitle: metadata.artists, duration: '3:21' });
  const queue = songFromQueue({ ...metadata, videoId: 'dance', entryId: 'occurrence', duration: 201 });
  const card = targetFromCard({ ...metadata, id: 'dance', kind: 'song', subtitle: metadata.artists, duration: '3:21' }).song;
  for (const converted of [home, queue, card]) {
    assert.deepEqual(converted.artistRuns, artistRuns);
    assert.equal(converted.album, metadata.album);
    assert.equal(converted.albumId, metadata.albumId);
    assert.notEqual(converted.artistRuns, artistRuns);
  }
});

test('legacy tracks remain playable without inventing artist identities', () => {
  const converted = songFromQueue({ videoId: 'v', title: 'Track', artists: 'Earth, Wind & Fire', thumbnail: null, duration: null });
  assert.deepEqual(converted.artistRuns, []);
  assert.equal(converted.artistId, null);
});

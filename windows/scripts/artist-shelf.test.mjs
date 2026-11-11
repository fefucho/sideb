import assert from 'node:assert/strict';
import { test } from 'node:test';
import path from 'node:path';
import { mountedSvelteEnvironment } from './helpers/mount-svelte.mjs';

const { root, moduleFor } = await mountedSvelteEnvironment('artist-shelf');
const lib = file => path.join(root, 'src/lib', file);
const shelf = await import(await moduleFor(lib('detail/artistShelf.ts')));

test('artistShelves synthesizes fallback browse endpoint for Albums when moreBrowseId is missing', () => {
  const sections = [
    {
      title: 'Albums',
      items: [{ kind: 'album', id: 'm1', title: 'Album 1' }],
      moreBrowseId: null,
      moreParams: null,
    },
    {
      title: 'Álbumes',
      items: [{ kind: 'album', id: 'm2', title: 'Album 2' }],
      moreBrowseId: '',
      moreParams: null,
    },
  ];
  const channelId = 'UC1234567890';
  const resolved = shelf.artistShelves(sections, channelId);

  assert.equal(resolved.length, 2);
  assert.equal(resolved[0].moreBrowseId, 'MPADUC1234567890');
  assert.equal(resolved[0].moreParams, shelf.ARTIST_ALBUMS_BROWSE_PARAMS);
  assert.equal(resolved[1].moreBrowseId, 'MPADUC1234567890');
  assert.equal(resolved[1].moreParams, shelf.ARTIST_ALBUMS_BROWSE_PARAMS);
});

test('artistShelves synthesizes fallback browse endpoint for Singles & EPs when moreBrowseId is missing', () => {
  const sections = [
    {
      title: 'Singles & EPs',
      items: [{ kind: 'album', id: 's1', title: 'Single 1' }],
      moreBrowseId: null,
      moreParams: null,
    },
    {
      title: 'Sencillos',
      items: [{ kind: 'album', id: 's2', title: 'Single 2' }],
      moreBrowseId: null,
      moreParams: null,
    },
    {
      title: 'EPs',
      items: [{ kind: 'album', id: 'e1', title: 'EP 1' }],
      moreBrowseId: null,
      moreParams: null,
    },
  ];
  const channelId = 'UC1234567890';
  const resolved = shelf.artistShelves(sections, channelId);

  assert.equal(resolved.length, 3);
  for (const s of resolved) {
    assert.equal(s.moreBrowseId, 'MPADUC1234567890');
    assert.equal(s.moreParams, shelf.ARTIST_SINGLES_BROWSE_PARAMS);
  }
});

test('artistShelves preserves existing moreBrowseId and moreParams', () => {
  const sections = [
    {
      title: 'Albums',
      items: [{ kind: 'album', id: 'm1', title: 'Album 1' }],
      moreBrowseId: 'CUSTOM_BROWSE_ID',
      moreParams: 'CUSTOM_PARAMS',
    },
  ];
  const channelId = 'UC1234567890';
  const resolved = shelf.artistShelves(sections, channelId);

  assert.equal(resolved.length, 1);
  assert.equal(resolved[0].moreBrowseId, 'CUSTOM_BROWSE_ID');
  assert.equal(resolved[0].moreParams, 'CUSTOM_PARAMS');
});

test('artistShelves does not synthesize fallback for non-album sections or invalid channel IDs', () => {
  const sections = [
    {
      title: 'Featured on',
      items: [{ kind: 'playlist', id: 'p1', title: 'Playlist 1' }],
      moreBrowseId: null,
      moreParams: null,
    },
    {
      title: 'Albums',
      items: [{ kind: 'album', id: 'm1', title: 'Album 1' }],
      moreBrowseId: null,
      moreParams: null,
    },
  ];

  // Channel ID not starting with UC
  const resolvedNonUC = shelf.artistShelves(sections, 'custom-id');
  assert.equal(resolvedNonUC[0].moreBrowseId, null);
  assert.equal(resolvedNonUC[1].moreBrowseId, null);

  // Valid channel ID: Featured on untouched, Albums resolved
  const resolvedUC = shelf.artistShelves(sections, 'UC999');
  assert.equal(resolvedUC[0].moreBrowseId, null);
  assert.equal(resolvedUC[1].moreBrowseId, 'MPADUC999');
  assert.equal(resolvedUC[1].moreParams, shelf.ARTIST_ALBUMS_BROWSE_PARAMS);
});

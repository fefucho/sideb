import assert from 'node:assert/strict';
import {test} from 'node:test';
import {loadJam} from './helpers/jam-modules.mjs';
import {song} from './helpers/jam-harness.mjs';

const {normalize, durationSeconds, rankCandidates, lookupResult, matchQuery} = await loadJam('matcher');
const track = (title, artists, seconds) => ({uri: 'spotify:track:x', title, artists, album: null, durationMs: seconds * 1000, isrc: null, provider: null});

test('same recording wins over a video and over another version', () => {
  const ranked = rankCandidates(track('Sueño Stereo', ['Soda Stereo'], 200), [
    song('video', 'Sueño Stereo', 'Soda Stereo', '3:20', {isVideo: true}),
    song('live', 'Sueño Stereo (En Vivo)', 'Soda Stereo', '5:02'),
    song('album', 'Sueno Stereo - Remasterizado 2007', 'Soda Stereo', '3:20')
  ]);
  assert.equal(ranked[0].song.videoId, 'album');
  assert.equal(ranked[0].isConfident, true);
  assert.equal(ranked[0].durationDelta, 0);
});

test('an unrelated result is not accepted', () => {
  const ranked = rankCandidates(track('Persiana Americana', ['Soda Stereo'], 290), [song('other', 'Otra canción', 'Otro artista', '2:10')]);
  assert.equal(ranked[0].isConfident, false);
});

test('durations and names are normalised', () => {
  assert.equal(durationSeconds('3:20'), 200);
  assert.equal(durationSeconds('1:02:03'), 3723);
  assert.equal(durationSeconds('x'), null);
  assert.equal(durationSeconds(''), null);
  assert.equal(durationSeconds('1::2'), null);
  assert.equal(normalize('Canción (feat. Otro) [Deluxe]'), 'cancion');
  assert.equal(matchQuery(track('A', ['B', 'C'], 1)), 'A B');
});

test('ties keep the search order', () => {
  const ranked = rankCandidates(track('Same', ['Same'], 100), [song('a', 'Same', 'Same', '1:40'), song('b', 'Same', 'Same', '1:40')]);
  assert.deepEqual(ranked.map(entry => entry.song.videoId), ['a', 'b']);
});

test('a thrown error is a failure, never "no match"; an empty successful search is', () => {
  assert.equal(lookupResult({ok: false, error: new Error('boom')}).kind, 'failed');
  assert.equal(lookupResult({ok: false, error: {code: 'SEARCH_FAILED'}}).reason, 'SEARCH_FAILED');
  const empty = lookupResult({ok: true, ranked: []});
  assert.deepEqual(empty, {kind: 'noMatch', candidateCount: 0, bestScore: null});
});

test('a low-score result is "no match" with count and best score; an override wins', () => {
  const ranked = rankCandidates(track('Sorry', ['Justin Bieber'], 200.786), [song('x', 'Other', 'Someone', '1:00')]);
  const result = lookupResult({ok: true, ranked});
  assert.equal(result.kind, 'noMatch');
  assert.equal(result.candidateCount, 1);
  assert.equal(lookupResult({ok: true, ranked}, 'x').kind, 'matched');
});

test('realistic rows match confidently', () => {
  const cases = [
    [track('Sorry', ['Justin Bieber'], 200.786), song('a', 'Sorry', 'Justin Bieber', '3:21')],
    [track('Hvnly (feat. JIHYO)', ['Jenevieve', 'JIHYO'], 160), song('b', 'Hvnly (feat. JIHYO)', 'Jenevieve, JIHYO', '2:40')],
    [track('Obsessed (feat. Mariah Carey)', ['Gucci Mane', 'Mariah Carey'], 180), song('c', 'Obsessed (feat. Mariah Carey)', 'Gucci Mane & Mariah Carey', '3:00')]
  ];
  for (const [spotify, ytm] of cases) {
    const result = lookupResult({ok: true, ranked: rankCandidates(spotify, [ytm])});
    assert.equal(result.kind, 'matched', spotify.title);
    assert.equal(result.song.videoId, ytm.videoId);
  }
});

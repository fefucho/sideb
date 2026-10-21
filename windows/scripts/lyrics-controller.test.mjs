import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/player/lyrics.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { LyricsController, activeLyricIndex, lyricSeekSeconds } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const lyrics = (starts, isSynced = true) => ({ provider: 'LRCLIB', isSynced, lines: starts.map((timeMs, index) => ({ timeMs, endTimeMs: null, text: `Line ${index}` })) });
const track = videoId => ({ videoId, title: 'Song', artists: 'Artist', album: 'Album', duration: 120, thumbnail: null });
const settle = () => new Promise(resolve => setTimeout(resolve, 0));
function deferred() {
  let resolve; let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

test('lyric timing matches macOS before first line, backwards seeks, unsorted and untimed rows', () => {
  const info = lyrics([null, 5000, 2000, null, 8000]);
  assert.equal(activeLyricIndex(info, 0), 2);
  assert.equal(activeLyricIndex(info, 6), 1);
  assert.equal(activeLyricIndex(info, 3), 2);
  assert.equal(activeLyricIndex(info, 9), 4);
  assert.equal(activeLyricIndex(info, -1), 2);
  assert.equal(activeLyricIndex(info, Number.NaN), null);
  assert.equal(activeLyricIndex(lyrics([null, null]), 1), null);
  assert.equal(activeLyricIndex(lyrics([1000], false), 2), null);
  assert.equal(activeLyricIndex(lyrics([1000, 1000]), 2), 1);
});

test('line seeking clamps within audio duration and untimed lyrics cannot seek', () => {
  assert.equal(lyricSeekSeconds({ timeMs: 2500 }, 120), 2.5);
  assert.equal(lyricSeekSeconds({ timeMs: 150000 }, 120), 120);
  assert.equal(lyricSeekSeconds({ timeMs: -100 }, 120), null);
  assert.equal(lyricSeekSeconds({ timeMs: null }, 120), null);
  assert.equal(lyricSeekSeconds({ timeMs: 1000 }, 0), 1);
  assert.equal(lyricSeekSeconds({ timeMs: 1000 }, Number.NaN), 1);
  assert.equal(lyricSeekSeconds({ timeMs: 3418 }, undefined), 3.418);
  assert.equal(lyricSeekSeconds({ timeMs: 3418 }, null, 100), 3.318);
  assert.equal(lyricSeekSeconds({ timeMs: 100 }, 120, 500), 0);
  assert.equal(lyricSeekSeconds({ timeMs: Number.NaN }, 120), null);
});

test('controller loads the Mac core contract once per track generation and retains plain lyrics', async () => {
  const calls = []; let published;
  const controller = new LyricsController(async (command, args) => { calls.push({ command, args }); return lyrics([null, null], false); }, state => published = state);
  controller.setTrack(track('a'), 1, 125.5);
  await settle();
  assert.deepEqual(calls[0], { command: 'get_lyrics', args: { videoId: 'a', title: 'Song', artists: 'Artist', album: 'Album', duration: 125.5 } });
  assert.equal(published.status, 'ready'); assert.equal(published.lyrics.isSynced, false);
  controller.setTrack(track('a'), 1, 125.51);
  await settle(); assert.equal(calls.length, 1);
  controller.setTrack({ ...track('a'), album: 'Enriched album' }, 1, 125.5);
  await settle(); assert.equal(calls.length, 2); assert.equal(calls[1].args.album, 'Enriched album');
  await controller.retry(); assert.equal(calls[2].args.album, 'Enriched album');
  published.lyrics.lines[0].text = 'consumer mutated';
  assert.equal(controller.snapshot.lyrics.lines[0].text, 'Line 0');
  controller.setTrack(track('a'), 2);
  await settle(); assert.equal(calls.length, 4);
});

test('same-video occurrences reject the previous response and retain a valid fallback through refresh failure', async () => {
  const a = deferred(), b = deferred(), refresh = deferred(); let published;
  const requests = [a, b, refresh]; const calls = [];
  const controller = new LyricsController(async (_, args) => { calls.push(args); return requests.shift().promise; }, state => published = state);
  controller.setTrack(track('same'), 1, 0, 'entry-a');
  controller.setTrack(track('same'), 1, 0, 'entry-b');
  b.resolve(lyrics([3418])); await settle();
  a.resolve(lyrics([1])); await settle();
  assert.equal(published.lyrics.lines[0].timeMs, 3418);
  assert.equal(published.trackKey, JSON.stringify(['same', 1, 'entry-b']));
  const pending = controller.retry();
  assert.equal(published.status, 'loading'); assert.equal(published.lyrics.lines[0].timeMs, 3418);
  refresh.reject({message:'Try later'}); await pending;
  assert.equal(published.status, 'error'); assert.equal(published.lyrics.lines[0].timeMs, 3418);
  controller.reset(); assert.equal(published.lyrics, null);
});

test('provisional duration lookup is reconsidered once useful audio metadata arrives', async () => {
  const calls=[]; const provisional=deferred(); let published;
  const controller=new LyricsController(async (_,args)=>{calls.push(args);return calls.length===1?provisional.promise:lyrics([4000]);},s=>published=s);
  const unknown={...track('a'),duration:null};
  controller.setTrack(unknown,1,0,'entry');
  controller.setTrack(unknown,1,240.2,'entry'); await settle();
  provisional.resolve(lyrics([1000])); await settle();
  assert.deepEqual(calls.map(c=>c.duration),[null,240.2]);
  assert.equal(published.lyrics.lines[0].timeMs,4000);
});

test('late success and error from abandoned tracks or reset cannot populate new lyrics', async () => {
  const a = deferred(); const b = deferred(); const c = deferred(); let published;
  const requests = [a, b, c];
  const controller = new LyricsController(async () => requests.shift().promise, state => published = state);
  controller.setTrack(track('a'), 1);
  controller.setTrack(track('b'), 2);
  b.resolve(lyrics([1000])); await settle();
  a.reject(new Error('old request failed')); await settle();
  assert.equal(published.status, 'ready'); assert.equal(published.trackKey, JSON.stringify(['b', 2]));
  controller.setTrack(track('c'), 3); controller.reset();
  c.resolve(lyrics([1000])); await settle();
  assert.equal(published.status, 'idle'); assert.equal(published.lyrics, null);
});

test('no lyrics, bridge error, retry and disposal remain recoverable and isolated', async () => {
  let call = 0; let published; const pending = deferred();
  const controller = new LyricsController(async () => {
    if (++call === 1) return null;
    if (call === 2) throw { message: 'Network failed' };
    return pending.promise;
  }, state => published = state);
  controller.setTrack(track('a'), 1); await settle();
  assert.equal(published.status, 'empty');
  await controller.retry(); assert.equal(published.status, 'error'); assert.equal(published.error, 'Network failed');
  const retry = controller.retry(); controller.dispose();
  pending.resolve(lyrics([1000])); await retry;
  assert.equal(controller.snapshot.status, 'idle'); assert.equal(published.status, 'idle');
  controller.setTrack(track('b'), 2); assert.equal(call, 3);
});

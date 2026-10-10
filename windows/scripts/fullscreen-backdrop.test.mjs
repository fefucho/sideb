import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

function moduleURL(source) {
  const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
  return `data:text/javascript;base64,${Buffer.from(output).toString('base64')}`;
}
const artworkSource = await readFile(new URL('../src/lib/images/artwork.ts', import.meta.url), 'utf8');
const artworkURL = moduleURL(artworkSource);
const backdropSource = await readFile(new URL('../src/lib/components/fullscreen/backdrop.ts', import.meta.url), 'utf8');
const { fullscreenBackdropCandidates } = await import(moduleURL(backdropSource.replace("'../../images/artwork'", JSON.stringify(artworkURL))));
const { nextArtworkUrl, rejectArtworkAttempt } = await import(artworkURL);

test('backdrop requests exactly 300px independently of foreground originals and retains flags/fallback', () => {
  assert.deepEqual(fullscreenBackdropCandidates('https://lh3.googleusercontent.com/cover=w1080-h608-l90-rj'), [
    'https://lh3.googleusercontent.com/cover=w300-h300-l90-rj',
    'https://lh3.googleusercontent.com/cover=w1080-h608-l90-rj',
  ]);
  assert.deepEqual(fullscreenBackdropCandidates('https://yt3.googleusercontent.com/cover=s576-rj'), [
    'https://yt3.googleusercontent.com/cover=s300-rj',
    'https://yt3.googleusercontent.com/cover=s576-rj',
  ]);
});

test('backdrop preserves signed, query-bearing, external and unsupported URLs byte for byte', () => {
  for (const url of [
    'https://lh3.googleusercontent.com/cover=w544-h544?expire=123&signature=exact',
    'https://yt3.ggpht.com/cover=s576?token=a%2Bb',
    'https://lh3.googleusercontent.com/cover=s576#fragment',
    'https://external.example/cover=w544-h544',
    'https://i.ytimg.com/vi/video/hqdefault.jpg',
    'https://lh3.googleusercontent.com/unsupported',
  ]) assert.deepEqual(fullscreenBackdropCandidates(url), [url]);
});

test('missing artwork has no request and already bounded artwork has no duplicate fallback', () => {
  assert.deepEqual(fullscreenBackdropCandidates(null), []);
  assert.deepEqual(fullscreenBackdropCandidates(''), []);
  const url = 'https://lh3.googleusercontent.com/cover=w300-h300';
  assert.deepEqual(fullscreenBackdropCandidates(url), [url]);
});

test('backdrop fallback rejects only its current attempt and stale track errors cannot reject replacement', () => {
  const candidates = fullscreenBackdropCandidates('https://lh3.googleusercontent.com/cover=s576');
  const initial = { key: '', urls: [] };
  const failed = rejectArtworkAttempt(initial, 'track-a', candidates, 'track-a', candidates[0]);
  assert.equal(nextArtworkUrl(candidates, failed.urls), candidates[1]);
  assert.equal(rejectArtworkAttempt(failed, 'track-a', candidates, 'track-a', candidates[0]), failed);
  const newer = fullscreenBackdropCandidates('https://lh3.googleusercontent.com/replacement=s544');
  assert.equal(rejectArtworkAttempt(initial, 'track-b', newer, 'track-a', candidates[1]), initial);
  const exhausted = rejectArtworkAttempt(failed, 'track-a', candidates, 'track-a', candidates[1]);
  assert.equal(nextArtworkUrl(candidates, exhausted.urls), null);
});

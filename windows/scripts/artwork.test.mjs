import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/images/artwork.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { maxQualityArtworkUrl, originalArtworkUrl, fallbackArtworkUrl, artworkCandidates, nextArtworkUrl, cardArtworkCandidates, rejectArtworkAttempt } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

test('uses 1200px variants for known Google artwork suffixes and preserves query tokens', () => {
  assert.equal(maxQualityArtworkUrl('https://lh3.googleusercontent.com/abc=w544-h544?authuser=2&token=keep'),
    'https://lh3.googleusercontent.com/abc=w1200-h1200?authuser=2&token=keep');
  assert.equal(maxQualityArtworkUrl('https://yt3.ggpht.com/abc=s576?foo=bar'),
    'https://yt3.ggpht.com/abc=s1200?foo=bar');
  assert.equal(originalArtworkUrl('https://lh3.googleusercontent.com/abc=w544-h544?authuser=2&token=keep'),
    'https://lh3.googleusercontent.com/abc=s0?authuser=2&token=keep&imgmax=0');
  assert.equal(fallbackArtworkUrl('https://lh3.googleusercontent.com/abc=s1200?token=keep'),
    'https://lh3.googleusercontent.com/abc=s544?token=keep');
});

test('maps known YouTube image CDN variants to maxresdefault and preserves query tokens', () => {
  assert.equal(maxQualityArtworkUrl('https://i.ytimg.com/vi/abc/hqdefault.jpg?token=keep'),
    'https://i.ytimg.com/vi/abc/maxresdefault.jpg?token=keep');
  assert.equal(maxQualityArtworkUrl('https://img.youtube.com/vi/abc/default.jpg?x=1'),
    'https://img.youtube.com/vi/abc/maxresdefault.jpg?x=1');
});

test('preserves recognized Google size flags and exhausts each fallback before showing a placeholder', () => {
  const flagged = 'https://lh3.googleusercontent.com/abc=w1080-h608-l90-rj?authuser=1&token=keep';
  assert.equal(maxQualityArtworkUrl(flagged), 'https://lh3.googleusercontent.com/abc=w1200-h1200-l90-rj?authuser=1&token=keep');
  assert.equal(fallbackArtworkUrl(flagged), 'https://lh3.googleusercontent.com/abc=w544-h544-l90-rj?authuser=1&token=keep');
  assert.equal(originalArtworkUrl(flagged), 'https://lh3.googleusercontent.com/abc=s0?authuser=1&token=keep&imgmax=0');
  assert.equal(maxQualityArtworkUrl('https://yt3.ggpht.com/abc=s576-l90-rj?x=2'), 'https://yt3.ggpht.com/abc=s1200-l90-rj?x=2');

  const candidates = artworkCandidates(flagged);
  assert.deepEqual(candidates, [
    'https://lh3.googleusercontent.com/abc=s0?authuser=1&token=keep&imgmax=0',
    'https://lh3.googleusercontent.com/abc=w1200-h1200-l90-rj?authuser=1&token=keep',
    'https://lh3.googleusercontent.com/abc=w544-h544-l90-rj?authuser=1&token=keep',
    flagged,
  ]);
  assert.equal(nextArtworkUrl(candidates, candidates.slice(0, 3)), flagged);
  assert.equal(nextArtworkUrl(candidates, candidates), null);
});

test('rewrites the anonymous YouTube Music yt3.googleusercontent.com artwork host', () => {
  const source = 'https://yt3.googleusercontent.com/anonymous-art=w120-h120-l90-rj';
  assert.equal(maxQualityArtworkUrl(source), 'https://yt3.googleusercontent.com/anonymous-art=w1200-h1200-l90-rj');
  assert.equal(originalArtworkUrl(source), 'https://yt3.googleusercontent.com/anonymous-art=s0?imgmax=0');
  assert.equal(fallbackArtworkUrl(source), 'https://yt3.googleusercontent.com/anonymous-art=w544-h544-l90-rj');
});

test('does not rewrite external, signed, or unsupported image URL formats', () => {
  const external = 'https://images.example.test/art?w=200&token=signed';
  assert.equal(maxQualityArtworkUrl(external), external);
  assert.equal(originalArtworkUrl(external), null);
  assert.equal(fallbackArtworkUrl(external), external);
  const unsupportedGoogle = 'https://lh3.googleusercontent.com/abc?token=keep';
  assert.equal(maxQualityArtworkUrl(unsupportedGoogle), unsupportedGoogle);
  assert.equal(originalArtworkUrl(unsupportedGoogle), null);
});

test('card variants follow actual size and DPI while retaining the provider fallback and flags',()=>{
  const source='https://lh3.googleusercontent.com/card=w1080-h608-l90-rj';
  assert.deepEqual(cardArtworkCandidates(source,44,2),['https://lh3.googleusercontent.com/card=w96-h96-l90-rj',source]);
  assert.equal(cardArtworkCandidates(source,216,1.5)[0],'https://lh3.googleusercontent.com/card=w352-h352-l90-rj');
  assert.equal(cardArtworkCandidates(source,5000,4)[0],'https://lh3.googleusercontent.com/card=w1200-h1200-l90-rj');
  assert.deepEqual(cardArtworkCandidates(null,160),[]);
});

test('card sizing never rewrites query-bearing, signed, external or unsupported URLs',()=>{
  for(const source of ['https://lh3.googleusercontent.com/card=w544-h544?sig=secret','https://lh3.googleusercontent.com/card=w544-h544?token=secret','https://images.example.test/card=w544-h544','https://i.ytimg.com/vi/abc/hqdefault.jpg','https://lh3.googleusercontent.com/unsupported'])
    assert.deepEqual(cardArtworkCandidates(source,44,2),[source]);
});

test('card failure retries the exact source once, rejects late recycled callbacks and exhausts cleanly',()=>{
  const source='https://lh3.googleusercontent.com/card=w544-h544';
  const candidates=cardArtworkCandidates(source,44,2),key=JSON.stringify(candidates);
  let failures={key,urls:[]};
  const before=failures;failures=rejectArtworkAttempt(failures,key,candidates,'old-track',candidates[0]);assert.equal(failures,before);
  failures=rejectArtworkAttempt(failures,key,candidates,key,candidates[0]);assert.equal(nextArtworkUrl(candidates,failures.urls),source);
  const fallback=failures;failures=rejectArtworkAttempt(failures,key,candidates,key,candidates[0]);assert.equal(failures,fallback,'superseded attempt cannot consume fallback');
  failures=rejectArtworkAttempt(failures,key,candidates,key,source);assert.equal(nextArtworkUrl(candidates,failures.urls),null);
  const next=['https://lh3.googleusercontent.com/next=w96-h96'];const nextKey=JSON.stringify(next);
  const old=failures;assert.equal(rejectArtworkAttempt(failures,nextKey,next,key,source),old,'old callback cannot reject a recycled replacement');
});

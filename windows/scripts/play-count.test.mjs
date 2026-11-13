import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const load = async name => {
  const source = await readFile(new URL(`../src/lib/${name}`, import.meta.url), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
};
const { formatPlayCount } = await load('detail/playCount.ts');
const { lookup } = await load('i18n/format.ts');
const catalog = JSON.parse(await readFile(new URL('../src/lib/i18n/catalog.json', import.meta.url), 'utf8'));
const translate = (key, args, language) => lookup(catalog, key, language, args);
const show = (raw, language) => formatPlayCount(raw, language, translate);

test('abbreviated provider counts use the app language (same contract as Apple PlayCountFormatter)', () => {
  assert.equal(show('1.2M', 'es'), '1,2 M');
  assert.equal(show('1.2M', 'en'), '1.2M');
  assert.equal(show('53M', 'es'), '53 M');
  assert.equal(show('980K', 'es'), '980 mil');
  assert.equal(show('980K', 'en'), '980K');
  assert.equal(show('2.1B', 'es'), '2,1 mil M');
  assert.equal(show('2.1B', 'en'), '2.1B');
  assert.equal(show('53m', 'en'), '53M', 'suffix is case-insensitive');
  assert.equal(show(' 1.25M ', 'en'), '1.3M', 'at most one decimal');
});

test('plain integers get the language grouping', () => {
  assert.equal(show('1,234', 'es'), '1.234');
  assert.equal(show('1,234', 'en'), '1,234');
  assert.equal(show('987', 'es'), '987');
  assert.equal(show('1,234,567', 'en'), '1,234,567');
});

test('empty or unrecognised text is dropped, never shown raw', () => {
  for (const raw of [null, undefined, '', '   ', 'abc', '12 plays', 'M', '1.2.3M', '-5', '1.2MM', 'NaN'])
    assert.equal(show(raw, 'es'), null, String(raw));
});

test('the localized plural/suffix strings and the accessibility label exist in both languages', () => {
  for (const key of ['detail.track.plays.thousand', 'detail.track.plays.million', 'detail.track.plays.billion', 'detail.track.playsAX']) {
    assert.ok(catalog[key]?.es && catalog[key]?.en, key);
  }
  assert.equal(lookup(catalog, 'detail.track.playsAX', 'es', ['1,2 M']), '1,2 M reproducciones');
  assert.equal(lookup(catalog, 'detail.track.playsAX', 'en', ['1.2M']), '1.2M plays');
});

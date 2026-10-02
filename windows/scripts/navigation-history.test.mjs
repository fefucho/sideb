import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/navigation/history.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { NavigationHistory } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

test('history supports back, forward and branch replacement', () => {
  const history = new NavigationHistory();
  history.visit('home'); history.visit('album');
  assert.equal(history.back('artist'), 'album');
  assert.equal(history.back('album'), 'home');
  assert.equal(history.canForward, true);
  history.visit('home');
  assert.equal(history.canForward, false);
  assert.equal(history.forward('home'), null);
});

test('back and forward exchange snapshots and map both stacks', () => {
  const history = new NavigationHistory(40, (left, right) => left.page === right.page);
  history.visit({ page: 'home', scroll: 42 });
  const destination = history.back({ page: 'album', scroll: 11 });
  assert.deepEqual(destination, { page: 'home', scroll: 42 });
  assert.deepEqual(history.forward({ page: 'home', scroll: 7 }), { page: 'album', scroll: 11 });
  history.mapSnapshots(snapshot => ({ ...snapshot, mapped: true }));
  assert.deepEqual(history.back({ page: 'album', scroll: 11 }), { page: 'home', scroll: 7, mapped: true });
});

test('history is bounded, suppresses adjacent duplicates with an equality key, and clears both stacks', () => {
  const duplicateHistory = new NavigationHistory(40, (left, right) => left.id === right.id);
  duplicateHistory.visit({ id: 'home' }); duplicateHistory.visit({ id: 'album' }); duplicateHistory.visit({ id: 'album' });
  assert.equal(duplicateHistory.back({ id: 'artist' })?.id, 'album');
  assert.equal(duplicateHistory.back({ id: 'album' })?.id, 'home');

  const history = new NavigationHistory(2, (left, right) => left.id === right.id);
  history.visit({ id: 'home', scroll: 1 }); history.visit({ id: 'album', scroll: 2 });
  history.visit({ id: 'album', scroll: 3 });
  assert.equal(history.canBack, true);
  history.visit({ id: 'artist', scroll: 4 });
  history.visit({ id: 'search', scroll: 5 });
  assert.equal(history.back({ id: 'library', scroll: 6 })?.id, 'search');
  assert.equal(history.back({ id: 'search', scroll: 5 })?.id, 'artist');
  assert.equal(history.back({ id: 'artist', scroll: 4 }), null);
  history.clear();
  assert.equal(history.canBack, false); assert.equal(history.canForward, false);
});

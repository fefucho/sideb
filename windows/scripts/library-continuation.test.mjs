import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/library/continuation.ts', import.meta.url), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { ContinuationGate } = await import(`data:text/javascript;base64,${Buffer.from(compiled).toString('base64')}`);

test('near-bottom pagination does not load outside the threshold or during a pending request', () => {
  const gate = new ContinuationGate();
  assert.equal(gate.claim('playlist:a', 'page1', false, false, null), false);
  assert.equal(gate.claim('playlist:a', 'page1', true, true, null), false);
  assert.equal(gate.claim('playlist:a', 'page1', true, false, null), true);
});

test('a failed cursor does not automatically loop when the observer or playback state updates', () => {
  const gate = new ContinuationGate();
  assert.equal(gate.claim('playlist:a', 'page1', true, false, null), true);
  assert.equal(gate.claim('playlist:a', 'page1', true, false, 'network failure'), false);
  assert.equal(gate.claim('playlist:a', 'page1', true, true, null), false);
  assert.equal(gate.claim('playlist:a', 'page1', true, false, null), false);
});

test('the next cursor can continue while still near the bottom; final pages stop', () => {
  const gate = new ContinuationGate();
  assert.equal(gate.claim('library:songs', 'page1', true, false, null), true);
  assert.equal(gate.claim('library:songs', 'page2', true, false, null), true);
  assert.equal(gate.claim('library:songs', null, true, false, null), false);
});

test('playlist navigation and full refresh allow reused provider cursors', () => {
  const gate = new ContinuationGate();
  assert.equal(gate.claim('playlist:a', 'same-cursor', true, false, null), true);
  assert.equal(gate.claim('playlist:b', 'same-cursor', true, false, null), true);
  gate.reset();
  assert.equal(gate.claim('playlist:b', 'same-cursor', true, false, null), true);
});

test('an existing error blocks the first automatic request without consuming its cursor', () => {
  const gate = new ContinuationGate();
  assert.equal(gate.claim('library:songs', 'page1', true, false, 'refresh failed'), false);
  assert.equal(gate.claim('library:songs', 'page1', true, false, null), true);
});

import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/search/preview.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { SearchPreviewController } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const card = id => ({ kind: 'artist', id, title: id, subtitle: null, thumbnail: null, duration: null });
const result = id => ({ top: [card(id)], songs: [], albums: [], artists: [], playlists: [] });
function deferred() { let resolve; const promise = new Promise(done => resolve = done); return { promise, resolve }; }
function clock() {
  let now = 0; let nextId = 0; const timers = new Map();
  return { scheduler: {
    setTimeout(callback, delay) { const id = ++nextId; timers.set(id, { at: now + delay, callback }); return id; },
    clearTimeout(id) { timers.delete(id); },
  }, advance(ms) {
    now += ms;
    while (true) {
      const due = [...timers].filter(([, timer]) => timer.at <= now).sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) break;
      timers.delete(due[0]); due[1].callback();
    }
  } };
}
const tick = () => new Promise(resolve => setTimeout(resolve, 0));
function create(invoke) { let data; const time = clock(); const controller = new SearchPreviewController(invoke, next => data = next, time.scheduler); return { controller, advance: ms => time.advance(ms), get data() { return data; } }; }

test('debounces 250ms, requests only search_all without recording history, and clears on empty query', async () => {
  const calls = [];
  const ctx = create(async (command, args) => { calls.push({ command, args }); return result(args.query); });
  ctx.controller.setQuery(' Radiohead ');
  ctx.advance(249);
  assert.equal(calls.length, 0);
  ctx.advance(1); await tick();
  assert.deepEqual(calls, [{ command: 'search_all', args: { query: 'Radiohead', recordHistory: false } }]);
  assert.equal(ctx.data.associatedQuery, 'Radiohead');
  assert.equal(ctx.data.results.top[0].id, 'Radiohead');
  ctx.controller.setQuery('');
  assert.deepEqual(ctx.data, { query: '', associatedQuery: '', results: null, isLoading: false, error: null });
  ctx.controller.setQuery('will clear'); ctx.controller.setQuery(''); ctx.advance(250);
  assert.equal(calls.length, 1);
  ctx.controller.dispose();
});

test('A to B to A rejects stale responses from the first A and B', async () => {
  const pending = [deferred(), deferred(), deferred()]; const calls = [];
  const ctx = create((command, args) => { calls.push(args.query); return pending[calls.length - 1].promise; });
  ctx.controller.setQuery('A'); ctx.advance(250); await tick();
  ctx.controller.setQuery('B'); ctx.advance(250); await tick();
  ctx.controller.setQuery('A'); ctx.advance(250); await tick();
  pending[2].resolve(result('new A')); await tick();
  pending[0].resolve(result('old A')); pending[1].resolve(result('old B')); await tick();
  assert.deepEqual(calls, ['A', 'B', 'A']);
  assert.equal(ctx.data.results.top[0].id, 'new A');
  ctx.controller.dispose();
});

test('cancel, reset, and dispose invalidate pending responses', async () => {
  const pending = [deferred(), deferred(), deferred()]; let requests = 0; let emissions = 0;
  const ctx = create(() => pending[requests++].promise);
  const originalEmit = ctx.controller['onChange'];
  ctx.controller['onChange'] = data => { emissions++; originalEmit(data); };
  ctx.controller.setQuery('pending'); ctx.advance(250); await tick();
  ctx.controller.cancel();
  pending[0].resolve(result('stale')); await tick();
  assert.equal(ctx.data.results, null);
  ctx.controller.setQuery('again'); ctx.advance(250); await tick();
  const beforeReset = emissions;
  ctx.controller.reset(); pending[1].resolve(result('pre-reset')); await tick();
  assert.equal(emissions, beforeReset + 1);
  assert.equal(ctx.data.query, '');
  ctx.controller.setQuery('disposed'); ctx.advance(250); await tick();
  const beforeDispose = emissions;
  ctx.controller.dispose(); pending[2].resolve(result('late')); await tick();
  assert.equal(emissions, beforeDispose);
  assert.equal(ctx.data.query, 'disposed');
});

test('changing draft clears results from the previous associated query immediately', async () => {
  const ctx = create(async (_command, args) => result(args.query));
  ctx.controller.setQuery('old'); ctx.advance(250); await tick();
  assert.ok(ctx.data.results);
  ctx.controller.setQuery('new');
  assert.equal(ctx.data.results, null);
  assert.equal(ctx.data.associatedQuery, '');
  ctx.controller.dispose();
});

test('reports recoverable request errors for the current draft', async () => {
  const ctx = create(async () => { throw new Error('offline'); });
  ctx.controller.setQuery('query'); ctx.advance(250); await tick();
  assert.equal(ctx.data.isLoading, false);
  assert.equal(ctx.data.error, 'offline');
  assert.equal(ctx.data.associatedQuery, 'query');
  ctx.controller.dispose();
});

test('a failed or cancelled query can be requested again when Spotlight reopens', async () => {
  let attempts = 0;
  const ctx = create(async () => { if (++attempts === 1) throw new Error('offline'); return result('recovered'); });
  ctx.controller.setQuery('query'); ctx.advance(250); await tick();
  ctx.controller.cancel();
  ctx.controller.setQuery('query'); ctx.advance(250); await tick();
  assert.equal(attempts, 2);
  assert.equal(ctx.data.results.top[0].id, 'recovered');
  ctx.controller.dispose();
});

test('default scheduler calls browser timers with globalThis as receiver', async () => {
  const originalSetTimeout = globalThis.setTimeout;
  const originalClearTimeout = globalThis.clearTimeout;
  let calls = 0;
  const controller = new SearchPreviewController(async (_command, args) => { calls++; return result(args.query); }, () => {});
  globalThis.setTimeout = function (callback, delay, ...args) {
    assert.equal(this, globalThis);
    return originalSetTimeout(callback, delay, ...args);
  };
  globalThis.clearTimeout = function (timer) {
    assert.equal(this, globalThis);
    return originalClearTimeout(timer);
  };
  try {
    controller.setQuery('cancelled');
    controller.setQuery('');
    controller.setQuery('query');
    await new Promise(resolve => originalSetTimeout(resolve, 270));
    assert.equal(calls, 1);
    controller.dispose();
  } finally {
    globalThis.setTimeout = originalSetTimeout;
    globalThis.clearTimeout = originalClearTimeout;
  }
});

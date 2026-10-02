import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const compile = text => ts.transpileModule(text, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const url = text => `data:text/javascript;base64,${Buffer.from(text).toString('base64')}`;
const presentation = url(compile(await readFile(new URL('../src/lib/home/presentation.ts', import.meta.url), 'utf8')));
const source = compile(await readFile(new URL('../src/lib/home/controller.ts', import.meta.url), 'utf8')).replace("'./presentation'", JSON.stringify(presentation));
const { HomeController } = await import(url(source));
const section = id => ({ title: id, format: 'largeCards', moreBrowseId: null, moreParams: null, items: [{ id, kind: 'song' }] });
const page = (id, continuation = null) => ({ sections: [section(id)], chips: [], continuation });
function deferred() { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; }

test('account reset discards pending Home and continuation replies', async () => {
  const pending = deferred(); let data;
  const home = new HomeController(() => pending.promise, next => { data = next; });
  const load = home.load(); home.reset(); pending.resolve(page('private', 'private-token')); await load;
  assert.equal(data.page, null); assert.equal(data.loading, false); assert.equal(data.loadingMore, false);
});
test('older chip result cannot replace a newer feed', async () => {
  const first = deferred(); let data;
  const home = new HomeController((command, args) => args.chipParams === 'first' ? first.promise : Promise.resolve(page('second')), next => { data = next; });
  const old = home.load('first'); await home.load('second'); first.resolve(page('first')); await old;
  assert.equal(data.chipParams, 'second'); assert.equal(data.page.sections[0].title, 'second');
});
test('pagination retries a failure, preserves order, and stops repeated tokens', async () => {
  let calls = 0; let data;
  const home = new HomeController(async command => {
    if (command === 'get_home_page') return page('first', 'next');
    if (++calls === 1) throw new Error('temporary');
    return { ...page('second', 'next'), sections: [section('first'), section('second')] };
  }, next => { data = next; });
  await home.load('chip'); await home.loadMore();
  assert.equal(data.page.continuation, 'next'); assert.equal(data.moreError, 'temporary');
  await home.loadMore(); assert.deepEqual(data.page.sections.map(s => s.title), ['first', 'second']);
  assert.equal(data.page.continuation, null); assert.equal(await home.loadMore(), false); assert.equal(calls, 2);
});
test('pending continuation cannot append to a new chip', async () => {
  const pending = deferred(); let data;
  const home = new HomeController((command, args) => command === 'get_home_continuation' ? pending.promise : Promise.resolve(page(args.chipParams, 'next')), next => { data = next; });
  await home.load('first'); const more = home.loadMore(); await home.load('second');
  pending.resolve(page('private')); await more;
  assert.deepEqual(data.page.sections.map(s => s.title), ['second']); assert.equal(data.loadingMore, false);
});

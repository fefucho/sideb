import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const compile = text => ts.transpileModule(text, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const url = text => `data:text/javascript;base64,${Buffer.from(text).toString('base64')}`;
const presentation = url(compile(await readFile(new URL('../src/lib/home/presentation.ts', import.meta.url), 'utf8')));
const source = compile(await readFile(new URL('../src/lib/home/controller.ts', import.meta.url), 'utf8')).replace("'./presentation'", JSON.stringify(presentation));
const { HomeController } = await import(url(source));
const section = id => ({ title: id, format: 'largeCards', moreBrowseId: null, moreParams: null, items: [{ id, title:id, kind: 'song' }] });
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


test('durable Home feed is isolated by account and excludes continuation cursors',async()=>{
 const values=new Map();const storage={getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value)};let data;
 const home=new HomeController(async()=>page('private-A','secret-cursor'),next=>data=next,undefined,()=>false);
 home.setSession('account-hash-A',storage);await home.load();
 assert.ok(values.get('account-hash-A.feed.v1'));assert.equal(values.get('account-hash-A.feed.v1').includes('secret-cursor'),false);
 home.setSession('account-hash-B',storage);assert.equal(data.page,null);
 home.setSession('account-hash-A',storage);assert.equal(data.page.sections[0].title,'private-A');assert.equal(data.page.continuation,null);
});

test('failed chip restores the previous selection and RAM snapshots are bounded to four',async()=>{
 let data;const home=new HomeController(async(_,{chipParams})=>{if(chipParams==='bad')throw Error('offline');return page(chipParams??'home');},next=>data=next,undefined,()=>false);
 await home.load('one');await home.load('bad');assert.equal(data.chipParams,'one');assert.equal(data.page.sections[0].title,'one');assert.ok(data.error);
 for(const chip of ['two','three','four','five'])await home.load(chip);
 assert.equal(home.snapshots.size,4);assert.equal(home.snapshots.has('one'),false);
});


test('durable Home ignores malformed/oversized storage and strips opaque action data',async()=>{
 let data;const values=new Map();const storage={getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value)};
 const fixture=page('safe');fixture.sections[0].items[0].library={addToken:'private-action-token'};fixture.sections[0].items[0].thumbnail='https://image.test/a?signature=private';
 const home=new HomeController(async()=>fixture,next=>data=next,undefined,()=>false);
 home.setSession('good',storage);await home.load();
 const raw=values.get('good.feed.v1');assert.ok(raw);assert.equal(raw.includes('private-action-token'),false);assert.equal(raw.includes('signature='),false);
 values.set('bad.feed.v1',JSON.stringify({version:1,chips:[],sections:[{title:'bad',items:[null]}]}));
 home.setSession('bad',storage);assert.equal(data.page,null);
 values.set('large.feed.v1',' '.repeat(2_000_001));home.setSession('large',storage);assert.equal(data.page,null);
 home.setSession('good',storage);assert.equal(data.page.sections[0].items[0].id,'safe');
});

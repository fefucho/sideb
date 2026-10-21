import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import ts from 'typescript';

async function load(relative) {
  const source = await readFile(new URL(relative, import.meta.url), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
}
const policy = await load('../src/lib/artwork/policy.ts');
const clearing = await load('../src/lib/artwork/clearCoordinator.ts');
const deferred = () => { let resolve, reject; const promise = new Promise((done, fail) => {resolve = done; reject = fail;}); return { promise, resolve, reject }; };

test('track changes within one album preserve its player identity; a different album does not', () => {
  const first = { albumId: 'collection-1', album: 'Album', artists: 'Artist' };
  assert.equal(policy.animatedArtworkAlbumKey(first), policy.animatedArtworkAlbumKey({ ...first, videoId: 'next-track' }));
  assert.notEqual(policy.animatedArtworkAlbumKey(first), policy.animatedArtworkAlbumKey({ ...first, albumId: 'collection-2' }));
  assert.equal(policy.animatedArtworkAlbumKey({ album: ' Album ', artists: ' Artist ' }), policy.animatedArtworkAlbumKey({ album: 'album', artists: 'artist' }));
  const splitCredit = { album: 'Record', artists: 'Featured Artist & Main Artist', artistRuns: [{ text: 'Main Artist', id: 'artist-main' }, { text: 'Featured Artist', id: 'artist-featured' }] };
  assert.equal(policy.animatedArtworkPrimaryArtist(splitCredit), 'Main Artist');
  assert.equal(policy.animatedArtworkAlbumKey(splitCredit), policy.animatedArtworkAlbumKey({ album: 'record', artists: 'Main Artist' }));
});

test('late result is accepted only for the current revision and retained request lease', () => {
  assert.equal(policy.isCurrentAnimatedArtworkRequest(4, 4, 'album-a', 'album-a'), true);
  assert.equal(policy.isCurrentAnimatedArtworkRequest(3, 4, 'album-a', 'album-a'), false);
  assert.equal(policy.isCurrentAnimatedArtworkRequest(4, 4, 'album-a', 'album-b'), false);
});

test('cache clear waits for source release and coalesces concurrent clears', async () => {
  const coordinator = new clearing.AnimatedArtworkClearCoordinator();
  const sourceRemoved = deferred(); const order = []; let clearCalls = 0;
  coordinator.register(async () => { order.push('source-removed'); await sourceRemoved.promise; order.push('lease-cancelled'); });
  const clearFiles = async () => { clearCalls++; order.push('cache-cleared'); return 123; };
  const first = coordinator.clear(clearFiles); const second = coordinator.clear(clearFiles);
  assert.equal(first, second); assert.equal(coordinator.clearing, true);
  await Promise.resolve(); assert.deepEqual(order, ['source-removed']); assert.equal(clearCalls, 0);
  sourceRemoved.resolve(); assert.equal(await first, 123); assert.equal(await second, 123);
  assert.deepEqual(order, ['source-removed', 'lease-cancelled', 'cache-cleared']); assert.equal(clearCalls, 1);
});

const { AnimatedArtworkController } = await load('../src/lib/artwork/controller.ts');
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };
const wait = () => new Promise(resolve => setTimeout(resolve, 5));
function fixture() {
  const jobs = [], cancelled = [], presented = [];
  const controller = new AnimatedArtworkController({ debounceMs: 0,
    prepare: (request, id) => { const job = deferred(); jobs.push({ request, id, ...job }); return job.promise; },
    cancel: async id => { cancelled.push(id); }, publish: asset => presented.push(asset), detach: async () => {}, id: () => `lease-${jobs.length}`,
  });
  return {controller,jobs,cancelled,presented};
}
test('A to B during pending cancels A immediately and prepares B after its captured job releases', async () => {
  const f = fixture(); f.controller.update('A', 'request A', true, true); await wait();
  f.controller.update('B', 'request B', true, true); await wait();
  assert.deepEqual(f.cancelled, ['lease-0']); assert.equal(f.jobs.length, 1);
  f.jobs[0].resolve({album:'A'}); await flush(); await wait();
  assert.equal(f.jobs.length, 2); assert.equal(f.jobs[1].request, 'request B');
  assert.equal(f.presented.some(asset => asset?.album === 'A'), false);
  f.jobs[1].resolve({album:'B'}); await flush();
  assert.equal(f.presented.at(-1).album, 'B'); await f.controller.dispose();
});
test('absence and failures do not retry on playback ticks; reopen or album change allows a new request', async () => {
  const f = fixture(); f.controller.update('A', 'request A', true, true); await wait(); f.jobs[0].resolve(null); await flush();
  for(let i=0;i<10;i++) f.controller.update('A', 'request A', true, true);
  await wait(); assert.equal(f.jobs.length, 1);
  f.controller.update('B', 'request B', true, true); await wait(); assert.equal(f.jobs.length, 2);
  f.jobs[1].resolve(null); await flush(); await f.controller.dispose();
});
test('pause/flip/hidden preserves prepared lease, while same-album account change releases it', async () => {
  const f = fixture(); f.controller.update('session1:A', 'request A', true, true); await wait(); f.jobs[0].resolve({album:'A'}); await flush();
  f.controller.update('session1:A', 'next track A', true, false); f.controller.update('session1:A', 'next track A', true, true);
  await wait(); assert.equal(f.jobs.length, 1); assert.deepEqual(f.cancelled, []);
  f.controller.update('session2:A', 'request A', true, true); await wait();
  assert.deepEqual(f.cancelled, ['lease-0']); assert.equal(f.jobs.length, 2);
  f.jobs[1].resolve(null); await flush(); await f.controller.dispose();
});
test('clear cancels pending before awaiting it and cannot repopulate or restart on same album', async () => {
  const f = fixture(); f.controller.update('A', 'A', true, true); await wait();
  let finished = false; const clearing = f.controller.clear().then(() => finished = true);
  assert.deepEqual(f.cancelled, ['lease-0']); await flush(); assert.equal(finished, false);
  f.jobs[0].resolve({album:'A'}); await clearing;
  f.controller.update('A', 'A', true, true); await wait(); assert.equal(f.jobs.length, 1);
  assert.equal(f.presented.some(asset => asset?.album === 'A'), false); await f.controller.dispose();
});
test('track-only fallback never shares an empty-album artist identity across songs', () => {
  assert.notEqual(policy.animatedArtworkAlbumKey({videoId:'a',title:'A',artists:'Artist',duration:120}), policy.animatedArtworkAlbumKey({videoId:'b',title:'B',artists:'Artist',duration:120}));
});


test('temporary resolver failure stays static without retrying on pause/resume', async () => {
  const f=fixture();f.controller.update('A','A',true,true);await wait();f.jobs[0].reject(new Error('network'));await flush();
  f.controller.update('A','A',true,false);f.controller.update('A','A',true,true);await wait();
  assert.equal(f.jobs.length,1);assert.deepEqual(f.cancelled,['lease-0']);await f.controller.dispose();
});


test('metadata enrichment retries a static result once, while an existing album asset stays retained', async () => {
 const f=fixture();f.controller.update('A','missing artist',true,true,'missing');await wait();f.jobs[0].resolve(null);await flush();
 f.controller.update('A','known artist',true,true,'known');await wait();assert.equal(f.jobs.length,2);
 f.jobs[1].resolve({album:'A'});await flush();f.controller.update('A','enriched artist',true,true,'enriched');await wait();
 assert.equal(f.jobs.length,2);assert.equal(f.presented.at(-1).album,'A');await f.controller.dispose();
});


test('a newly registered consumer inherits an active clear and cannot start even before registration',async()=>{
 const coordinator=new clearing.AnimatedArtworkClearCoordinator();const deletion=deferred();
 const pending=coordinator.clear(()=>deletion.promise);let released=0;
 coordinator.register(async()=>{released++;});assert.equal(released,1);
 let preparations=0;
 const controller=new AnimatedArtworkController({debounceMs:0,isClearing:()=>coordinator.clearing,prepare:async()=>{preparations++;return {};},cancel:async()=>{},publish:()=>{},detach:async()=>{},id:()=> 'clear-mount'});
 controller.update('A','A',true,true);await wait();assert.equal(preparations,0);
 deletion.resolve(0);await pending;controller.update('A','A',true,true);await wait();assert.equal(preparations,0);
 controller.update('B','B',true,true);await wait();assert.equal(preparations,1);await controller.dispose();
});

test('inactive prepared asset has one deadline, resume cancels it, and 30s release permits a warm preparation',async()=>{
 const originalTimeout=globalThis.setTimeout;const originalClear=globalThis.clearTimeout;const deadlines=new Map();let seq=0;
 globalThis.setTimeout=(callback,delay,...args)=>delay===30000?(deadlines.set(++seq,callback),seq):originalTimeout(callback,delay,...args);
 globalThis.clearTimeout=id=>deadlines.delete(id)||originalClear(id);
 const f=fixture();
 try{
  f.controller.update('A','A',true,true);await wait();f.jobs[0].resolve({album:'A'});await flush();
  f.controller.update('A','A',true,false);f.controller.update('A','A',true,false);assert.equal(deadlines.size,1);
  f.controller.update('A','A',true,true);assert.equal(deadlines.size,0);
  f.controller.update('A','A',true,false);const expire=[...deadlines.values()][0];deadlines.clear();expire();await flush();assert.deepEqual(f.cancelled,['lease-0']);assert.equal(f.presented.at(-1),null);
  f.controller.update('A','A',true,true);await wait();assert.equal(f.jobs.length,2);f.jobs[1].resolve({album:'A'});await flush();
  await f.controller.dispose();assert.equal(deadlines.size,0);
 }finally{globalThis.setTimeout=originalTimeout;globalThis.clearTimeout=originalClear;}
});

test('cache deletion waits for a consumer mounted while an earlier detach is pending',async()=>{
 const coordinator=new clearing.AnimatedArtworkClearCoordinator();const first=deferred(),late=deferred();let deleted=false;
 coordinator.register(()=>first.promise);
 const pending=coordinator.clear(async()=>{deleted=true;return 0;});
 coordinator.register(()=>late.promise);first.resolve();await flush();assert.equal(deleted,false);
 late.resolve();await pending;assert.equal(deleted,true);
});

import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
import {compile} from 'svelte/compiler';
const source=await readFile(new URL('../src/lib/featured/artists.ts',import.meta.url),'utf8');
const output=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {FeaturedArtistService,FeaturedArtistPicker}=await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const track=(title='Title')=>({videoId:'one',title,artists:'Main',artistRuns:[]});
const card=(id='guest')=>({kind:'artist',id,title:'Guest'});
const tick=()=>new Promise(r=>setTimeout(r,0));
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};
function setup(){const pending=[];const calls=[];const disk=new Map();const service=new FeaturedArtistService({scope:'a',storage:{getItem:k=>disk.get(k)??null,setItem:(k,v)=>disk.set(k,v)},search:async q=>{calls.push(q);const d=deferred();pending.push(d);return d.promise;}});return {service,pending,calls,disk};}
test('first consumer cancellation never cancels the second live consumer',async()=>{
 const {service,pending,calls}=setup(),a=new AbortController(),b=new AbortController();
 const first=service.resolve(track(),'Guest',undefined,true,a.signal),second=service.resolve(track(),'Guest',undefined,true,b.signal);
 await tick();a.abort();assert.equal((await first).id,undefined);pending[0].resolve([card()]);assert.equal((await second).id,'guest');assert.deepEqual(calls,['Guest']);
 assert.equal((await service.resolve(track(),'Guest')).id,'guest');assert.equal(calls.length,1);
});
test('last consumer cancellation skips contextual retry/cache and next consumer gets fresh flight',async()=>{
 const {service,pending,calls}=setup(),a=new AbortController();const first=service.resolve(track(),'Guest',undefined,true,a.signal);
 await tick();a.abort();await first;const next=service.resolve(track(),'Guest');await tick();assert.equal(calls.length,2);
 pending[0].resolve([]);await tick();assert.deepEqual(calls,['Guest','Guest']);pending[1].resolve([card('fresh')]);assert.equal((await next).id,'fresh');
 assert.equal((await service.resolve(track(),'Guest')).id,'fresh');
});
test('scope reset cancels shared work without caching into another account',async()=>{
 const {service,pending}=setup();const first=service.resolve(track(),'Guest');await tick();service.resetScope('b');pending[0].resolve([card('old')]);assert.equal((await first).id,undefined);
 const fresh=service.resolve(track(),'Guest');await tick();pending[1].resolve([card('new')]);assert.equal((await fresh).id,'new');
});
for(const change of ['title','name','account'])test(`correction rejects publication and choice after ${change} changes`,async()=>{
 const {service,pending,disk}=setup();let current={track:track(),name:'Guest'};const picker=new FeaturedArtistPicker(service,()=>current);const loading=picker.load();await tick();
 if(change==='title')current={...current,track:track('Other')};if(change==='name')current={...current,name:'Other'};if(change==='account')service.resetScope('b');
 pending[0].resolve([card('stale')]);assert.deepEqual(await loading,[]);assert.equal(picker.choose('stale'),false);assert.equal([...disk.keys()].filter(k=>k.includes('choices')).length,0);
});
test('loaded correction rejects an account change before choice; current explicit choice persists',async()=>{
 const {service,pending,disk}=setup();const current={track:track(),name:'Guest'},picker=new FeaturedArtistPicker(service,()=>current);
 const old=picker.load();await tick();pending[0].resolve([card('old')]);await old;service.resetScope('b');assert.equal(picker.choose('old'),false);
 const fresh=picker.load();await tick();assert.equal(picker.choose('old'),false);pending[1].resolve([card('new')]);await fresh;assert.equal(picker.choose('old'),false);assert.equal(picker.choose('new'),true);
 assert.equal((await service.resolve(current.track,'Guest')).id,'new');assert.ok([...disk.keys()].includes('sideb.featured.choices.v1:b'));
});
test('reopening selector clears previous choices and ignores cancelled results',async()=>{
 const {service,pending}=setup();const picker=new FeaturedArtistPicker(service,()=>({track:track(),name:'Guest'}));const old=picker.load();await tick();const fresh=picker.load();await tick();pending[1].resolve([card('new')]);assert.deepEqual((await fresh).map(c=>c.id),['new']);pending[0].resolve([card('old')]);assert.deepEqual(await old,[]);assert.equal(picker.choose('old'),false);assert.equal(picker.choose('new'),true);
});
test('patched Svelte correction component compiles for client and server',async()=>{
 const component=await readFile(new URL('../src/lib/components/FeaturedArtistLink.svelte',import.meta.url),'utf8');for(const generate of ['client','server'])compile(component,{filename:'FeaturedArtistLink.svelte',generate});
});

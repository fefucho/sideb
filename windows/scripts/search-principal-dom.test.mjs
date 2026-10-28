import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {readFile} from 'node:fs/promises';

if(!process.execArgv.includes('--conditions=browser')) {
 test('mounted provider principal preserves artist navigation, menu, actions and local related expansion',()=>{
  const {NODE_TEST_CONTEXT,...env}=process.env;
  const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
  assert.equal(result.status,0,result.stdout+result.stderr);
 });
} else {
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('search-principal-dom');
 globalThis.IntersectionObserver=class {observe(){} disconnect(){}};
 const Fixture=(await import(await moduleFor(path.join(root,'scripts/fixtures/ProviderPrincipal.svelte')))).default;
 test('real principal keeps 3 related visible initially, expands without dropping occurrences and dispatches original actions',async()=>{
  for(const width of [600,800,1100]) {
   const host=document.createElement('div');document.body.append(host);const calls=[];let app;
   flushSync(()=>app=mount(Fixture,{target:host,props:{width,onCall:(...args)=>calls.push(args)},intro:false}));
   assert.equal(host.querySelectorAll('.related-list .media-card').length,3);
   host.querySelector('.actions button').click();flushSync();
   assert.equal(calls.at(-1)[0],'action');assert.equal(calls.at(-1)[1].params,'opaque');assert.equal(calls.at(-1)[2].id,'top');
   host.querySelector('.related > button').click();flushSync();await tick();
   assert.equal(host.querySelectorAll('.related-list .media-card').length,5);
   host.querySelector('.hero-card .cover').click();flushSync();assert.deepEqual(calls.at(-1),['artist','artist-main']);
   host.querySelector('.open-primary').click();flushSync();assert.deepEqual(calls.at(-1),['artist','artist-main']);assert.notEqual(calls.at(-1)[0],'play');
   host.querySelector('.actions .more').click();flushSync();assert.equal(calls.at(-1)[0],'menu');assert.equal(calls.at(-1)[1].kind,'artist');
   await unmount(app);host.remove();
  }
 });
 test('primary fallbacks play songs and albums only when needed, and empty action groups do not reserve a column',async()=>{
  for(const config of [{kind:'song',actions:false},{kind:'song',actions:true,actionType:'browse'},{kind:'album',actions:false,withMedia:false},{kind:'album',actions:false,withMedia:true},{kind:'album',actions:true,withMedia:true},{kind:'artist',actions:false},{kind:'artist',actions:false,openable:false}]) {
   const host=document.createElement('div');document.body.append(host);const calls=[];let app;
   flushSync(()=>app=mount(Fixture,{target:host,props:{...config,onCall:(...args)=>calls.push(args)},intro:false}));
   const root=host.querySelector('.principal');
   if(config.kind==='song') {assert.ok(root.classList.contains('has-actions'));assert.ok(host.querySelector('.fallback-play'));if(config.actionType==='browse'){assert.equal(host.querySelectorAll('.actions button').length,3);host.querySelector('.actions button').click();flushSync();assert.equal(calls.at(-1)[0],'action');}host.querySelector('.fallback-play').click();flushSync();assert.equal(calls.at(-1)[0],'play');assert.equal(calls.at(-1)[1].videoId,'fixture');}
   if(config.kind==='album'&&!config.withMedia)assert.equal(host.querySelector('.fallback-play'),null);
   if(config.kind==='album'&&config.withMedia&&!config.actions){host.querySelector('.open-primary').click();flushSync();assert.equal(calls.at(-1)[0],'album');assert.equal(calls.at(-1)[1].id,'album-main');assert.notEqual(calls.at(-1)[0],'activate');host.querySelector('.fallback-play').click();flushSync();assert.equal(calls.at(-1)[0],'activate');assert.equal(calls.at(-1)[1].id,'album-main');}
   if(config.kind==='album'&&config.actions){assert.equal(host.querySelector('.fallback-play'),null);host.querySelector('.open-primary').click();flushSync();assert.equal(calls.at(-1)[0],'album');}
   if(config.kind==='artist'&&config.openable!==false){assert.ok(root.classList.contains('has-actions'));host.querySelector('.open-primary').click();flushSync();assert.deepEqual(calls.at(-1),['artist','artist-main']);}
   if(config.kind==='artist'&&config.openable===false){assert.equal(host.querySelector('.open-primary'),null);assert.ok(host.querySelector('.actions .more'));}
   await unmount(app);host.remove();
  }
  const source=await readFile(path.join(root,'src/lib/components/search/SearchPrincipal.svelte'),'utf8');
  assert.ok(source.includes('.principal:not(.artist).has-actions{grid-template-columns:minmax(0,1fr) auto'));
  assert.ok(source.includes('.hero-card .cover{display:grid;place-items:center;width:96px;height:96px'));
  assert.ok(source.includes('.hero-card{display:flex;align-items:center;gap:16px'));assert.ok(source.includes('.actions{display:flex;min-width:0;align-items:center;'));
  const searchView=await readFile(path.join(root,'src/lib/components/search/SearchView.svelte'),'utf8');assert.ok(searchView.includes('projectSearchDocument(displayData.page)'));assert.ok(searchView.includes('remaining={[]}'));
 });
 test('unpaired song and video principals retain media geometry, accessible playback and safe fallback payloads',async()=>{
  for(const kind of ['song','video']){
   const host=document.createElement('div');document.body.append(host);const calls=[];let app;
   flushSync(()=>app=mount(Fixture,{target:host,props:{kind,actions:false,missingSong:true,onCall:(...args)=>calls.push(args)},intro:false}));
   assert.ok(host.querySelector('.hero-song .play'));assert.equal(host.querySelector('.hero-card'),null);
   assert.match(host.querySelector('.hero-song .play').getAttribute('aria-label'),/Reproducir/);
   host.querySelector('.fallback-play').click();flushSync();
   const payload=calls.at(-1)[1];assert.equal(calls.at(-1)[0],'play');assert.equal(payload.videoId,'artist-main');assert.equal(payload.isVideo,kind==='video');assert.equal(payload.setVideoId,undefined);assert.equal(payload.library,undefined);
   host.querySelector('.actions .more').click();flushSync();assert.equal(calls.at(-1)[1].kind,'song');assert.equal(calls.at(-1)[1].song.videoId,payload.videoId);
   await unmount(app);host.remove();
  }
 });
}

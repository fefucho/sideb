import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import path from 'node:path';
import {Window} from 'happy-dom';
import {compile} from 'svelte/compiler';
import ts from 'typescript';

// Use the browser runtime explicitly: the normal Node export renders SSR only.
const root=fileURLToPath(new URL('../',import.meta.url)),cache=path.join(root,'.cache/animated-artwork-test');
await mkdir(cache,{recursive:true});
const window=new Window({url:'http://tauri.localhost'});
for(const key of ['window','document','navigator','HTMLElement','HTMLMediaElement','HTMLVideoElement','Element','Node','Text','Comment','Event','CustomEvent','MutationObserver']) Object.defineProperty(globalThis,key,{value:key==='window'?window:window[key],configurable:true});
window.document.hasFocus=()=>true;
window.matchMedia=()=>({matches:false,addEventListener(){},removeEventListener(){}});
globalThis.requestAnimationFrame=callback=>setTimeout(callback,0); globalThis.cancelAnimationFrame=clearTimeout;
const clientUrl=pathToFileURL(path.join(root,'node_modules/svelte/src/index-client.js')).href;
const {mount,unmount,flushSync}=await import(clientUrl);
const jobs=[],cancels=[],callbacks=new Map();let nextFrame=0;
window.HTMLMediaElement.prototype.play=function(){Object.defineProperty(this,'paused',{value:false,configurable:true});return Promise.resolve();};
window.HTMLMediaElement.prototype.pause=function(){Object.defineProperty(this,'paused',{value:true,configurable:true});};
window.HTMLMediaElement.prototype.load=function(){};
window.HTMLVideoElement.prototype.requestVideoFrameCallback=function(callback){const id=++nextFrame;callbacks.set(id,callback);return id;};
window.HTMLVideoElement.prototype.cancelVideoFrameCallback=function(id){callbacks.delete(id);};
globalThis.__motionTest={jobs,cancels,release:null};
await writeFile(path.join(cache,'bridge.mjs'),`export const prepareAnimatedArtwork=(request,id)=>new Promise(resolve=>globalThis.__motionTest.jobs.push({request,id,resolve}));export const cancelAnimatedArtwork=async id=>{globalThis.__motionTest.cancels.push(id)};export const animatedArtworkUrl=asset=>'asset://localhost/'+asset.assetId;export const animatedArtworkClearState=()=>globalThis.__motionTest.coordinator.clearing;export const registerAnimatedArtworkRelease=release=>globalThis.__motionTest.coordinator.register(release);import {AnimatedArtworkClearCoordinator} from './clearCoordinator.mjs';globalThis.__motionTest.coordinator=new AnimatedArtworkClearCoordinator();`);
await writeFile(path.join(cache,'appearance.mjs'),`import {writable} from 'svelte/store'; export const appearance=writable({animatedArtwork:true});`);
for(const name of ['controller','policy','clearCoordinator']){const source=await readFile(path.join(root,`src/lib/artwork/${name}.ts`),'utf8');await writeFile(path.join(cache,`${name}.mjs`),ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText);}
await writeFile(path.join(cache,'runtime.mjs'),`export const initialAnimatedArtworkRuntimeState={visible:true,minimized:false,cloaked:false,powerSaver:false,memoryPressure:false};export const observeAnimatedArtworkRuntime=publish=>{globalThis.__motionTest.publishRuntime=publish;return()=>{globalThis.__motionTest.publishRuntime=null}};`);
const component=await readFile(path.join(root,'src/lib/components/fullscreen/AnimatedArtwork.svelte'),'utf8');
let compiled=compile(component,{filename:'AnimatedArtwork.svelte',generate:'client'}).js.code;
compiled=compiled.replace(/from ['"]svelte['"]/g,`from '${clientUrl}'`).replaceAll("'$lib/appearance/preferences'","'./appearance.mjs'").replaceAll("'$lib/artwork/animated'","'./bridge.mjs'").replaceAll("'$lib/artwork/policy'","'./policy.mjs'").replaceAll("'$lib/artwork/controller'","'./controller.mjs'").replaceAll("'$lib/artwork/runtime'","'./runtime.mjs'");
await writeFile(path.join(cache,'AnimatedArtwork.mjs'),compiled);
const Artwork=(await import(pathToFileURL(path.join(cache,'AnimatedArtwork.mjs')).href)).default;
const settle=async(ms=0)=>{await new Promise(resolve=>setTimeout(resolve,ms));flushSync();await Promise.resolve();flushSync();};
const track=(albumId,videoId=albumId)=>({videoId,title:'Song',artists:'Artist',album:'Album',albumId,duration:120});
const asset=id=>({assetId:id,localPath:'/cache/'+id,codec:'avc1.640028',width:1080,height:1080,frameRate:60,sizeBytes:123});
function metadata(video,changes={}) {for(const [name,value] of Object.entries({videoWidth:1080,videoHeight:1080,duration:15,readyState:2,...changes}))Object.defineProperty(video,name,{value,configurable:true});video.dispatchEvent(new window.Event('loadeddata'));flushSync();}

test('mounted component cancels pending A, renders B, preserves same-album pause/flip and rejects stale first-frame callbacks',async()=>{
 const props={track:track('A'),session:1,isPlaying:true,flipped:false};
 // A small reactive wrapper models actual parent prop updates.
 let wrapper=compile(`<script>import Artwork from './AnimatedArtwork.mjs'; let state=$state(globalThis.__motionProps); globalThis.__setMotionProps=next=>Object.assign(state,next);</script><Artwork {...state}/>` ,{filename:'Harness.svelte',generate:'client'}).js.code.replace(/from ['"]svelte['"]/g,`from '${clientUrl}'`);
 globalThis.__motionProps=props;await writeFile(path.join(cache,'Harness.mjs'),wrapper);
 const Harness=(await import(pathToFileURL(path.join(cache,'Harness.mjs')).href)).default;
 const app=mount(Harness,{target:document.body});flushSync();await settle(330);assert.equal(jobs.length,1);
 globalThis.__setMotionProps({track:track('B')});flushSync();await settle(330);assert.deepEqual(cancels,[jobs[0].id]);
 jobs[0].resolve(asset('A'));await settle(15);assert.equal(jobs.length,2);assert.equal(document.querySelector('video'),null);
 jobs[1].resolve(asset('B'));await settle();const b=document.querySelector('video');assert.ok(b);metadata(b);
 const stale=[...callbacks.values()].at(-1);assert.equal(b.classList.contains('shown'),false);
 stale();flushSync();assert.equal(b.classList.contains('shown'),true);
 globalThis.__setMotionProps({isPlaying:false,flipped:true,track:track('B','next track')});flushSync();await settle();assert.equal(document.querySelector('video'),b);assert.equal(b.paused,true);assert.equal(jobs.length,2);
 globalThis.__setMotionProps({isPlaying:true,flipped:false,session:2});flushSync();await settle(330);assert.equal(jobs.length,3);assert.equal(document.querySelector('video'),null);
 jobs[2].resolve(asset('B-account2'));await settle();const fresh=document.querySelector('video');assert.notEqual(fresh,b);stale();flushSync();assert.equal(fresh.classList.contains('shown'),false);
 metadata(fresh,{videoWidth:2160,videoHeight:2160});await settle();assert.equal(document.querySelector('video'),null);
 globalThis.__setMotionProps({track:track('B','third track')});flushSync();await settle(330);assert.equal(jobs.length,3);
 await unmount(app);await settle();assert.equal(callbacks.size,0);
});

test('real component rejects duration/fps/codec violations and abandons a source without loadeddata',async()=>{
 for(const changes of [{duration:61},{frameRate:120},{codec:'hvc1.2.4.L120'}]) {
  const before=jobs.length;
  const app=mount(Artwork,{target:document.body,props:{track:track(`invalid-${before}`),session:1,isPlaying:true,flipped:false}});
  flushSync();await settle(330);assert.equal(jobs.length,before+1);
  jobs[before].resolve({...asset(`invalid-${before}`),...changes});await settle();
  const video=document.querySelector('video');metadata(video,changes.duration?{duration:changes.duration}:{});await settle();
  assert.equal(document.querySelector('video'),null);await unmount(app);await settle();
 }
 const originalTimeout=globalThis.setTimeout;
 globalThis.setTimeout=(callback,delay,...args)=>originalTimeout(callback,delay===8000?10:delay,...args);
 try {
  const before=jobs.length;
  const app=mount(Artwork,{target:document.body,props:{track:track('no-loadeddata'),session:1,isPlaying:true,flipped:false}});
  flushSync();await settle(330);jobs[before].resolve(asset('no-loadeddata'));await settle();assert.ok(document.querySelector('video'));
  await settle(25);assert.equal(document.querySelector('video'),null);assert.ok(cancels.includes(jobs[before].id));
  await unmount(app);await settle();
 } finally {globalThis.setTimeout=originalTimeout;}
});


test('track-only duration/title enrichment retries a static result but retains an existing player',async()=>{
 const before=jobs.length;
 globalThis.__motionProps={track:{...track(null,'track-only'),album:null,title:'',duration:null},session:1,isPlaying:true,flipped:false,audioDuration:null};
 const Harness=(await import(pathToFileURL(path.join(cache,'Harness.mjs')).href)).default;
 const app=mount(Harness,{target:document.body});flushSync();await settle(330);
 assert.equal(jobs[before].request.durationSecs,null);jobs[before].resolve(null);await settle();
 globalThis.__setMotionProps({audioDuration:123.2,track:{...track(null,'track-only'),album:null,title:'Known Song',duration:null}});flushSync();await settle(330);
 assert.equal(jobs.length,before+2);assert.equal(jobs[before+1].request.durationSecs,123);assert.equal(jobs[before+1].request.title,'Known Song');
 jobs[before+1].resolve(asset('track-only'));await settle();const retained=document.querySelector('video');assert.ok(retained);
 globalThis.__setMotionProps({audioDuration:125.4,track:{...track(null,'track-only'),album:null,title:'Enriched Song',duration:null}});flushSync();await settle(330);
 assert.equal(document.querySelector('video'),retained);assert.equal(jobs.length,before+2);
 await unmount(app);await settle();
});


test('a component mounted during cache deletion cannot prepare and stays blocked until album changes',async()=>{
 let finish;const deleting=globalThis.__motionTest.coordinator.clear(()=>new Promise(resolve=>finish=resolve));
 await settle();const before=jobs.length;
 globalThis.__motionProps={track:track('clear-mount'),session:1,isPlaying:true,flipped:false};
 const Harness=(await import(pathToFileURL(path.join(cache,'Harness.mjs')).href)).default;
 const app=mount(Harness,{target:document.body});
 flushSync();await settle(330);assert.equal(jobs.length,before);assert.equal(document.querySelector('video'),null);
 finish(0);await deleting;await settle(330);assert.equal(jobs.length,before);
 globalThis.__setMotionProps({track:track('after-clear')});flushSync();await settle(330);assert.equal(jobs.length,before+1);jobs[before].resolve(asset('after-clear'));await settle();
 await unmount(app);await settle();
});

test('visible without focus plays; hidden past the single 30s idle deadline releases then reuses preparation on return',async()=>{
 const originalTimeout=globalThis.setTimeout;
 let idleDeadlines=0;
 globalThis.setTimeout=(callback,delay,...args)=>{if(delay===30000){idleDeadlines++;return originalTimeout(callback,20,...args);}return originalTimeout(callback,delay,...args);};
 const before=jobs.length;window.document.hasFocus=()=>false;
 try {
  const app=mount(Artwork,{target:document.body,props:{track:track('visible-unfocused'),session:1,isPlaying:true,flipped:false}});
  flushSync();await settle(330);assert.equal(jobs.length,before+1);
  jobs[before].resolve(asset('unfocused'));await settle();const video=document.querySelector('video');assert.ok(video);assert.equal(video.paused,false);
  globalThis.__motionTest.publishRuntime({visible:true,minimized:true,cloaked:false,powerSaver:false,memoryPressure:false});flushSync();await settle();assert.equal(video.paused,true);
  await settle(35);assert.equal(document.querySelector('video'),null);assert.equal(idleDeadlines,1);assert.ok(cancels.includes(jobs[before].id));
  globalThis.__motionTest.publishRuntime({visible:true,minimized:false,cloaked:false,powerSaver:false,memoryPressure:false});flushSync();await settle(330);assert.equal(jobs.length,before+2);
  jobs[before+1].resolve(asset('unfocused'));await settle();const fresh=document.querySelector('video');assert.ok(fresh);metadata(fresh);assert.equal(fresh.classList.contains('shown'),false);
  [...callbacks.values()].at(-1)();flushSync();assert.equal(fresh.classList.contains('shown'),true);
  await unmount(app);await settle();
 }finally{globalThis.setTimeout=originalTimeout;window.document.hasFocus=()=>true;}
});


test('native power saver and memory pressure immediately detach and cancel a warm source',async()=>{
 for(const signal of ['powerSaver','memoryPressure']){
  const before=jobs.length;
  const app=mount(Artwork,{target:document.body,props:{track:track(signal),session:1,isPlaying:true,flipped:false}});
  flushSync();await settle(330);jobs[before].resolve(asset(signal));await settle();assert.ok(document.querySelector('video'));
  globalThis.__motionTest.publishRuntime({visible:true,minimized:false,cloaked:false,powerSaver:false,memoryPressure:false,[signal]:true});flushSync();await settle();
  assert.equal(document.querySelector('video'),null);assert.ok(cancels.includes(jobs[before].id));
  await unmount(app);await settle();
 }
});

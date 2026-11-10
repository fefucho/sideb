import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {mountedSvelteEnvironment} from './helpers/mount-svelte.mjs';
if(!process.execArgv.includes('--conditions=browser')) {
 test('mounted side-player cover: tall adoption, square fallback, suspension without remount',()=>{const {NODE_TEST_CONTEXT,...env}=process.env;const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});assert.equal(result.status,0,result.stdout+result.stderr);});
}else{
 const {root,dom,moduleFor,mount,unmount,flushSync}=await mountedSvelteEnvironment('sidebar-artwork');
 dom.matchMedia=()=>({matches:false,addEventListener(){},removeEventListener(){}});
 const jobs=[],cancels=[],providerJobs=[],providerReleases=[];let callbackId=0;const nativeCallbacks=new Map(),listeners=new Map();
 globalThis.__providerState=null;
 dom.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener(){}};
 dom.__TAURI_INTERNALS__={transformCallback:callback=>{nativeCallbacks.set(++callbackId,callback);return callbackId;},convertFileSrc:(file,protocol)=>`${protocol}://localhost/${file}`,
  invoke:(command,args)=>command==='plugin:event|listen'?(listeners.set(args.event,args.handler),Promise.resolve(args.handler)):command==='plugin:event|unlisten'?Promise.resolve():command==='get_animated_artwork_runtime_state'?Promise.resolve({visible:true,minimized:false,cloaked:false,powerSaver:false,memoryPressure:false})
   :command==='get_visual_provider_state'?Promise.resolve(globalThis.__providerState)
   :command==='prepare_visual_provider_artwork'?new Promise(resolve=>providerJobs.push({request:args.request,id:args.requestId,resolve}))
   :command==='cancel_visual_provider_artwork'?(providerReleases.push(args.requestId),Promise.resolve())
   :command==='prepare_animated_artwork'?new Promise((resolve,reject)=>jobs.push({request:args.request,id:args.requestId,resolve,reject})):command==='cancel_animated_artwork'?(cancels.push(args.requestId),Promise.resolve()):Promise.resolve(null)};
 const emit=(event,payload=null)=>nativeCallbacks.get(listeners.get(event))({event,payload});
 dom.HTMLMediaElement.prototype.play=function(){Object.defineProperty(this,'paused',{value:false,configurable:true});return Promise.resolve();};
 dom.HTMLMediaElement.prototype.pause=function(){Object.defineProperty(this,'paused',{value:true,configurable:true});};
 dom.HTMLMediaElement.prototype.load=function(){};
 Object.defineProperty(dom.HTMLMediaElement,'HAVE_CURRENT_DATA',{value:2,configurable:true});
 const component=path.join(root,'src/lib/components/playback-sidebar/SidebarArtwork.svelte');
 const track=(albumId,videoId=albumId)=>({videoId,title:'Song '+videoId,artists:'Artist',album:'Album '+albumId,albumId,duration:120,thumbnail:'https://lh3.googleusercontent.com/cover=w544-h544'});
 const playback=(albumId,extra={})=>({isPlaying:true,isLoading:false,isEnded:false,position:3,duration:120,generation:1,currentTrack:track(albumId),queue:{items:[],currentIndex:null},error:null,...extra});
 const asset=(id,width,height)=>({assetId:id,localPath:'/cache/'+id,codec:'avc1.640028',width,height,frameRate:24,sizeBytes:1234});
 globalThis.__sideProps={session:1,playback:playback('A')};globalThis.__portrait=[];
 const source=`<script>import Artwork from '${component}';let values=$state(globalThis.__sideProps);globalThis.__setSideProps=next=>Object.assign(values,next);</script><Artwork {...values} onPortraitChange={value=>globalThis.__portrait.push(value)}/>`;
 const Harness=(await import(await moduleFor(path.join(root,'src/lib/components/playback-sidebar/SidebarHarness.svelte'),source.replace(component,'./SidebarArtwork.svelte')))).default;
 const settle=async(ms=0)=>{await new Promise(r=>setTimeout(r,ms));flushSync();await Promise.resolve();flushSync();};
 function frame(video,width,height){for(const [name,value] of Object.entries({videoWidth:width,videoHeight:height,duration:15,readyState:2}))Object.defineProperty(video,name,{value,configurable:true});video.dispatchEvent(new dom.Event('loadeddata'));flushSync();}
 const rendered=()=>({tall:!!document.querySelector('.video.tall'),shown:!!document.querySelector('.video.shown'),poster:!document.querySelector('.poster.hidden')});

 test('requests the tall variant, adopts the portrait frame, keeps one <video> through suspension and drops it with the sidebar',async()=>{
  const app=mount(Harness,{target:document.body});flushSync();await settle(330);
  assert.equal(jobs.length,1);assert.equal(jobs[0].request.preferTall,true,'the sidebar asks for portrait');assert.equal(jobs[0].request.preferHevc,false);
  assert.deepEqual(rendered(),{tall:false,shown:false,poster:true},'the poster card is shown first');
  jobs[0].resolve(asset('A-tall',1080,1440));await settle();const video=document.querySelector('video');assert.ok(video);
  frame(video,1080,1440);await settle(30);
  assert.deepEqual(rendered(),{tall:true,shown:true,poster:false},'portrait takes over only after a ready frame');
  assert.deepEqual(globalThis.__portrait,[true]);  assert.match(video.getAttribute('style')??'',/mask-image/,'portrait video fades at the bottom');
  assert.equal(video.paused,false);
  // A brief scroll suspends playback but never replaces or removes the element, nor asks for a new asset.
  globalThis.__setSideProps({scrollOffset:120});flushSync();await settle();assert.equal(document.querySelector('video'),video);assert.equal(video.paused,true);assert.equal(jobs.length,1);
  globalThis.__setSideProps({scrollOffset:0});flushSync();await settle();assert.equal(document.querySelector('video'),video,'same decode identity after returning');assert.equal(video.paused,false);assert.equal(jobs.length,1);
  // Another tab behaves like scrolling away.
  globalThis.__setSideProps({active:false});flushSync();await settle();assert.equal(document.querySelector('video'),video);assert.equal(video.paused,true);
  globalThis.__setSideProps({active:true});flushSync();await settle();assert.equal(video.paused,false);
  // Paused audio still shows the already prepared first frame (prepareWhilePaused) without playing.
  globalThis.__setSideProps({playback:playback('A',{isPlaying:false})});flushSync();await settle();assert.equal(document.querySelector('video'),video);assert.equal(video.paused,true);assert.equal(rendered().shown,true);
  // Same album, next track: nothing is rebuilt, orientation and player persist.
  globalThis.__setSideProps({playback:{...playback('A'),currentTrack:{...track('A','A2'),title:'Next'}}});flushSync();await settle(330);assert.equal(document.querySelector('video'),video);assert.equal(jobs.length,1);assert.equal(rendered().tall,true);
  // New album: geometry returns to the card until a new frame; the old video is released.
  globalThis.__setSideProps({playback:playback('B')});flushSync();await settle(330);
  assert.equal(document.querySelector('video'),null);assert.deepEqual(rendered(),{tall:false,shown:false,poster:true});assert.equal(globalThis.__portrait.at(-1),false);
  assert.equal(jobs.length,2);assert.equal(jobs[1].request.albumId,'B');
  // The core fell back to a square master: the card stays and the square video replaces its poster.
  jobs[1].resolve(asset('B-square',1080,1080));await settle();const square=document.querySelector('video');frame(square,1080,1080);await settle(30);
  assert.deepEqual(rendered(),{tall:false,shown:true,poster:false});
  // A new account never inherits the previous album's geometry/video.
  globalThis.__setSideProps({session:2});flushSync();await settle(330);assert.equal(document.querySelector('video'),null);assert.equal(jobs.length,3);
  jobs[2].resolve(asset('B-tall',1080,1440));await settle();frame(document.querySelector('video'),1080,1440);await settle(30);assert.equal(rendered().tall,true);
  // Closing/covering the sidebar releases immediately (no 30 s wait).
  globalThis.__setSideProps({presented:false});flushSync();await settle();assert.equal(document.querySelector('video'),null);assert.deepEqual(rendered(),{tall:false,shown:false,poster:true});
  await unmount(app);await settle();
 });

 test('a tall-looking video for a square-only request, and an invalid orientation, are rejected without a portrait layout',async()=>{
  const before=jobs.length;globalThis.__sideProps={session:7,playback:playback('R')};
  const app=mount(Harness,{target:document.body});flushSync();await settle(330);assert.equal(jobs.length,before+1);
  jobs[before].resolve(asset('R-wide',1440,1080));await settle();const video=document.querySelector('video');frame(video,1440,1080);await settle();
  assert.equal(document.querySelector('video'),null,'landscape is never valid');assert.equal(rendered().tall,false);
  await unmount(app);await settle();
 });

 const providerState=(salt='s1')=>({installed:true,bundledAvailable:true,provider:null,enabled:true,hasCredential:true,authBlocked:false,revision:1,statusKey:'visualProvider.status.ready',identitySalt:salt});
 const providerAsset=(id,width=720,height=1280)=>({...asset('visual-extension:'+id,width,height),frameRate:30});

 test('provider fallback: Apple first, sidebar only, per-track identity, leased and released with the video',async()=>{
  globalThis.__providerState=providerState('s1');
  const a0=jobs.length,p0=providerJobs.length,r0=providerReleases.length;globalThis.__sideProps={session:20,playback:playback('P')};
  let app=mount(Harness,{target:document.body});flushSync();await settle(330);
  assert.equal(jobs.length,a0+1,'Apple is asked first');assert.equal(providerJobs.length,p0,'a valid answer would never reach the provider');
  jobs[a0].resolve(asset('P-apple',1080,1440));await settle();frame(document.querySelector('video'),1080,1440);await settle(30);
  assert.equal(providerJobs.length,p0,'a usable Apple asset never consults the provider');assert.equal(rendered().tall,true);
  await unmount(app);await settle();
  // Apple empty → provider answers for the same request id with the same request shape.
  globalThis.__sideProps={session:21,playback:playback('Q')};app=mount(Harness,{target:document.body});flushSync();await settle(330);
  const apple=jobs.at(-1);assert.equal(apple.request.preferTall,true);apple.resolve(null);await settle();
  assert.equal(providerJobs.length,p0+1);const provider=providerJobs.at(-1);assert.equal(provider.id,apple.id);assert.equal(provider.request.artists,'Artist');assert.equal(provider.request.videoId,'Q');
  provider.resolve(providerAsset('Q'));await settle();const video=document.querySelector('video');assert.ok(video);frame(video,720,1280);await settle(30);
  assert.equal(rendered().tall,true,'the 9:16 provider video is portrait');
  // Identity is per track while the provider is active: the next song of the same album is requested again.
  const before=jobs.length;globalThis.__setSideProps({playback:{...playback('Q'),currentTrack:{...track('Q','Q2')}}});flushSync();await settle(330);
  assert.equal(jobs.length,before+1,'a provider Canvas is not shared across songs of one album');assert.equal(document.querySelector('video'),null);
  assert.ok(providerReleases.includes(provider.id),'the old lease is released when its video goes away');
  // Apple error behaves like empty for the enabled vertical player.
  jobs.at(-1).reject(new Error('apple failed'));await settle();assert.equal(providerJobs.at(-1).request.videoId,'Q2');
  // Closing the sidebar releases the leased file.
  providerJobs.at(-1).resolve(providerAsset('Q2'));await settle();frame(document.querySelector('video'),720,1280);await settle(30);
  const leased=providerJobs.at(-1).id;globalThis.__setSideProps({presented:false});flushSync();await settle();
  assert.equal(document.querySelector('video'),null);assert.ok(providerReleases.includes(leased));
  await unmount(app);await settle();
 });

 test('provider: cancellation does not fall back, disabled provider is never asked, 1921 px is rejected and will-change drops the src first',async()=>{
  globalThis.__providerState=providerState('s2');
  let p=providerJobs.length;globalThis.__sideProps={session:30,playback:playback('C1')};
  let app=mount(Harness,{target:document.body});flushSync();await settle(330);
  const pending=jobs.at(-1);globalThis.__setSideProps({playback:playback('C2')});flushSync();await settle(330);
  assert.ok(cancels.includes(pending.id));pending.resolve(null);await settle();
  assert.equal(providerJobs.length,p,'a cancelled request never falls back to the provider');
  jobs.at(-1).resolve(null);await settle();const live=providerJobs.at(-1);
  live.resolve(providerAsset('C2',1080,1921));await settle();frame(document.querySelector('video'),1080,1921);await settle();
  assert.equal(document.querySelector('video'),null,'the provider limit is 1920 px');
  await unmount(app);await settle();
  // will-change: the provider video disappears synchronously and the request is made again.
  globalThis.__sideProps={session:31,playback:playback('W')};app=mount(Harness,{target:document.body});flushSync();await settle(330);
  jobs.at(-1).resolve(null);await settle();providerJobs.at(-1).resolve(providerAsset('W'));await settle();frame(document.querySelector('video'),720,1280);await settle(30);
  const before=jobs.length;assert.ok(document.querySelector('video'));emit('visual-provider-will-change');flushSync();
  assert.equal(document.querySelector('video'),null,'src dropped before files are released');await settle(330);assert.equal(jobs.length,before+1);
  await unmount(app);await settle();
  // Provider disabled: Apple empty is final.
  globalThis.__providerState={...providerState(null),enabled:false};p=providerJobs.length;
  globalThis.__sideProps={session:32,playback:playback('D')};app=mount(Harness,{target:document.body});flushSync();await settle(330);
  jobs.at(-1).resolve(null);await settle();assert.equal(providerJobs.length,p);await unmount(app);await settle();
 });

 test('fullscreen (not vertical) never consults the provider nor reacts to its changes',async()=>{
  globalThis.__providerState=providerState('s3');
  const FullscreenArtwork=(await import(await moduleFor(path.join(root,'src/lib/components/fullscreen/AnimatedArtwork.svelte')))).default;
  const p=providerJobs.length,a=jobs.length;
  const app=mount(FullscreenArtwork,{target:document.body,props:{track:track('F'),session:40,isPlaying:true,flipped:false}});flushSync();await settle(330);
  assert.equal(jobs.at(-1).request.preferTall,false);jobs.at(-1).resolve(null);await settle();
  assert.equal(providerJobs.length,p,'Apple empty stays empty in fullscreen');
  const second=jobs.length;emit('visual-provider-will-change');await settle(330);assert.equal(jobs.length,second,'provider changes do not touch fullscreen');
  await unmount(app);await settle();assert.ok(a<=jobs.length);
 });
}

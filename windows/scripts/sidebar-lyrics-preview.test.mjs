import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {mountedSvelteEnvironment} from './helpers/mount-svelte.mjs';
if(!process.execArgv.includes('--conditions=browser')) {
 test('mounted lyrics sample: real renderer, clock, symmetric frame, open action and lifecycle',()=>{const {NODE_TEST_CONTEXT,...env}=process.env;const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});assert.equal(result.status,0,result.stdout+result.stderr);});
}else{
 const {root,dom,moduleFor,mount,unmount,flushSync}=await mountedSvelteEnvironment('sidebar-lyrics-preview');
 dom.Range.prototype.getClientRects=function(){const width=(this.endOffset-this.startOffset)*8;return width>0?[{left:this.startOffset*8,top:0,width,height:20,right:this.endOffset*8,bottom:20}]:[];};
 dom.matchMedia=()=>({matches:false,addEventListener(){},removeEventListener(){}});
 const requests=[];const nativeCallbacks=new Map();let callbackId=0;
 dom.__TAURI_EVENT_PLUGIN_INTERNALS__={unregisterListener(){}};
 dom.__TAURI_INTERNALS__={transformCallback:callback=>{nativeCallbacks.set(++callbackId,callback);return callbackId;},
  invoke:(command,args)=>command==='plugin:event|listen'?Promise.resolve(1):command==='plugin:event|unlisten'?Promise.resolve():command==='get_animated_artwork_runtime_state'?Promise.resolve({visible:true,minimized:false,cloaked:false,powerSaver:false,memoryPressure:false})
   :command==='get_karaoke_lyrics'?new Promise(resolve=>requests.push({args,resolve})):Promise.resolve(null)};
 const {KaraokeClock}=await import(await moduleFor(path.join(root,'src/lib/player/karaoke-clock.ts')));
 const observations=[];const observe=KaraokeClock.prototype.observe;
 KaraokeClock.prototype.observe=function(...args){observations.push(args);return observe.apply(this,args);};
 const component=path.join(root,'src/lib/components/playback-sidebar/SidebarLyricsPreview.svelte');
 const line=(text,timeMs,words=[])=>({text,timeMs,endTimeMs:timeMs+2000,words});
 const classic={status:'ready',trackKey:JSON.stringify(['a',1,JSON.stringify([1,'one'])]),lyrics:{provider:'LRCLIB',isSynced:true,lines:[line('First plain',0),line('Second plain',5000),line('Third plain',10000)]},error:null};
 const playback=(position=1,extra={})=>({isPlaying:false,isLoading:false,position,duration:30,generation:1,queue:{items:[{entryId:'one'}],currentIndex:0},currentTrack:{videoId:'a',title:'Song',artists:'Artist',duration:30},...extra});
 const opened=[];
 globalThis.__previewProps={session:1,playback:playback(),lyricsState:classic,active:true,onOpen:()=>opened.push(1)};
 const source=`<script>import Preview from '${component}';let values=$state(globalThis.__previewProps);globalThis.__setPreview=next=>Object.assign(values,next);</script><div style="height:200px"><Preview {...values}/></div>`;
 const Harness=(await import(await moduleFor(path.join(root,'src/lib/components/playback-sidebar/PreviewHarness.svelte'),source.replace(component,'./SidebarLyricsPreview.svelte')))).default;
 const settle=async(ms=5)=>{await new Promise(r=>setTimeout(r,ms));flushSync();await Promise.resolve();flushSync();};
 const focused=()=>[...document.querySelectorAll('.group.focused [data-line]')].map(row=>row.textContent.trim());

 test('renders the classic fallback, then the rich document with the real karaoke ink; the clock moves the focus; the card opens Letras',async()=>{
  const app=mount(Harness,{target:document.body});flushSync();await settle();
  assert.equal(requests.length,1,'one rich request for the occurrence');assert.equal(requests[0].args.source,'auto');
  assert.match(document.body.textContent,/First plain/);assert.deepEqual(focused(),['First plain'],'position 1 s focuses the first line');
  assert.equal(document.querySelector('.content').getAttribute('aria-hidden'),'true');assert.equal(document.querySelector('.card').getAttribute('role'),'button');
  assert.equal(document.querySelectorAll('.lyrics-scroll button, .lyrics-scroll [tabindex]').length,0,'no interactive controls inside the sample');
  assert.equal(document.querySelectorAll('header, h1, h2, h3').length,0,'no header or arrow');assert.match(document.querySelector('.more').textContent,/Mostrar más/);
  requests[0].resolve({provider:'TTML',isSynced:true,instrumental:false,lines:[line('Rich one',0,[{text:'Rich',startMs:0,endMs:500},{text:'one',startMs:500,endMs:1000}]),line('Rich two',5000),line('Rich three',10000)]});await settle(20);
  assert.match(document.body.textContent,/Rich one/);assert.doesNotMatch(document.body.textContent,/First plain/);
  assert.ok(document.querySelector('.phrase .effects'),'rendered by KaraokePhrase (the Letras renderer)');
  globalThis.__setPreview({playback:playback(5.5)});flushSync();await settle();assert.deepEqual(focused(),['Rich two'],'the shared clock moves the active group');
  globalThis.__setPreview({playback:playback(12)});flushSync();await settle();assert.deepEqual(focused(),['Rich three']);
  document.querySelector('.card').click();flushSync();assert.equal(opened.length,1);
  document.querySelector('.card').dispatchEvent(new dom.KeyboardEvent('keydown',{key:'Enter',bubbles:true}));flushSync();assert.equal(opened.length,2);
  // Same video in another account never reuses the previous lyrics.
  globalThis.__setPreview({session:2});flushSync();await settle(20);assert.doesNotMatch(document.body.textContent,/Rich|plain/);
  await unmount(app);await settle();
 });

 test('playing reaches the clock only while visible; leaving the screen stops the request, the clock and the content',async()=>{
  globalThis.__previewProps={session:1,playback:playback(2,{isPlaying:true}),lyricsState:classic,active:true,onOpen(){}};
  const callbacksBefore=nativeCallbacks.size;
  const app=mount(Harness,{target:document.body});flushSync();await settle();
  assert.equal(observations.at(-1)[1],true,'visible and playing drives the clock');
  const signal=[...nativeCallbacks.values()][callbacksBefore];
  signal({payload:{visible:true,minimized:true,cloaked:false,powerSaver:false,memoryPressure:false}});flushSync();await settle();assert.equal(observations.at(-1)[1],false,'minimized window freezes the sample');
  signal({payload:{visible:true,minimized:false,cloaked:false,powerSaver:false,memoryPressure:false}});flushSync();await settle();assert.equal(observations.at(-1)[1],true);
  const count=requests.length;globalThis.__setPreview({active:false});flushSync();await settle();
  assert.equal(document.querySelector('.lyrics-scroll'),null,'no content while off screen');assert.equal(observations.at(-1)[1],false);assert.equal(requests.length,count);
  globalThis.__setPreview({active:true});flushSync();await settle();assert.ok(document.querySelector('.lyrics-scroll'),'reopening shows the sample again');
  await unmount(app);await settle();
 });

 test('status states: searching, no lyrics, no track and instrumental',async()=>{
  const empty={status:'idle',trackKey:null,lyrics:null,error:null};
  globalThis.__previewProps={session:3,playback:playback(0),lyricsState:{...empty,status:'loading'},active:true,onOpen(){}};
  const app=mount(Harness,{target:document.body});flushSync();await settle();
  assert.match(document.body.textContent,/Buscando letra/);
  globalThis.__setPreview({lyricsState:{...empty,status:'empty'}});flushSync();await settle();
  const pending=requests.at(-1);pending.resolve(null);await settle(20);assert.match(document.body.textContent,/Sin letras disponibles/);
  globalThis.__setPreview({playback:{...playback(0),currentTrack:null}});flushSync();await settle();assert.doesNotMatch(document.body.textContent,/Sin letras disponibles/);
  globalThis.__setPreview({playback:playback(0)});flushSync();await settle();
  requests.at(-1).resolve({provider:'x',isSynced:false,instrumental:true,lines:[]});await settle(20);assert.match(document.body.textContent,/instrumental/i);
  await unmount(app);await settle();
 });
}

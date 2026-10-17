import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import ts from 'typescript';
import {compile} from 'svelte/compiler';
import {Window} from 'happy-dom';

// Svelte's browser entry is needed for real mounted-component interactions.
if(!process.execArgv.includes('--conditions=browser')) {
  test('volume policy, DOM routing and real Svelte components',()=>{
    const {NODE_TEST_CONTEXT,...env}=process.env;
    const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
    assert.equal(result.status,0,result.stdout+result.stderr);
    assert.match(result.stdout,/real bar stays closed for wheel/);
  });
} else {
const root=fileURLToPath(new URL('../',import.meta.url));
const cache=path.join(root,'.cache/volume-scroll-test');
await mkdir(cache,{recursive:true});
const compiled=new Map();
async function moduleFor(filename){
  if(compiled.has(filename))return compiled.get(filename);
  const destination=path.join(cache,createHash('sha256').update(filename).digest('hex')+'.mjs');
  const url=pathToFileURL(destination).href;compiled.set(filename,url);
  const source=await readFile(filename,'utf8');
  let code=filename.endsWith('.json')?'export default '+source:filename.endsWith('.svelte')?compile(source,{filename,generate:'client',css:'external'}).js.code:ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
  code=code.replace(/import\s+['"][^'"]+\.css['"];?/g,'');
  for(const match of [...code.matchAll(/(?:from\s+|import\s*\()(['"])(\$lib\/[^'"]+|\.{1,2}\/[^'"]+)\1/g)]){
    let target=match[2].startsWith('$lib/')?path.join(root,'src/lib',match[2].slice(5)):path.resolve(path.dirname(filename),match[2]);
    if(!path.extname(target)) {try{await readFile(target+'.ts');target+='.ts';}catch{target=path.join(target,'index.ts');}}
    code=code.replaceAll(match[0],match[0].replace(match[2],await moduleFor(target)));
  }
  await writeFile(destination,code);return url;
}
const dom=new Window({url:'http://localhost',settings:{disableCSSFileLoading:true,disableComputedStyleRendering:false,disableIframePageLoading:true,disableJavaScriptFileLoading:true,disableJavaScriptEvaluation:true}});
for(const name of ['window','document','navigator','Element','HTMLElement','HTMLInputElement','HTMLButtonElement','HTMLMediaElement','SVGElement','Node','Text','Comment','Event','MouseEvent','KeyboardEvent','PointerEvent','WheelEvent','MutationObserver','getComputedStyle'])Object.defineProperty(globalThis,name,{configurable:true,value:name==='window'?dom:name==='document'?dom.document:typeof dom[name]==='function'&&name==='getComputedStyle'?dom[name].bind(dom):dom[name]});
const {mount,unmount,flushSync,tick}=await import('svelte');
const {VolumeScrollPolicy,VolumeScrollFeedback,volumeScrollSurface}=await import(await moduleFor(path.join(root,'src/lib/player/volume-scroll.ts')));
const {installNavigationGestures}=await import(await moduleFor(path.join(root,'src/lib/navigation/gestures.ts')));
const {emptyPlaybackData}=await import(await moduleFor(path.join(root,'src/lib/player/controller.ts')));
const sample=(extra={})=>({x:0,y:-100,mode:0,at:1,surface:'fullscreen',cancelable:true,defaultPrevented:false,modified:false,...extra});
const context=(extra={})=>({revision:'account:track:generation:scene',enabled:true,blocked:false,value:42.3,...extra});

test('distance accumulation is invariant under sample subdivision in every deltaMode, preserves fractions and reverses immediately',()=>{
 for(const [mode,total] of [[0,300],[1,9],[2,3]]){
  for(const count of [1,3,9,30]){
   const policy=new VolumeScrollPolicy();let value=42.3;
   for(let i=0;i<count;i++){const output=policy.wheel(sample({y:-total/count,mode,at:i}),context({value}));value+=output.delta;assert.equal(output.consume,true);}
   assert.ok(Math.abs(value-45.3)<1e-8);
  }
 }
 const p=new VolumeScrollPolicy();assert.equal(p.wheel(sample({y:-90}),context()).delta,0);assert.equal(p.wheel(sample({y:100,at:2}),context()).delta,-1);
});
test('bounds discard excess and unsafe magnitudes never produce nonfinite commands or reversal debt',()=>{
 for(const value of [0,100,Number.NaN,Number.POSITIVE_INFINITY]){
  const p=new VolumeScrollPolicy();for(let at=1;at<4;at++){assert.ok(Number.isFinite(p.wheel(sample({y:-Number.MAX_VALUE,at}),context({value})).delta));}
 }
 const p=new VolumeScrollPolicy();assert.equal(p.wheel(sample({y:-Number.MAX_VALUE}),context({value:100})).delta,0);assert.equal(p.wheel(sample({y:100,at:2}),context({value:100})).delta,-1);
 const q=new VolumeScrollPolicy();q.wheel(sample({y:1000}),context({value:0}));assert.equal(q.wheel(sample({y:-100,at:2}),context({value:0})).delta,1);
});
test('ambiguous, invalid, modified, preconsumed and noncancelable starts never become volume within a burst',()=>{
 for(const extra of [{y:0},{x:100,y:100},{y:NaN},{y:Infinity},{mode:7},{modified:true},{defaultPrevented:true},{cancelable:false},{momentum:true},{surface:null}]){
  const p=new VolumeScrollPolicy();assert.equal(p.wheel(sample(extra),context()).consume,false);assert.equal(p.wheel(sample({at:100}),context()).delta,0);assert.equal(p.wheel(sample({at:281}),context()).delta,1);
 }
});
test('owned input drains on exit, revision, modal, drag or cancellation without transferring to a panel, and resumes only after quiet',()=>{
 for(const [extra,ctx] of [[{surface:null},{}],[{}, {revision:'new-generation'}],[{}, {blocked:true}],[{surface:'bar'},{}]]){
  const p=new VolumeScrollPolicy();p.wheel(sample(),context());const out=p.wheel(sample({at:2,...extra}),context(ctx));assert.equal(out.delta,0);assert.equal(out.consume,true);assert.equal(out.cancelled,true);
  assert.equal(p.wheel(sample({at:80}),context()).delta,0);assert.equal(p.wheel(sample({at:261}),context()).delta,1);
 }
 const p=new VolumeScrollPolicy();p.wheel(sample(),context());p.cancel();assert.equal(p.wheel(sample({at:2}),context()).delta,0);
});
test('modern momentum never adjusts or refreshes feedback; absent signal follows explicit fallback',()=>{
 const p=new VolumeScrollPolicy();assert.equal(p.wheel(sample({y:-50,momentum:false}),context()).feedback,true);
 const out=p.wheel(sample({at:2,momentum:true}),context());assert.equal(out.consume,true);assert.equal(out.delta,0);assert.equal(out.feedback,false);
 assert.equal(p.wheel(sample({at:3,momentum:false,y:-50}),context()).delta,1);
 const fallback=new VolumeScrollPolicy();assert.equal(fallback.wheel(sample(),context()).delta,1);
});
function clock(){let now=0,id=0;const timers=new Map();return{timers,set:(fn,delay)=>{timers.set(++id,{fn,at:now+delay});return id;},clear:id=>timers.delete(id),advance:duration=>{now+=duration;for(const [id,t] of [...timers])if(t.at<=now){timers.delete(id);t.fn();}}};}
test('feedback uses confirmed ACK value, groups announcements, expires 900ms from input and has no idle timers',()=>{
 const c=clock();let value=42,visible=false,announcement=null;const f=new VolumeScrollFeedback({value:()=>value,visible:v=>visible=v,announce:v=>announcement=v},c);
 f.confirmedChanged();assert.equal(c.timers.size,0);f.input();assert.equal(visible,true);c.advance(100);value=43;f.confirmedChanged();c.advance(100);assert.equal(announcement,null);c.advance(80);assert.equal(announcement,43);c.advance(620);assert.equal(visible,false);assert.equal(c.timers.size,0);
 f.input();c.advance(800);f.input();c.advance(100);assert.equal(visible,true);f.cancel();assert.equal(visible,false);assert.equal(announcement,null);assert.equal(c.timers.size,0);
});

const Fullscreen=(await import(await moduleFor(path.join(root,'src/lib/components/fullscreen/FullscreenNowPlaying.svelte')))).default;
const fullscreenStyle=document.createElement('style');fullscreenStyle.textContent=compile(await readFile(path.join(root,'src/lib/components/fullscreen/FullscreenNowPlaying.svelte'),'utf8'),{filename:path.join(root,'src/lib/components/fullscreen/FullscreenNowPlaying.svelte'),generate:'client',css:'external'}).css.code;document.head.append(fullscreenStyle);
const Bar=(await import(await moduleFor(path.join(root,'src/lib/components/player/PlayerBar.svelte')))).default;
const noop=()=>{};
const state=()=>({...emptyPlaybackData(),volume:42.3,currentTrack:{videoId:'fixture',title:'Fixture',artists:'Artist',thumbnail:null,artistRuns:[]},generation:4});
const fullscreenProps=()=>({playback:state(),confirmedVolume:42.3,geniusState:{phase:'idle',resolution:null},geniusController:{ensureNow:async()=>{}},onOpenExternal:noop,onSelectQueue:noop,onTogglePlayback:noop,onMoveQueue:async()=>{},lyricsState:{phase:'idle',lines:[],lyrics:null},recommendationsState:{phase:'idle',items:[],songs:[]},onSeek:noop,onRetryLyrics:noop,onRefreshRecommendations:noop,onPlayRecommendation:noop,onEnqueueRecommendation:noop,onSongContextMenu:noop,onArtistContextMenu:noop,onClose:noop});
function attach(Component,props){const host=document.createElement('div');document.body.append(host);let instance;flushSync(()=>instance=mount(Component,{target:host,props,intro:false}));return{host,instance,dispose:async()=>{await unmount(instance);host.remove();}};}
function routing(host){let hit=host.querySelector('.artwork')??host;document.elementFromPoint=()=>hit;let value=42.3,feedback=0,cancels=0;const deltas=[];const handle=installNavigationGestures(dom,{context:()=>({revision:'nav',enabled:true,blocked:false,fullscreen:true,reduceMotion:true,height:600,backTitle:'Back',forwardTitle:null}),progress:noop,commit:noop,volume:{context:()=>context({value,blocked:!!document.querySelector('[role="dialog"],[role="menu"]')}),adjust:delta=>{deltas.push(delta);value=Math.max(0,Math.min(100,value+delta));},feedback:()=>feedback++,cancelFeedback:()=>cancels++}});let time=1;return{deltas,setHit:node=>hit=node,get feedback(){return feedback;},get cancels(){return cancels;},wheel:(target=hit,extra={})=>{const event=new dom.WheelEvent('wheel',{bubbles:true,cancelable:true,deltaY:-100,clientX:40,clientY:40,...extra});// happy-dom WheelEvent currently derives from UIEvent; supply browser MouseEvent fields.
for(const name of ['ctrlKey','altKey','metaKey','shiftKey'])Object.defineProperty(event,name,{value:extra[name]??false});
Object.defineProperty(event,'timeStamp',{value:time+=10});target.dispatchEvent(event);return event;},quiet:()=>time+=181,handle};}
test('real fullscreen volume is limited to cover and bar; background never owns or adopts a volume burst',async()=>{
 const fixture=attach(Fullscreen,fullscreenProps()),r=routing(fixture.host);const art=fixture.host.querySelector('.artwork'),scene=fixture.host.querySelector('.layout'),panel=fixture.host.querySelector('.side-column');
 assert.equal(volumeScrollSurface(art),'fullscreen');
 for(const selector of ['.fullscreen','.layout','.art-column','.art-block','.artwork-flip','.side-column','.panel','.track-info','.artwork-back','.close-button','.information-button'])assert.equal(volumeScrollSurface(fixture.host.querySelector(selector)),null,selector);
 // Starting on empty background and crossing onto the artwork cannot adopt that burst.
 r.setHit(scene);assert.equal(r.wheel().defaultPrevented,false);r.setHit(art);r.wheel();assert.deepEqual(r.deltas,[]);assert.equal(r.feedback,0);
 r.quiet();assert.equal(r.wheel(art).defaultPrevented,true);assert.deepEqual(r.deltas,[1]);
 // Even when the browser retains the artwork target, leaving onto background drains volume.
 r.setHit(scene);assert.equal(r.wheel(art).defaultPrevented,true);assert.deepEqual(r.deltas,[1]);r.setHit(art);r.wheel();assert.deepEqual(r.deltas,[1]);
 r.quiet();r.setHit(scene);assert.equal(r.wheel().defaultPrevented,false);assert.deepEqual(r.deltas,[1]);
 r.quiet();r.setHit(art);r.wheel();assert.deepEqual(r.deltas,[1,1]);
 r.setHit(panel);assert.equal(r.wheel(art).defaultPrevented,true);assert.deepEqual(r.deltas,[1,1]);
 r.quiet();r.setHit(panel);assert.equal(r.wheel().defaultPrevented,false);r.setHit(art);r.wheel();assert.equal(r.deltas.length,2);
 r.quiet();r.wheel();assert.equal(r.deltas.length,3);
 r.setHit(scene);const move=new dom.PointerEvent('pointermove',{bubbles:true,clientX:40,clientY:40,pointerId:9});Object.defineProperty(move,'timeStamp',{value:150});scene.dispatchEvent(move);assert.ok(r.cancels>0);
 r.handle.dispose();await fixture.dispose();
});
test('real bar stays closed for wheel, opens on click, range owns exactly one custom adjustment and drag wins',async()=>{
 let inputs=0;const fixture=attach(Bar,{playback:state(),onTogglePlayback:noop,onRetryPlayback:noop,onPrevious:noop,onNext:noop,onSeek:noop,onVolumeChange:()=>inputs++,onSetShuffle:noop,onSetRepeat:noop,fullscreenOpen:false,onToggleFullscreen:noop});
 const toggle=fixture.host.querySelector('.volume-toggle'),range=fixture.host.querySelector('#player-volume input[type="range"]');const r=routing(fixture.host);r.setHit(toggle);assert.equal(r.wheel().defaultPrevented,false);assert.equal(fixture.host.querySelector('[data-volume-scroll="bar"]'),null);
 toggle.click();flushSync();await tick();assert.ok(fixture.host.querySelector('[data-volume-scroll="bar"]'));r.quiet();r.setHit(range);assert.equal(r.wheel().defaultPrevented,true);assert.deepEqual(r.deltas,[1]);assert.equal(inputs,0);
 range.dispatchEvent(new dom.PointerEvent('pointerdown',{bubbles:true,pointerId:7}));flushSync();r.quiet();assert.equal(volumeScrollSurface(range),null);assert.equal(r.wheel().defaultPrevented,false);assert.equal(r.deltas.length,1);
 dom.dispatchEvent(new dom.PointerEvent('pointerup',{pointerId:7}));r.handle.dispose();await fixture.dispose();
});
test('adapter rejects ineffective preventDefault, prior consumers, modifier zoom and noncancelable input',async()=>{
 const fixture=attach(Fullscreen,fullscreenProps()),r=routing(fixture.host),art=fixture.host.querySelector('.artwork');
 for(const extra of [{ctrlKey:true},{altKey:true},{shiftKey:true},{metaKey:true},{cancelable:false}]){r.quiet();r.wheel(art,extra);}
 r.quiet();const prevented=e=>e.preventDefault();art.addEventListener('wheel',prevented);r.wheel();art.removeEventListener('wheel',prevented);
 r.quiet();const ineffective=e=>{e.preventDefault=()=>{};};art.addEventListener('wheel',ineffective);r.wheel();art.removeEventListener('wheel',ineffective);
 assert.deepEqual(r.deltas,[]);assert.equal(r.feedback,0);r.handle.dispose();await fixture.dispose();
});

// Compile the exact scalar dependencies/effect from +page rather than a duplicate
// policy, with its real fullscreen child and no native connection or providers.
const pageSource=await readFile(path.join(root,'src/routes/+page.svelte'),'utf8');
const errorEffect=pageSource.match(/  \$effect\(\(\)=>\{if\(volumeAudioError\)[^\n]+/)[0];
const routingDeclarations=pageSource.match(/  const volumeContextRevision[^\n]+\n  const volumeAudioError[^\n]+\n  const volumeAvailable[^\n]+\n  \$effect\(\(\)=>\{activeView;[^\n]+/)[0];
const harnessSource=`<script lang="ts">
 import Fullscreen from '$lib/components/fullscreen/FullscreenNowPlaying.svelte';
 import {untrack} from 'svelte';
 let {initialProps,onInvalidated}=$props();
 let playbackError=$state(null);
 let playbackState=$state(initialProps.playback),confirmedVolume=$state(42.3),volumeFeedbackVisible=$state(false);
 let homeSession=$state('guest'),isFullscreenOpen=$state(true),backendStatus=$state({ready:true}),authStatus=$state({state:'guest'});
 let activeView=$state('feed'),menuRequest=$state(null),spotlightOpen=$state(false),editingPlaylist=$state(null),deletingPlaylist=$state(null),creatingPlaylist=$state(false),updaterModalOpen=$state(false);
 let gestureInput={invalidate:()=>{volumeFeedbackVisible=false;onInvalidated();}};
 ${routingDeclarations}
 ${errorEffect}
 export function progress(value){playbackState=value;}
 export function confirmed(value){confirmedVolume=value;}
 export function feedback(){volumeFeedbackVisible=true;}
 export function modal(value){updaterModalOpen=value;}
 export function error(value){playbackError=value;}
 </script>
 <Fullscreen {...initialProps} playback={playbackState} {confirmedVolume} volumeFeedback={volumeFeedbackVisible} onVolumeSurfaceChange={()=>gestureInput.invalidate()} />`;
const harnessFile=path.join(cache,'VolumeSceneHarness.svelte');await writeFile(harnessFile,harnessSource);
const Scene=(await import(await moduleFor(harnessFile))).default;
test('root scalar routing survives same-track progress; real cover updates confirmed feedback without remount and places reverse feedback outside information',async()=>{
 let invalidations=0;const policy=new VolumeScrollPolicy();const props=fullscreenProps();props.playback.currentTrack.thumbnail='data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg"/>';
 const fixture=attach(Scene,{initialProps:props,onInvalidated:()=>{invalidations++;policy.cancel();}});
 flushSync();policy.wheel(sample(),context());const initial=invalidations,art=fixture.host.querySelector('.artwork'),image=art.querySelector('img');assert.ok(image);
 art.focus();assert.equal(art.matches(':focus-visible'),true);assert.equal(getComputedStyle(art.querySelector('.artwork-control')).opacity,'1');
 flushSync(()=>fixture.instance.feedback());assert.equal(art.classList.contains('volume-feedback'),true);assert.equal(getComputedStyle(art.querySelector('.artwork-control')).opacity,'0');assert.equal(getComputedStyle(art.querySelector('.artwork-percentage')).opacity,'1');
 for(let position=1;position<10;position++)flushSync(()=>fixture.instance.progress({...props.playback,position,currentTrack:{...props.playback.currentTrack},queue:{...props.playback.queue}}));
 assert.equal(invalidations,initial);assert.equal(policy.wheel(sample({at:20}),context()).delta,1);assert.equal(art.classList.contains('volume-feedback'),true);
 flushSync(()=>fixture.instance.confirmed(43.3));assert.equal(art.querySelector('.artwork-percentage').textContent,'43 %');assert.equal(art.querySelector('img'),image);
 fixture.host.querySelector('.information-button').click();flushSync();assert.ok(invalidations>initial);assert.equal(art.classList.contains('volume-feedback'),false);
 flushSync(()=>fixture.instance.feedback());const adjacent=fixture.host.querySelector('.volume-adjacent');assert.equal(adjacent.classList.contains('visible'),true);assert.equal(adjacent.closest('.artwork-back'),null);
 flushSync(()=>fixture.instance.error('Audio failed'));assert.equal(art.classList.contains('volume-feedback'),false);assert.equal(policy.wheel(sample({at:40}),context()).delta,0);assert.equal(policy.wheel(sample({at:221}),context()).delta,1);
 flushSync(()=>fixture.instance.feedback());flushSync(()=>fixture.instance.error(null));assert.equal(art.classList.contains('volume-feedback'),true);
 flushSync(()=>fixture.instance.feedback());flushSync(()=>fixture.instance.modal(true));assert.equal(art.classList.contains('volume-feedback'),false);
 flushSync(()=>fixture.instance.feedback());flushSync(()=>fixture.instance.progress({...props.playback,generation:5}));assert.equal(art.classList.contains('volume-feedback'),false);
 await fixture.dispose();
});

test('an external dialog blocks a visible scene and drains its existing burst after removal',async()=>{
 const fixture=attach(Fullscreen,fullscreenProps()),r=routing(fixture.host);r.wheel();assert.deepEqual(r.deltas,[1]);
 const overlay=document.createElement('div');overlay.setAttribute('role','dialog');document.body.append(overlay);
 assert.equal(r.wheel().defaultPrevented,true);assert.deepEqual(r.deltas,[1]);assert.ok(r.cancels>0);
 overlay.remove();r.wheel();assert.deepEqual(r.deltas,[1]);r.quiet();r.wheel();assert.deepEqual(r.deltas,[1,1]);
 r.handle.dispose();await fixture.dispose();
});
}

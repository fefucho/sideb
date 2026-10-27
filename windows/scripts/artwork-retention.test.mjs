import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if(!process.execArgv.includes('--conditions=browser')) {
 test('retained artwork detaches hidden work, resumes current geometry and rejects old image failures',()=>{
  const {NODE_TEST_CONTEXT,...env}=process.env;
  const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
  assert.equal(result.status,0,result.stdout+result.stderr);
 });
} else {
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('artwork-retention-test');
 const settle=async()=>{flushSync();await tick();flushSync();};
 const Fixture=(await import(await moduleFor(path.join(root,'scripts/fixtures/ArtworkRetentionFixture.svelte'),`<script>
  import {setContext} from 'svelte';
  import {PRESENTATION_CONTEXT} from '$lib/components/common/presentation';
  import RetainedPage from '$lib/components/shell/RetainedPage.svelte';
  import MediaArtwork from '$lib/components/common/MediaArtwork.svelte';
  import TrackArtwork from '$lib/components/common/TrackArtwork.svelte';
  let selected=$state(true),covered=$state(false),thumbnail=$state('https://lh3.googleusercontent.com/first=w120-h120-l90-rj');
  setContext(PRESENTATION_CONTEXT,{active:element=>{
   const current=selected,overlay=covered,page=element?.closest('[data-retained-page]');
   return !page||(current&&!overlay);
  }});
  export function select(value){selected=value;}
  export function cover(value){covered=value;}
  export function replace(){thumbnail='https://lh3.googleusercontent.com/replacement=w120-h120-l90-rj';}
 </script><RetainedPage id="feed" {selected} {covered}>{#snippet children(active)}
  <MediaArtwork title="Album" {thumbnail} onMenu={()=>{}}/>
  <TrackArtwork title="Track" {thumbnail} active={false} playing={false} onPlay={()=>{}}/>
 {/snippet}</RetainedPage>`))).default;

 test('real artwork components release observers/listeners under coverage and navigation, then reconcile DPR once',async()=>{
  const resize=new Set(),intersection=new Set();
  Object.defineProperty(globalThis,'ResizeObserver',{configurable:true,value:class{observe(){resize.add(this);}disconnect(){resize.delete(this);}}});
  Object.defineProperty(globalThis,'IntersectionObserver',{configurable:true,value:class{observe(){intersection.add(this);}disconnect(){intersection.delete(this);}}});
  const listeners={resize:new Set(),focus:new Set(),blur:new Set(),visibilitychange:new Set()};
  const originals=[];
  for(const [owner,names] of [[window,['resize','focus','blur']],[document,['visibilitychange']]]) {
   const add=owner.addEventListener,remove=owner.removeEventListener;
   owner.addEventListener=function(type,handler,...args){if(names.includes(type))listeners[type].add(handler);return add.call(this,type,handler,...args);};
   owner.removeEventListener=function(type,handler,...args){if(names.includes(type))listeners[type].delete(handler);return remove.call(this,type,handler,...args);};
   originals.push(()=>{owner.addEventListener=add;owner.removeEventListener=remove;});
  }
  let artworkWidth=160;
  const getRect=HTMLElement.prototype.getBoundingClientRect;
  HTMLElement.prototype.getBoundingClientRect=function(){return this.classList.contains('artwork')?{width:artworkWidth,height:artworkWidth,top:0,left:0,right:artworkWidth,bottom:artworkWidth,x:0,y:0,toJSON(){}}:getRect.call(this);};
  Object.defineProperty(window,'devicePixelRatio',{configurable:true,value:1});
  const target=document.createElement('div');document.body.append(target);let app;
  const counts=()=>[resize.size,intersection.size,...Object.values(listeners).map(set=>set.size)];
  try {
   app=mount(Fixture,{target});await settle();
   const media=()=>target.querySelector('.artwork img'),track=()=>target.querySelector('.track-artwork img');
   assert.deepEqual(counts(),[1,1,1,1,1,1]);
   const mediaSource=media().getAttribute('src'),trackSource=track().getAttribute('src');
   app.cover(true);await settle();assert.deepEqual(counts(),[0,0,0,0,0,0]);
   assert.ok(target.querySelector('.artwork'),'coverage retains visual DOM');
   artworkWidth=240;Object.defineProperty(window,'devicePixelRatio',{configurable:true,value:2});
   window.dispatchEvent(new dom.Event('resize'));await settle();
   assert.equal(media().getAttribute('src'),mediaSource);assert.equal(track().getAttribute('src'),trackSource);
   app.cover(false);await settle();assert.deepEqual(counts(),[1,1,1,1,1,1]);
   assert.match(media().getAttribute('src'),/=w512-h512/);assert.match(track().getAttribute('src'),/=w96-h96/);
   for(let i=0;i<10;i++){
    app.select(false);await settle();assert.deepEqual(counts(),[0,0,0,0,0,0]);
    app.select(true);await settle();assert.deepEqual(counts(),[1,1,1,1,1,1]);
   }
   const oldMedia=media(),oldTrack=track();app.replace();await settle();
   const newMedia=media().getAttribute('src'),newTrack=track().getAttribute('src');
   oldMedia.dispatchEvent(new dom.Event('error'));oldTrack.dispatchEvent(new dom.Event('error'));await settle();
   assert.equal(media().getAttribute('src'),newMedia);assert.equal(track().getAttribute('src'),newTrack);
   assert.match(newMedia,/replacement/);assert.match(newTrack,/replacement/);
   media().dispatchEvent(new dom.Event('error'));track().dispatchEvent(new dom.Event('error'));await settle();
   assert.match(media().getAttribute('src'),/replacement=w120-h120/);
   assert.match(track().getAttribute('src'),/replacement=w120-h120/);
  } finally {
   if(app)await unmount(app);target.remove();assert.deepEqual(counts(),[0,0,0,0,0,0]);
   for(const restore of originals)restore();HTMLElement.prototype.getBoundingClientRect=getRect;
  }
 });
}

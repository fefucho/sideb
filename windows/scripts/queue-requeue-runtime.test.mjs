import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if(!process.execArgv.includes('--conditions=browser')) {
 test('dragging previous/current/pending rows reaches authoritative placement with correct IDs and focus',()=>{
  const {NODE_TEST_CONTEXT,...env}=process.env;
  const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
  assert.equal(result.status,0,result.stdout+result.stderr);
 });
} else {
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('queue-requeue-runtime');
 Object.defineProperty(HTMLElement.prototype,'clientHeight',{configurable:true,get:()=>480});
 const Fixture=(await import(await moduleFor(path.join(root,'scripts/fixtures/QueueRequeueFixture.svelte'),`<script>
 import QueuePanel from '$lib/components/fullscreen/QueuePanel.svelte';
 const entry=id=>({entryId:id,videoId:id,title:id,artists:'Artist',duration:180});
 const seed=radio=>({generation:7,position:123,isPlaying:true,isLoading:false,currentTrack:entry('current'),queue:{items:(radio?['current']:['old','current','next','last']).map(entry),currentIndex:radio?0:1,source:{kind:radio?'radio':'playlist',id:'fixture',title:'Fixture'},recommendations:[entry('radio')]}});
 let playback=$state(seed(false));let calls=[];let radio=false;
 export function reset(value=false){radio=value;playback=seed(value);calls=[];}
 export function viewState(){return {calls,active:playback.currentTrack.entryId,generation:playback.generation,position:playback.position,ids:playback.queue.items.map(x=>x.entryId)}};
 function place(id,before){calls.push([id,before]);
  // Predetermined RPC responses exercise UI delivery/focus, not a second queue model.
  if(id==='old')playback={...playback,queue:{...playback.queue,items:['old','current','copy-old','next','last'].map(entry)}};
  else if(id==='current')playback={...playback,queue:{...playback.queue,items:(radio?['current','copy-current']:['old','current','copy-current','next','last']).map(entry)}};
  return playback;
 }
 const noop=()=>{};
 </script><QueuePanel {playback} onSelectQueue={noop} onMoveQueue={place}/>`))).default;
 const settle=async()=>{flushSync();await tick();await new Promise(r=>dom.requestAnimationFrame(r));flushSync();await tick();};
 const transfer=()=>({effectAllowed:'none',dropEffect:'none',setData(){},setDragImage(){}});
 function event(type,data,y=0){const e=new dom.Event(type,{bubbles:true,cancelable:true});Object.defineProperties(e,{dataTransfer:{value:data},clientY:{value:y}});return e;}
 test('all committed rows drag; earlier/current repeat requests preserve audio and focus follows admitted occurrence',async()=>{
  const target=document.createElement('div');document.body.append(target);const app=mount(Fixture,{target});
  const row=id=>target.querySelector('[data-entry-id="'+id+'"]');
  const start=id=>{const data=transfer();const grip=row(id).querySelector('.reorder-handle');assert.ok(grip,'drag handle '+id);grip.dispatchEvent(event('dragstart',data));return data;};
  const drop=async(source,destination,y)=>{const data=start(source),node=row(destination);node.getBoundingClientRect=()=>({top:0,height:46,bottom:46});const over=event('dragover',data,y);node.dispatchEvent(over);node.dispatchEvent(event('drop',data,y));await settle();return {over,data};};
  try {
   await settle();const previous=await drop('old','next',5);assert.equal(previous.over.defaultPrevented,true);assert.equal(previous.data.dropEffect,'copy');
   assert.deepEqual(app.viewState().calls,[['old','next']]);assert.equal(document.activeElement.closest('[data-entry-id]').dataset.entryId,'copy-old');
   assert.equal(app.viewState().active,'current');assert.equal(app.viewState().generation,7);assert.equal(app.viewState().position,123);assert.ok(app.viewState().ids.includes('old'));
   app.reset();await settle();await drop('current','current',40);assert.deepEqual(app.viewState().calls,[['current','next']],'after current must not be suppressed as a no-op');assert.equal(document.activeElement.closest('[data-entry-id]').dataset.entryId,'copy-current');
   app.reset();await settle();const pending=await drop('last','next',5);assert.equal(pending.data.dropEffect,'move');assert.deepEqual(app.viewState().calls,[['last','next']]);
   app.reset();await settle();const invalid=await drop('current','old',5);assert.equal(invalid.over.defaultPrevented,false);assert.deepEqual(app.viewState().calls,[]);
   app.reset(true);await settle();const data=start('current'),divider=target.querySelector('[data-queue-section="recommendations"]');assert.ok(divider);divider.dispatchEvent(event('dragover',data));divider.dispatchEvent(event('drop',data));await settle();assert.deepEqual(app.viewState().calls,[['current',null]]);assert.deepEqual(app.viewState().ids,['current','copy-current']);assert.equal(app.viewState().active,'current');
  } finally {await unmount(app);target.remove();}
 });
}

import assert from 'node:assert/strict';
import {test} from 'node:test';
import path from 'node:path';
import {mountedSvelteEnvironment} from './helpers/mount-svelte.mjs';

const {root,moduleFor,dom}=await mountedSvelteEnvironment('artist-profile');
const lib=file=>path.join(root,'src/lib',file);
const shelf=await import(await moduleFor(lib('detail/artistShelf.ts')));
const {installNavigationGestures}=await import(await moduleFor(lib('navigation/gestures.ts')));
const {ARTIST_CARD_STRIDE:S,ARTIST_SHELF_INSET:INSET,ARTIST_CARD_OVERSCAN:OVER}=shelf;

test('empty provider sections never render and keep their order',()=>{
 const sections=[{title:'A',items:[1]},{title:'Empty',items:[]},{title:'B',items:[2,3]}];
 assert.deepEqual(shelf.artistShelves(sections).map(item=>item.title),['A','B']);
 const key=shelf.artistShelfKey({title:'A',items:[],moreBrowseId:'MPRE',moreParams:null},3);
 assert.equal(key,'3:A:MPRE:');
});

test('shelf window mounts only visible cards plus overscan and preserves the full scroll extent',()=>{
 for(const count of [1,5,120,5000]) for(const [left,viewport] of [[0,1000],[2400,1000],[1e9,1000],[0,320],[777,1400]]) {
  const window=shelf.artistShelfWindow(count,left,viewport);
  const full=INSET*2+count*S-16;
  assert.equal(window.width,full);
  assert.ok(window.start>=0&&window.end<=count&&window.start<=window.end);
  const rendered=window.end-window.start;
  if(rendered)assert.equal(window.before+rendered*S-16+window.after+INSET*2,full,'spacers + rendered cards equal the unvirtualized width');
  assert.ok(rendered<=Math.ceil(viewport/S)+2*OVER+2,`mounted ${rendered} cards for viewport ${viewport}`);
  const maximum=Math.max(0,full-viewport),offset=Math.min(left,maximum);
  const firstVisible=Math.max(0,Math.floor((offset-INSET)/S)),lastVisible=Math.min(count-1,Math.floor((offset+viewport-INSET)/S));
  assert.ok(window.start<=firstVisible&&window.end>lastVisible,'every visible card is mounted');
 }
 assert.deepEqual(shelf.artistShelfWindow(0,0,1000),{start:0,end:0,before:0,after:0,width:0});
});

test('RTL shelves use logical offsets (negative scrollLeft)',()=>{
 const forward=shelf.artistShelfWindow(500,1600,1000,false),rtl=shelf.artistShelfWindow(500,-1600,1000,true);
 assert.deepEqual(rtl,forward);
});

test('shelf height is one fixed value so recycled rows never remeasure',()=>{
 assert.equal(shelf.artistShelfHeight(),30+14+shelf.ARTIST_CARD_HEIGHT+8+32);
});

function gestureHarness() {
 globalThis.document.body.innerHTML='';
 const commits=[];
 const handle=installNavigationGestures(dom,{context:()=>({revision:'artist',enabled:true,blocked:false,fullscreen:false,reduceMotion:true,height:700,backTitle:'Back',forwardTitle:null}),progress:()=>{},commit:action=>commits.push(action)});
 dom.document.body.innerHTML='<main><header id="head"><p id="plain">Artist</p></header><section><div id="shelf" data-horizontal-scroll data-gesture-local><div><button id="card">Card</button><span id="label">Card text</span></div></div></section></main>';
 // happy-dom's WheelEvent drops modifier keys, so carry the fields the adapter reads on a plain event.
 const make=(deltaX,deltaY,altKey)=>Object.assign(new dom.Event('wheel',{bubbles:true,cancelable:true}),{deltaX,deltaY,deltaMode:0,altKey,ctrlKey:false});
 const wheel=(target,deltaX,deltaY=0,altKey=true)=>{const event=make(deltaX,deltaY,altKey);target.dispatchEvent(event);return event;};
 const quiet=()=>new Promise(resolve=>setTimeout(resolve,230));
 return {dom,commits,wheel,make,quiet,release:()=>dom.dispatchEvent(new dom.KeyboardEvent('keyup',{key:'Alt'})),dispose(){handle.dispose();globalThis.document.body.innerHTML='';}};
}

test('ordinary wheel never navigates, over the page or over an artist shelf',async()=>{
 const h=gestureHarness();
 try {
  for(const id of ['plain','label','card','shelf'])for(const [x,y] of [[200,0],[0,200],[-200,0],[80,80]]){h.wheel(h.dom.document.getElementById(id),x,y,false);}
  await h.quiet();h.release();
  assert.deepEqual(h.commits,[]);
 } finally {h.dispose();}
});

test('Alt + horizontal wheel is the explicit history gesture outside a shelf, but stays local over one',async()=>{
 const h=gestureHarness();
 try {
  const shelfCard=h.dom.document.getElementById('label'),plain=h.dom.document.getElementById('plain');
  const event=h.wheel(shelfCard,200);
  assert.equal(event.defaultPrevented,false,'the shelf keeps its native horizontal scrolling');
  await h.quiet();h.release();
  assert.deepEqual(h.commits,[],'no history action from a gesture that began on a shelf');
  for(let i=0;i<3;i++)h.wheel(plain,40);
  await h.quiet();h.release();
  assert.deepEqual(h.commits,['back'],'outside shelves the explicit Alt gesture remains available');
 } finally {h.dispose();}
});

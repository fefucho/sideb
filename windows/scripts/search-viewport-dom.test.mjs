import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if(!process.execArgv.includes('--conditions=browser')){
 test('mounted search retains a bounded viewport, occurrence actions, anchors, menus and suspension',()=>{
  const {NODE_TEST_CONTEXT,...env}=process.env;
  const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
  assert.equal(result.status,0,result.stdout+result.stderr);
 });
}else{
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('search-viewport-dom');
 const Fixture=(await import(await moduleFor(path.join(root,'scripts/fixtures/SearchParity.svelte')))).default;
 const observers=new Set();
 Object.defineProperty(globalThis,'ResizeObserver',{configurable:true,value:class{constructor(callback){this.callback=callback;this.nodes=new Set();observers.add(this);}observe(node){this.nodes.add(node);}unobserve(node){this.nodes.delete(node);}disconnect(){this.nodes.clear();observers.delete(this);}}});
 globalThis.IntersectionObserver=class{observe(){}disconnect(){}};
 const heights=new Map();
 Object.defineProperty(dom.HTMLElement.prototype,'clientHeight',{configurable:true,get(){return this.classList.contains('results-scroll')?600:0;}});
 Object.defineProperty(dom.HTMLElement.prototype,'clientWidth',{configurable:true,get(){return 1000;}});
 Object.defineProperty(dom.HTMLElement.prototype,'offsetParent',{configurable:true,get(){return this.parentElement;}});
 dom.HTMLElement.prototype.getBoundingClientRect=function(){
  const isRoot=this.classList.contains('results-scroll'),isViewport=this.classList.contains('search-viewport');
  const height=this.dataset.searchEntry?(heights.get(this.dataset.searchEntry)??(this.querySelector('.principal')?140:this.querySelector('.section-heading')?44:58)):isRoot?600:0;
  const top=isViewport?-(this.closest('.results-scroll')?.scrollTop??0):0;
  return {x:0,y:top,top,left:0,bottom:top+height,right:1000,width:1000,height,toJSON(){}};
 };
 async function settle(){flushSync();await tick();await new Promise(resolve=>setTimeout(resolve,25));flushSync();await tick();}
 function resize(node){for(const observer of [...observers])if(observer.nodes.has(node))observer.callback([{target:node,borderBoxSize:[{blockSize:node.getBoundingClientRect().height}]}]);}
 test('5000 results mount a bounded range; row4500 dispatches its exact duplicate occurrence',async()=>{
  const host=document.createElement('div');document.body.append(host);const calls=[];
  let app;flushSync(()=>app=mount(Fixture,{target:host,props:{onCall:(...args)=>calls.push(args)},intro:false}));await settle();
  const scroll=host.querySelector('.results-scroll'),viewport=host.querySelector('.search-viewport');
  let maximum=host.querySelectorAll('.search-entry').length;
  assert.ok(maximum<40);assert.equal(host.querySelectorAll('h2').length,1,'principal does not duplicate its section title');
  const primary=host.querySelector('.principal .play');primary.focus();primary.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true,cancelable:true}));await settle();
  assert.equal(document.activeElement.closest('[data-search-entry]').dataset.searchEntry,'section:1:list-0:song:0','ArrowDown skips a heading without primary controls');
  document.activeElement.blur();await settle();
  scroll.scrollTop=140+44+4500*58;scroll.dispatchEvent(new Event('scroll'));await settle();
  maximum=Math.max(maximum,host.querySelectorAll('.search-entry').length);
  const row=host.querySelector('[data-search-entry="section:1:list-0:song:4500"]');assert.ok(row);
  row.querySelector('.play').click();flushSync();assert.equal(calls.at(-1)[0],'play');assert.equal(calls.at(-1)[1].setVideoId,'occurrence-4500');
  const prior=scroll.scrollTop;
  host.querySelector('[data-append]').click();await settle();assert.equal(scroll.scrollTop,prior);assert.ok(host.querySelector('[data-search-entry="section:1:list-0:song:4500"]'));
  row.querySelector('.play').focus();flushSync();
  scroll.scrollTop=140+44+4800*58;scroll.dispatchEvent(new Event('scroll'));await settle();assert.ok(host.contains(row),'focused row stays mounted outside overscan');
  row.querySelector('.more').click();await settle();assert.ok(document.querySelector('[role="menu"]'));
  document.querySelector('[role="menuitem"]').focus();await settle();
  scroll.scrollTop=140+44+100*58;scroll.dispatchEvent(new Event('scroll'));await settle();assert.ok(host.contains(row),'menu owner stays mounted');
  document.querySelector('[role="menuitem"]').click();await settle();assert.ok(!host.contains(row),'unpinned row recycles after menu closes');
  for(const gesture of [{key:'ContextMenu'},{key:'F10',shiftKey:true}]){
   const owner=host.querySelector('[data-search-entry*="song:"]'),play=owner.querySelector('.play');play.focus();
   const event=new KeyboardEvent('keydown',{...gesture,bubbles:true,cancelable:true});play.dispatchEvent(event);await settle();assert.equal(event.defaultPrevented,true);
   document.querySelector('[role="menuitem"]').focus();await settle();
   scroll.scrollTop=140+44+4800*58;scroll.dispatchEvent(new Event('scroll'));await settle();assert.ok(host.contains(owner),'keyboard popup keeps its original owner mounted after focus moves');
   document.querySelector('[role="menuitem"]').click();await settle();assert.ok(!host.contains(owner),'closing keyboard popup releases owner');
   scroll.scrollTop=140+44+100*58;scroll.dispatchEvent(new Event('scroll'));await settle();
  }
  host.querySelector('[data-document]').click();await settle();assert.equal(scroll.scrollTop,0,'new query/filter document starts at the top');
  assert.ok(host.textContent.includes('Resultado 10000'));
  maximum=Math.max(maximum,host.querySelectorAll('.search-entry').length);assert.ok(maximum<40);console.log(`Search 5000: maximum mounted entries ${maximum}`);
  await unmount(app);host.remove();
 });
 test('early measurements compensate the anchor and inactive retained page stops scroll and playback updates',async()=>{
  const host=document.createElement('div');document.body.append(host);let app;
  flushSync(()=>app=mount(Fixture,{target:host,props:{},intro:false}));await settle();
  const scroll=host.querySelector('.results-scroll');
  Object.defineProperty(scroll,'offsetWidth',{configurable:true,value:1017});resize(scroll);await settle();
  assert.equal(host.querySelector('.search-page').style.getPropertyValue('--search-scrollbar-gutter'),'17px','header shares the results content width when a classic scrollbar consumes space');
  const first=host.querySelector('[data-search-entry="section:1:list-0:song:0"]');first.querySelector('.play').focus();flushSync();
  scroll.scrollTop=140+44+4500*58;scroll.dispatchEvent(new Event('scroll'));await settle();
  const previous=scroll.scrollTop;
  heights.set(first.dataset.searchEntry,210);resize(first);await settle();assert.equal(scroll.scrollTop,previous+152);
  host.querySelector('[data-active]').click();await settle();const keys=[...host.querySelectorAll('[data-search-entry]')].map(node=>node.dataset.searchEntry);
  scroll.scrollTop=0;scroll.dispatchEvent(new Event('scroll'));host.querySelector('[data-playback]').click();await settle();
  assert.deepEqual([...host.querySelectorAll('[data-search-entry]')].map(node=>node.dataset.searchEntry),keys);
  host.querySelector('[data-active]').click();await settle();assert.ok(host.querySelector('[data-search-entry="section:0:top:principal"]'));
  await unmount(app);host.remove();heights.clear();
 });
 test('three text suggestions share mouse/keyboard payloads; outside click passes through and IME never submits',async()=>{
  const host=document.createElement('div');document.body.append(host);const calls=[];let app;
  flushSync(()=>app=mount(Fixture,{target:host,props:{count:20,onCall:(...args)=>calls.push(args)},intro:false}));await settle();
  const input=host.querySelector('input');input.focus();await settle();
  const preview=host.querySelector('.preview-content');assert.equal(preview.querySelectorAll('.query-suggestion').length,3);assert.equal(preview.querySelectorAll('.song-row').length,2);
  input.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true}));flushSync();assert.equal(document.activeElement,preview.querySelector('.query-suggestion'));
  for(let index=0;index<3;index++){document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true}));flushSync();}
  assert.equal(document.activeElement,preview.querySelector('.song-row .play'));document.activeElement.click();flushSync();assert.equal(calls.at(-1)[0],'play');assert.equal(calls.at(-1)[1].setVideoId,'occurrence-0');
  input.focus();await settle();const outside=host.querySelector('[data-outside]');const event=new dom.PointerEvent('pointerdown',{bubbles:true,cancelable:true});outside.dispatchEvent(event);outside.click();await settle();assert.equal(event.defaultPrevented,false);assert.equal(calls.at(-1)[0],'outside');assert.equal(host.querySelector('.preview-popover'),null);assert.equal(input.value,'homecoming');
  input.focus();await settle();input.dispatchEvent(new Event('compositionstart',{bubbles:true}));host.querySelector('.search-form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));assert.ok(!calls.some(call=>call[0]==='submit'));
  input.dispatchEvent(new Event('compositionend',{bubbles:true}));host.querySelector('.search-form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));assert.equal(calls.at(-1)[0],'submit');
  await unmount(app);host.remove();
 });
}

import assert from 'node:assert/strict';import {test} from 'node:test';import {spawnSync} from 'node:child_process';import {fileURLToPath} from 'node:url';import path from 'node:path';
if(!process.execArgv.includes('--conditions=browser')){
 test('Home mosaic mounts a windowed, resettable layout of real song cards',()=>{const {NODE_TEST_CONTEXT,...env}=process.env;const r=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});assert.equal(r.status,0,r.stdout+r.stderr)});
}else{
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('home-mosaic-dom');
 globalThis.IntersectionObserver=class{observe(){}unobserve(){}disconnect(){}};
 Object.defineProperty(globalThis,'ResizeObserver',{configurable:true,value:class{constructor(fn){this.fn=fn}observe(){}unobserve(){}disconnect(){}}});
 Object.defineProperty(dom.HTMLElement.prototype,'clientWidth',{configurable:true,get(){return 600}});
 Object.defineProperty(dom.HTMLElement.prototype,'scrollWidth',{configurable:true,get(){return 6000}});
 const calls=[],scrolls=[];globalThis.__mosaic={calls,scrolls};
 const source=`<script>
  import {setContext} from 'svelte';
  import {MENU_CONTEXT} from '$lib/menu/types';
  import HomeMosaic from '$lib/components/home/HomeMosaic.svelte';
  let songs=$state(globalThis.__songs(0)),offset=$state(0);
  setContext(MENU_CONTEXT,{open:(_event,target)=>globalThis.__mosaic.calls.push(['menu',target.kind])});
  globalThis.__harness={songs:v=>songs=globalThis.__songs(v),offset:()=>offset};
</script><HomeMosaic {songs} session="s1" {offset} onScroll={o=>{offset=o;globalThis.__mosaic.scrolls.push(o)}} onPlaySong={item=>globalThis.__mosaic.calls.push(['play',item.id])} />`;
 globalThis.__songs=variant=>Array.from({length:27},(_,i)=>({kind:'song',id:`v${variant}-song${i}`,title:`Title ${variant}-${i}`,subtitle:null,thumbnail:null,duration:null,artists:`Artist ${i}`,albumId:null,artistId:null,album:null,artistRuns:[],explicit:false}));
 const Harness=(await import(await moduleFor(path.join(root,'src/lib/components/home/MosaicHarness.svelte'),source))).default;
 const settle=async()=>{flushSync();await tick();await new Promise(r=>setTimeout(r,45));flushSync();await tick()};
 const signature=target=>[...target.querySelectorAll('.cell')].map(c=>c.getAttribute('style')).join('|');
 const lefts=target=>[...target.querySelectorAll('.cell')].map(c=>parseInt(c.style.left));
 test('large first card, windowed mounting, actions, text and layout reset',async()=>{
  const target=document.createElement('div');document.body.append(target);let app;flushSync(()=>app=mount(Harness,{target}));await settle();
  const heading=target.querySelector('h2');assert.ok(heading.textContent.trim().length>0);assert.equal(target.querySelector('[data-horizontal-scroll]').getAttribute('role'),'region');
  const first=target.querySelector('.cell');assert.match(first.getAttribute('style'),/left: 0px; top: 0px; width: 296px; height: 296px/);
  assert.ok(first.querySelector('article.media-card.mosaic.large'));
  const all=target.querySelectorAll('.cell').length;assert.ok(all>0&&all<27,'only nearby cells are mounted');
  const scroller=target.querySelector('[data-horizontal-scroll]');
  assert.ok(Math.max(...lefts(target))<6*152,'cells beyond the window margin are not mounted');
  assert.ok(target.querySelector('.space').getAttribute('style').match(/width: ?\d+px/));
  const card=first.querySelector('article');assert.match(card.textContent,/Title 0-0/);assert.match(card.textContent,/Artist 0/);
  first.querySelector('button.primary').click();assert.deepEqual(calls.at(-1),['play','v0-song0']);
  card.dispatchEvent(new dom.MouseEvent('contextmenu',{bubbles:true,cancelable:true}));assert.deepEqual(calls.at(-1),['menu','song']);
  calls.length=0;const menu=first.querySelector('button.menu');assert.ok(menu.getAttribute('aria-label').includes('Title 0-0'));menu.click();assert.deepEqual(calls.at(-1),['menu','song']);
  const before=signature(target),firstBefore=target.querySelector('article').getAttribute('aria-label');
  scroller.scrollLeft=1500;scroller.dispatchEvent(new dom.Event('scroll'));await settle();
  assert.equal(globalThis.__harness.offset(),1500);assert.notEqual(target.querySelector('article').getAttribute('aria-label'),firstBefore,'scrolling swaps the mounted cells');
  assert.ok(Math.min(...lefts(target))>=1500-5*152&&Math.max(...lefts(target))<1500+600+3*152);
  const farLayout=signature(target);assert.notEqual(farLayout,before);
  globalThis.__harness.songs(1);await settle();
  assert.equal(scroller.scrollLeft,0,'a new list returns to the start');assert.equal(globalThis.__harness.offset(),0);
  assert.equal(target.querySelector('article').getAttribute('aria-label'),'Title 1-0');
  assert.notEqual(signature(target),before,'a new list of IDs draws a new layout');
  globalThis.__harness.songs(0);await settle();assert.equal(signature(target),before,'the same IDs draw the same layout');
  await unmount(app);target.remove();
 });
}

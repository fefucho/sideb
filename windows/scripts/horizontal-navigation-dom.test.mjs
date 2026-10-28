import assert from 'node:assert/strict';import {test} from 'node:test';import {spawnSync} from 'node:child_process';import {fileURLToPath} from 'node:url';import path from 'node:path';
if(!process.execArgv.includes('--conditions=browser')){
 test('horizontal controls navigate real mounted content, retain focus and suspend observers',()=>{const {NODE_TEST_CONTEXT,...env}=process.env;const r=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});assert.equal(r.status,0,r.stdout+r.stderr)});
}else{
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('horizontal-navigation-dom');
 const observers=new Set(),moves=[];let width=600,total=2000,commit=true,background=0;
 Object.defineProperty(globalThis,'ResizeObserver',{configurable:true,value:class{constructor(fn){this.fn=fn;observers.add(this)}observe(){}unobserve(){}disconnect(){observers.delete(this)}}});
 Object.defineProperty(dom.HTMLElement.prototype,'clientWidth',{configurable:true,get(){return this.hasAttribute('data-horizontal-scroll')?width:width}});
 Object.defineProperty(dom.HTMLElement.prototype,'scrollWidth',{configurable:true,get(){return total}});
 dom.HTMLElement.prototype.scrollTo=function(options){moves.push({...options});if(commit){this.scrollLeft=options.left;this.dispatchEvent(new Event('scroll'))}};
 dom.HTMLElement.prototype.getBoundingClientRect=function(){return{x:0,y:0,left:0,right:width,top:0,bottom:100,width,height:100,toJSON(){}}};
 globalThis.__background=()=>background++;
 const source=`<script>import Navigation from './HorizontalNavigation.svelte';let active=$state(true),paged=$state(false),index=$state(0),revision=$state(0);globalThis.__horizontal={active:v=>active=v,paged:v=>paged=v,revise:()=>revision++,index:()=>index};</script><div onclick={globalThis.__background} role="presentation"><Navigation label="Albums" {active} stride={176} {revision} previous={paged?()=>index--:undefined} next={paged?()=>index++:undefined} canPrevious={index>0} canNext={index<2}><div data-horizontal-scroll><button>Play song</button></div></Navigation></div>`;
 const Harness=(await import(await moduleFor(path.join(root,'src/lib/components/common/HorizontalHarness.svelte'),source))).default;
 const settle=async()=>{flushSync();await tick();await new Promise(r=>setTimeout(r,45));flushSync();await tick()};
 test('overflow, repeated smooth clicks, resize, focus, account reset and paged callbacks',async()=>{
   const target=document.createElement('div');document.body.append(target);let app;flushSync(()=>app=mount(Harness,{target}));await settle();
   const scroller=target.querySelector('[data-horizontal-scroll]'),next=target.querySelector('[data-horizontal-arrow="next"]'),prev=target.querySelector('[data-horizontal-arrow="previous"]');
   assert.equal(prev.getAttribute('aria-disabled'),'true');assert.ok(!next.classList.contains('hidden'));assert.equal(observers.size,1);
   next.click();await settle();assert.equal(scroller.scrollLeft,528);assert.equal(background,0);assert.equal(prev.getAttribute('aria-disabled'),'false');
   scroller.querySelector('button').click();assert.equal(background,1,'content keeps its original action');
   scroller.scrollLeft=0;scroller.dispatchEvent(new Event('scrollend'));await settle();moves.length=0;commit=false;
   next.click();next.click();assert.deepEqual(moves.map(m=>m.left),[528,1056],'rapid clicks continue from the requested destination');
   globalThis.__horizontal.revise();await settle();assert.equal(moves.at(-1).behavior,'instant');commit=true;
   total=600;for(const o of observers)o.fn();await settle();assert.equal(next.getAttribute('aria-disabled'),'true');
   moves.length=0;next.click();assert.equal(moves.length,0,'no overflow cannot move');
   total=800;for(const o of observers)o.fn();await settle();next.focus();next.click();await settle();
   assert.equal(scroller.scrollLeft,200);assert.equal(document.activeElement,next);assert.equal(next.getAttribute('aria-disabled'),'true');assert.ok(!next.classList.contains('hidden'),'end reached retains focused control');
   prev.focus();await settle();assert.ok(next.classList.contains('hidden'));
   globalThis.__horizontal.active(false);await settle();assert.equal(observers.size,0);assert.ok(prev.classList.contains('hidden'));
   scroller.scrollLeft=70;globalThis.__horizontal.active(true);await settle();assert.equal(observers.size,1);assert.equal(scroller.scrollLeft,70,'resume does not overwrite retained offset');
   globalThis.__horizontal.paged(true);await settle();assert.equal(observers.size,0,'paged controls have no scroll observers');
   moves.length=0;next.click();await settle();assert.equal(globalThis.__horizontal.index(),1);next.click();await settle();assert.equal(globalThis.__horizontal.index(),2);assert.equal(next.getAttribute('aria-disabled'),'true');prev.click();await settle();assert.equal(globalThis.__horizontal.index(),1);assert.equal(moves.length,0);
   const {setLanguage}=await import(await moduleFor(path.join(root,'src/lib/i18n/index.ts')));setLanguage('en');await settle();assert.equal(next.getAttribute('aria-label'),'Show next items in Albums');
   await unmount(app);target.remove();assert.equal(observers.size,0);
 });
 test('an active virtual catalog disconnects safely when its bound node is removed',async()=>{
   const fixture=`<script>import Catalog from '$lib/components/explore/VirtualCatalog.svelte';const items=Array.from({length:30},(_,i)=>({id:String(i),kind:'album',title:'Album '+i}));</script><Catalog {items} horizontal>{#snippet children(card)}<button>{card.title}</button>{/snippet}</Catalog>`;
   const Catalog=(await import(await moduleFor(path.join(root,'scripts/ActiveCatalogHarness.svelte'),fixture))).default;
   const target=document.createElement('div');document.body.append(target);let app;flushSync(()=>app=mount(Catalog,{target}));await settle();
   assert.equal(observers.size,2);
   await unmount(app);target.remove();assert.equal(observers.size,0);
   window.dispatchEvent(new Event('resize'));await settle();assert.equal(observers.size,0);
 });
 test('leaving a focused search row and immediately removing its viewport is safe',async()=>{
   const fixture=`<script>import Viewport from '$lib/components/search/SearchViewport.svelte';</script><div class="results-scroll"><Viewport items={[{key:'row'}]} documentKey="fixture" estimate={()=>58}>{#snippet children(row)}<button>{row.key}</button>{/snippet}</Viewport></div>`;
   const View=(await import(await moduleFor(path.join(root,'scripts/FocusedSearchViewportHarness.svelte'),fixture))).default;
   const target=document.createElement('div');document.body.append(target);let app;flushSync(()=>app=mount(View,{target}));await settle();
   const button=target.querySelector('button');button.focus();button.blur();await unmount(app);target.remove();await settle();
   assert.equal(observers.size,0);
 });
}

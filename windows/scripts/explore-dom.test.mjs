import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if(!process.execArgv.includes('--conditions=browser')) {
  test('mounted Explore hierarchy, routes, regions and catalog',()=>{
    const {NODE_TEST_CONTEXT,...env}=process.env;
    const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
    assert.equal(result.status,0,result.stdout+result.stderr);
  });
} else {
  const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
  const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('explore-dom-test');
  globalThis.IntersectionObserver=dom.IntersectionObserver;
  const Fixture=(await import(await moduleFor(path.join(root,'scripts/fixtures/ExplorePresentation.svelte'),`<script>
    import ExploreView from '$lib/components/explore/ExploreView.svelte';
    let {initial,onNavigate,onRefresh,onOpenCard,onScrollTop}=$props();
    let data=$state(initial);let active=$state(true);
    export function update(next){data=next;}
    export function activate(value){active=value;}
  </script><ExploreView {data} {active} {onNavigate} {onRefresh} {onOpenCard} {onScrollTop}/>`))).default;
  const i18n=await import(await moduleFor(path.join(root,'src/lib/i18n/index.ts')));
  const card=id=>({kind:'album',id:String(id),title:`Provider title ${id}`,subtitle:'Provider subtitle',thumbnail:null,duration:null});
  const initial=()=>({route:'discover',items:[card(1)],sections:[],countries:[{code:'ZZ'},{code:'UY'},{code:'JP'}],detectedCountry:'UY',regionMessage:null,isLoading:false,error:null,scrollTop:0});
  async function fixture(data=initial()) {
    const host=document.createElement('div');document.body.append(host);
    const navigated=[],offsets=[];let refreshes=0,instance;
    flushSync(()=>instance=mount(Fixture,{target:host,props:{initial:data,onNavigate:route=>navigated.push(route),onOpenCard:()=>{},onRefresh:()=>refreshes++,onScrollTop:offset=>offsets.push(offset)},intro:false}));
    await tick();
    return {host,instance,navigated,offsets,get refreshes(){return refreshes;},update:async next=>{flushSync(()=>instance.update(next));await tick();},dispose:async()=>{await unmount(instance);host.remove();}};
  }
  test('every route scrolls heading then chips with its real localized title',async()=>{
    const f=await fixture();
    for(const route of ['discover','releases','charts','genres','moods','category:focus','country:UY']) {
      await f.update({...initial(),route});
      const scroll=f.host.querySelector('.explore-scroll'),heading=f.host.querySelector('h1'),nav=f.host.querySelector('nav');
      const expected=route==='discover'?i18n.text('navigation.explore'):route==='category:focus'?i18n.text('explore.category.focus.title'):route==='country:UY'?i18n.text('explore.route.chart_country',['Uruguay']):i18n.text(`explore.route.${route}`);
      assert.equal(heading.textContent,expected);assert.equal(f.host.querySelector('header').textContent,expected);
      assert.equal(heading.closest('.explore-scroll'),scroll);assert.equal(nav.parentElement,scroll);
      assert.ok(heading.compareDocumentPosition(nav)&dom.Node.DOCUMENT_POSITION_FOLLOWING);
      assert.equal(nav.querySelectorAll('[aria-pressed="true"]').length,1);
    }
    i18n.setLanguage('en');flushSync();await f.update(initial());assert.equal(f.host.querySelector('h1').textContent,'Explore');
    assert.match(f.host.textContent,/Provider title 1/);assert.match(f.host.textContent,/Provider subtitle/);
    i18n.setLanguage('es');flushSync();await f.dispose();
  });
  test('shortcuts, categories, country selector, loading and retries preserve actions',async()=>{
    const f=await fixture();const shortcuts=[...f.host.querySelectorAll('.shortcuts button')];
    assert.deepEqual(shortcuts.map(button=>button.querySelector('strong').textContent),['Lanzamientos','Rankings']);
    for(const button of shortcuts){assert.ok(button.querySelector('svg[aria-hidden="true"]'));assert.ok(button.querySelector('.shortcut-copy span').textContent);button.click();}
    f.host.querySelector('.categories button').click();assert.deepEqual(f.navigated.slice(0,2),['releases','charts']);assert.match(f.navigated[2],/^category:/);
    await f.update({...initial(),route:'charts',sections:[{code:'ZZ',items:[card(7)],error:null},{code:'UY',items:[card(8)],error:null}]});
    const select=f.host.querySelector('select');assert.deepEqual([...select.options].map(option=>option.value),['charts','country:ZZ','country:UY','country:JP']);
    select.value='country:JP';select.dispatchEvent(new dom.Event('change',{bubbles:true}));assert.equal(f.navigated.at(-1),'country:JP');
    f.host.querySelector('nav button[aria-label]').click();assert.equal(f.refreshes,1);
    await f.update({...initial(),route:'releases',isLoading:true});assert.equal(f.host.querySelector('nav button[aria-label]').disabled,true);
    await f.update({...initial(),route:'releases',error:'explore.error.load_music',items:[]});f.host.querySelector('[role="alert"] button').click();assert.equal(f.refreshes,2);
    await f.dispose();
  });
  test('restores route offsets and recycles a large catalog toward the scroll destination',async()=>{
    const items=Array.from({length:5000},(_,index)=>card(index));const f=await fixture({...initial(),route:'releases',items,scrollTop:520});
    const scroll=f.host.querySelector('.explore-scroll'),catalog=f.host.querySelector('.viewport');
    assert.equal(scroll.scrollTop,520);assert.ok(f.host.querySelectorAll('.media-card').length<40);
    // Simulated layout tests viewport consumption; it does not certify CSS/DPI/WebView2 geometry.
    Object.defineProperty(catalog,'clientWidth',{configurable:true,value:730});Object.defineProperty(scroll,'clientHeight',{configurable:true,value:600});
    scroll.getBoundingClientRect=()=>({top:0});catalog.getBoundingClientRect=()=>({top:200-scroll.scrollTop});
    scroll.scrollTop=74000;scroll.dispatchEvent(new dom.Event('scroll'));flushSync();
    assert.equal(f.offsets.at(-1),74000);assert.ok(f.host.querySelectorAll('.media-card').length<40);
    assert.ok(Number(f.host.querySelector('.media-card').getAttribute('aria-label').split(' ').at(-1))>1000);
    await f.update({...initial(),route:'genres'});assert.equal(scroll.scrollTop,0);
    await f.update({...initial(),route:'releases',items,scrollTop:520});assert.equal(scroll.scrollTop,520);
    flushSync(()=>f.instance.activate(false));scroll.scrollTop=900;scroll.dispatchEvent(new dom.Event('scroll'));assert.equal(f.offsets.at(-1),74000);
    await f.dispose();
  });
}

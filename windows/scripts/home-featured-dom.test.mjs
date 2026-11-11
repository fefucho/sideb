import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if(!process.execArgv.includes('--conditions=browser')) {
  test('Home mounts the Speed Dial mosaic and the collection row with viewport metadata, a View all sheet and retained anchors',()=>{
    const {NODE_TEST_CONTEXT,...env}=process.env;
    const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
    assert.equal(result.status,0,result.stdout+result.stderr);
  });
} else {
  const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
  const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('home-featured-dom');
  // happy-dom has no layout: Home and its scrollers read these values.
  const observers=new Set();let viewport=800;
  Object.defineProperty(globalThis,'ResizeObserver',{configurable:true,value:class{constructor(fn){this.fn=fn;}observe(){observers.add(this)}unobserve(){}disconnect(){observers.delete(this)}}});
  globalThis.IntersectionObserver=class{observe(){}disconnect(){}};
  Object.defineProperty(dom.HTMLElement.prototype,'clientWidth',{configurable:true,get(){return this.hasAttribute('data-featured-rail')||this.hasAttribute('data-horizontal-scroll')?viewport:viewport}});
  Object.defineProperty(dom.HTMLElement.prototype,'clientHeight',{configurable:true,get(){return 520}});
  Object.defineProperty(dom.HTMLElement.prototype,'scrollWidth',{configurable:true,get(){if(this.classList.contains('collection-row'))return 56+[...this.children].reduce((sum,card)=>sum+Number.parseFloat(card.style.width)+24,-24);const space=this.firstElementChild;return Number.parseFloat(space?.style?.width)||viewport}});
  dom.HTMLElement.prototype.scrollTo=function(options){this.scrollLeft=options.left;this.dispatchEvent(new Event('scroll'))};
  dom.HTMLElement.prototype.getBoundingClientRect=function(){return{x:0,y:0,left:0,right:viewport,top:0,bottom:100,width:viewport,height:100,toJSON(){}}};
  const settle=async()=>{flushSync();await tick();await new Promise(r=>setTimeout(r,60));flushSync();await tick();};
  const resize=async width=>{viewport=width;for(const o of [...observers])o.fn([{contentRect:{width}}]);await settle();};
  const Home=(await import(await moduleFor(path.join(root,'src/lib/components/home/HomeView.svelte')))).default;
  const {defaults}=await import(await moduleFor(path.join(root,'src/lib/home/settings.ts')));
  const {setLanguage}=await import(await moduleFor(path.join(root,'src/lib/i18n/index.ts')));
  setLanguage('es');
  const cover='data:image/gif;base64,R0lGODlhAQABAAAAACw=';
  const item=(kind,i)=>({kind,id:`${kind}-${i}`,title:`${kind} ${i}`,subtitle:null,thumbnail:cover,duration:null,artists:'Artista',artistId:'UCartist',album:null,albumId:null,artistRuns:[],explicit:false});
  const sections=[
    {title:'Quick picks',format:'compactSongs',items:Array.from({length:30},(_,i)=>item('song',i)),moreBrowseId:null,moreParams:null},
    {title:'Albums for you',format:'largeCards',items:Array.from({length:40},(_,i)=>item('album',i)),moreBrowseId:null,moreParams:null},
  ];
  const mountHome=async(extra={},Component=Home)=>{
    const host=document.createElement('div');document.body.append(host);
    const calls={visible:[],album:[],artist:[],capacity:[],play:[]};
    const base={chips:[],sections,selectedChipParams:null,isLoading:false,error:null,onSelectChip(){},onRetry(){},hasMore:false,isLoadingMore:false,moreError:null,moreNotice:null,onLoadMore(){},
      auth:{state:'ready',name:'Fixture',thumbnail:null},session:'s1',settings:defaults(),kind:'albums',albums:[],playlists:[],history:[],onSettings(){},onKind(){},interactive:true,libraryError:null,
      onRetryLibrary(){},metadata:{},onVisibleCollections:items=>calls.visible.push(items.map(i=>i.id)),onCapacity:v=>calls.capacity.push(v),
      onOpenAlbum:id=>calls.album.push(id),onOpenArtist:id=>calls.artist.push(id),onPlaySong:s=>calls.play.push(s.id),...extra};
    const props=Component===Home?base:{base};
    let app;flushSync(()=>app=mount(Component,{target:host,props,intro:false}));await settle();
    return {host,calls,dispose:async()=>{await unmount(app);host.remove();}};
  };
  const rails=host=>({songs:host.querySelector('.mosaic .track'),collections:host.querySelector('.collection-row')});

  test('Speed Dial is a recycled mosaic and the albums a panel row sized by collectionRowLayout; the row reports its capacity',async()=>{
    viewport=800;const f=await mountHome();
    const {songs,collections}=rails(f.host);
    assert.ok(songs&&collections,'mosaic and collection row exist');
    assert.equal(f.host.querySelector('[data-featured-rail]'),null,'Home no longer mounts FeaturedRail');
    // 800px: (800-56+24)/224 = 3 cards of 232px; capacity 3 -> 18 collections.
    assert.deepEqual(f.calls.capacity.slice(-1),[3]);
    assert.equal(collections.querySelectorAll('.item article.media-card.panel').length,18);
    assert.ok(collections.querySelector('.item').getAttribute('style').includes('232px'));
    assert.ok(f.host.querySelectorAll('.mosaic article.media-card.mosaic').length>0,'some mosaic cells are mounted');
    assert.ok(f.host.querySelectorAll('.mosaic article.media-card.mosaic').length<30,'the mosaic recycles by viewport');
    await f.dispose();
  });

  test('resizing changes capacity and card width; metadata asks for the whole row with the visible cards first',async()=>{
    viewport=800;const f=await mountHome();
    const widths=()=>[...new Set([...f.host.querySelectorAll('.collection-row .item')].map(card=>card.style.width))];
    assert.deepEqual(widths(),['232px']);
    assert.equal(f.calls.visible.at(-1).length,18,'all 18 collections are requested');
    assert.deepEqual(f.calls.visible.at(-1).slice(0,3),['album-0','album-1','album-2'],'cards inside the 28px insets go first');
    await resize(1600);
    assert.deepEqual(f.calls.capacity.slice(-1),[5]);
    assert.equal(f.host.querySelectorAll('.collection-row .item').length,30);
    assert.deepEqual(widths(),['289.6px']);
    await f.dispose();
  });

  test('scrolling the row moves the visible metadata ids; arrows exist only where content is out of view',async()=>{
    viewport=800;const f=await mountHome();
    const {collections}=rails(f.host);
    const host=collections.closest('.horizontal-navigation');
    assert.ok(!host.classList.contains('leading'),'nothing before the first card');assert.ok(host.classList.contains('trailing'));
    assert.equal(host.querySelector('[data-horizontal-arrow=previous]').classList.contains('hidden'),true);
    collections.scrollLeft=3000;collections.dispatchEvent(new Event('scroll'));await settle();
    assert.ok(host.classList.contains('leading'));
    const ids=f.calls.visible.at(-1);assert.equal(ids.length,18);assert.equal(ids[0],'album-11',JSON.stringify(ids));
    await f.dispose();
  });

  test('View all lists every featured collection with the card actions, reports its own viewport and returns focus',async()=>{
    viewport=800;const f=await mountHome();
    const open=[...f.host.querySelectorAll('button')].find(b=>b.textContent.includes('Ver todo'));
    assert.ok(open,'the collections header has «Ver todo»');open.focus();open.click();await settle();
    const dialog=document.querySelector('[role=dialog][data-featured-sheet]');assert.ok(dialog);
    assert.equal(dialog.querySelector('h2').textContent,'Álbumes');
    assert.equal(dialog.querySelectorAll('.collection-card').length,18);
    assert.equal(dialog.querySelectorAll('.collection-card')[0].style.width,'180px');assert.equal(dialog.querySelectorAll('.collection-card')[0].style.height,'244px');
    // 800px grid: four 180px columns; a 520px viewport shows two rows (the third starts at 520px).
    assert.deepEqual(f.calls.visible.at(-1),Array.from({length:8},(_,i)=>`album-${i}`),'sheet metadata follows its own viewport');
    dialog.querySelector('button.primary,.primary').click();await settle();
    assert.deepEqual(f.calls.album,['album-0']);assert.equal(document.querySelector('[data-featured-sheet]'),null,'opening a card closes the sheet');
    open.click();await settle();document.dispatchEvent(new dom.KeyboardEvent('keydown',{key:'Escape',bubbles:true}));await settle();
    assert.equal(document.querySelector('[data-featured-sheet]'),null);assert.equal(document.activeElement,open);
    await f.dispose();
  });

  // A wrapper keeps the props reactive, as +page.svelte does.
  const Harness=(await import(await moduleFor(path.join(root,'src/lib/components/home/HomeHarness.svelte'),`<script>import Home from './HomeView.svelte';let {base}=$props();let session=$state('s1'),interactive=$state(true),sidebar=$state(false);globalThis.__home={session:v=>session=v,interactive:v=>interactive=v,sidebar:v=>sidebar=v};</script><Home {...base} {session} {interactive} sidebarOpen={sidebar}/>`))).default;
  test('the sidebar flag only toggles the trailing inset; the account switch closes the sheet and each selection keeps its own anchor',async()=>{
    viewport=800;const f=await mountHome({},Harness);
    const home=()=>f.host.querySelector('.home');
    assert.ok(!home().classList.contains('sidebar-open'));
    globalThis.__home.sidebar(true);await settle();assert.ok(home().classList.contains('sidebar-open'));
    globalThis.__home.sidebar(false);await settle();assert.ok(!home().classList.contains('sidebar-open'));
    const collections=()=>rails(f.host).collections;
    collections().scrollLeft=1792;collections().dispatchEvent(new Event('scroll'));await settle();
    // Another account: its row starts at the beginning and the open sheet is gone.
    [...f.host.querySelectorAll('button')].find(b=>b.textContent.includes('Ver todo')).click();await settle();
    assert.ok(document.querySelector('[data-featured-sheet]'));
    globalThis.__home.session('s2');await settle();
    assert.equal(document.querySelector('[data-featured-sheet]'),null,'a different account closes the sheet');
    assert.equal(collections().scrollLeft,0);
    // Back to the first selection: the retained offset returns.
    globalThis.__home.session('s1');await settle();
    assert.equal(collections().scrollLeft,1792);
    await f.dispose();
  });

  test('a covered Home reports no metadata, closes the sheet and returns its row to the retained anchor',async()=>{
    viewport=800;const f=await mountHome({},Harness);
    const collections=()=>rails(f.host).collections;
    collections().scrollLeft=768;collections().dispatchEvent(new Event('scroll'));await settle();
    [...f.host.querySelectorAll('button')].find(b=>b.textContent.includes('Ver todo')).click();await settle();
    globalThis.__home.interactive(false);await settle();
    assert.deepEqual(f.calls.visible.at(-1),[],'nothing is requested while fullscreen covers Home');
    assert.equal(document.querySelector('[data-featured-sheet]'),null);
    // display:none (retained page) resets scrollers; the row must put it back on reveal.
    collections().scrollLeft=0;
    globalThis.__home.interactive(true);await settle();
    assert.equal(collections().scrollLeft,768);
    await f.dispose();
  });
}

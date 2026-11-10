import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if(!process.execArgv.includes('--conditions=browser')) {
  test('Home mounts two continuous rails with fixed-size recycled cards, viewport metadata and a View all sheet',()=>{
    const {NODE_TEST_CONTEXT,...env}=process.env;
    const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
    assert.equal(result.status,0,result.stdout+result.stderr);
  });
} else {
  const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
  const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('home-featured-dom');
  // happy-dom has no layout: the rails read these three values from the scroller.
  const observers=new Set();let viewport=800;
  Object.defineProperty(globalThis,'ResizeObserver',{configurable:true,value:class{constructor(fn){this.fn=fn;}observe(){observers.add(this)}unobserve(){}disconnect(){observers.delete(this)}}});
  globalThis.IntersectionObserver=class{observe(){}disconnect(){}};
  Object.defineProperty(dom.HTMLElement.prototype,'clientWidth',{configurable:true,get(){return this.hasAttribute('data-featured-rail')||this.hasAttribute('data-horizontal-scroll')?viewport:viewport}});
  Object.defineProperty(dom.HTMLElement.prototype,'clientHeight',{configurable:true,get(){return 520}});
  Object.defineProperty(dom.HTMLElement.prototype,'scrollWidth',{configurable:true,get(){const space=this.firstElementChild;return Number.parseFloat(space?.style?.width)||viewport}});
  dom.HTMLElement.prototype.scrollTo=function(options){this.scrollLeft=options.left;this.dispatchEvent(new Event('scroll'))};
  dom.HTMLElement.prototype.getBoundingClientRect=function(){return{x:0,y:0,left:0,right:viewport,top:0,bottom:100,width:viewport,height:100,toJSON(){}}};
  const settle=async()=>{flushSync();await tick();await new Promise(r=>setTimeout(r,60));flushSync();await tick();};
  const resize=async width=>{viewport=width;for(const o of [...observers])o.fn([]);await settle();};
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
  const rails=host=>({songs:host.querySelector('[data-featured-rail]:not([data-featured-rail="Álbumes"])'),collections:host.querySelector('[data-featured-rail="Álbumes"]')});

  test('Speed Dial is a three-row 190x126 rail and albums a one-row 176x240 rail; both recycle by viewport',async()=>{
    viewport=800;const f=await mountHome();
    const {songs,collections}=rails(f.host);
    assert.ok(songs&&collections,'both rails exist');
    assert.deepEqual(f.calls.capacity.slice(-1),[6]);
    const songWindow=songs.querySelector('.window'),collectionWindow=collections.querySelector('.window');
    assert.equal(songWindow.style.gridTemplateRows,'repeat(3,126px)');assert.equal(songWindow.style.gridAutoColumns,'190px');
    assert.equal(collectionWindow.style.gridTemplateRows,'repeat(1,240px)');assert.equal(collectionWindow.style.gridAutoColumns,'176px');
    // 27 songs, 9 columns of 202px: only the columns around an 800px viewport are mounted.
    assert.equal(songs.querySelectorAll('article.media-card.tile').length,15);
    assert.equal(songs.querySelector('.space').style.width,`${9*202-12}px`);
    // 36 albums at 190px: six columns mounted; the pool is the 36-card capacity, not the 40 provided.
    assert.equal(collections.querySelectorAll('.collection-card').length,6);
    assert.equal(collections.querySelector('.space').style.width,`${36*190-14}px`);
    assert.equal(f.host.querySelector('[data-featured]').style.getPropertyValue('--song-height'),'402px');
    await f.dispose();
  });

  test('resizing reveals more cards without changing card size; metadata is requested only for the visible ones',async()=>{
    viewport=800;const f=await mountHome();
    const size=()=>[...f.host.querySelectorAll('.collection-card')].map(card=>`${card.style.width} ${card.style.height}`);
    assert.deepEqual([...new Set(size())],['176px 240px']);
    const before=f.host.querySelectorAll('.collection-card').length;
    const visibleAt800=f.calls.visible.at(-1);
    assert.deepEqual(visibleAt800,['album-0','album-1','album-2','album-3','album-4'],'cards whose bounds intersect 800px minus the 28px inset');
    await resize(1600);
    assert.ok(f.host.querySelectorAll('.collection-card').length>before);
    assert.deepEqual([...new Set(size())],['176px 240px'],'width does not scale cards');
    assert.ok(f.calls.visible.at(-1).length>visibleAt800.length);
    await resize(400);
    assert.deepEqual(f.calls.visible.at(-1),['album-0','album-1']);
    await f.dispose();
  });

  test('scrolling moves the mounted window and the visible metadata ids; arrows exist only where content is out of view',async()=>{
    viewport=800;const f=await mountHome();
    const {collections}=rails(f.host);
    const host=collections.closest('.horizontal-navigation');
    assert.ok(!host.classList.contains('leading'),'nothing before the first card');assert.ok(host.classList.contains('trailing'));
    assert.equal(host.querySelector('[data-horizontal-arrow=previous]').classList.contains('hidden'),true);
    collections.scrollLeft=3000;collections.dispatchEvent(new Event('scroll'));await settle();
    assert.ok(host.classList.contains('leading'));
    const ids=f.calls.visible.at(-1);assert.ok(ids.length>0&&ids.every(id=>Number(id.split('-')[1])>=14),JSON.stringify(ids));
    const mounted=[...collections.querySelectorAll('.collection-card')].map(card=>Number(card.dataset.collectionCard.split('-')[1]));
    assert.ok(Math.min(...mounted)>=13&&Math.max(...mounted)<=22,'old columns were recycled: '+mounted.join());
    await f.dispose();
  });

  test('View all lists every featured collection with the card actions, reports its own viewport and returns focus',async()=>{
    viewport=800;const f=await mountHome();
    const open=[...f.host.querySelectorAll('button')].find(b=>b.textContent.includes('Ver todo'));
    assert.ok(open,'the collections header has «Ver todo»');open.focus();open.click();await settle();
    const dialog=document.querySelector('[role=dialog][data-featured-sheet]');assert.ok(dialog);
    assert.equal(dialog.querySelector('h2').textContent,'Álbumes');
    assert.equal(dialog.querySelectorAll('.collection-card').length,36);
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
  test('the sidebar flag only toggles the trailing inset; the account switch closes the sheet and each selection keeps its own offset',async()=>{
    viewport=800;const f=await mountHome({},Harness);
    const home=()=>f.host.querySelector('.home');
    assert.ok(!home().classList.contains('sidebar-open'));
    globalThis.__home.sidebar(true);await settle();assert.ok(home().classList.contains('sidebar-open'));
    globalThis.__home.sidebar(false);await settle();assert.ok(!home().classList.contains('sidebar-open'));
    const collections=()=>rails(f.host).collections;
    collections().scrollLeft=1900;collections().dispatchEvent(new Event('scroll'));await settle();
    // Another account: its rail starts at the beginning and the open sheet is gone.
    [...f.host.querySelectorAll('button')].find(b=>b.textContent.includes('Ver todo')).click();await settle();
    assert.ok(document.querySelector('[data-featured-sheet]'));
    globalThis.__home.session('s2');await settle();
    assert.equal(document.querySelector('[data-featured-sheet]'),null,'a different account closes the sheet');
    assert.equal(collections().scrollLeft,0);
    // Back to the first selection: the retained offset returns.
    globalThis.__home.session('s1');await settle();
    assert.equal(collections().scrollLeft,1900);
    await f.dispose();
  });

  test('a covered Home reports no metadata, closes the sheet and returns its scroller to the retained offset',async()=>{
    viewport=800;const f=await mountHome({},Harness);
    const collections=()=>rails(f.host).collections;
    collections().scrollLeft=760;collections().dispatchEvent(new Event('scroll'));await settle();
    [...f.host.querySelectorAll('button')].find(b=>b.textContent.includes('Ver todo')).click();await settle();
    globalThis.__home.interactive(false);await settle();
    assert.deepEqual(f.calls.visible.at(-1),[],'nothing is requested while fullscreen covers Home');
    assert.equal(document.querySelector('[data-featured-sheet]'),null);
    // display:none (retained page) resets scrollers; the rail must put it back on reveal.
    collections().scrollLeft=0;
    globalThis.__home.interactive(true);await settle();
    assert.equal(collections().scrollLeft,760);
    await f.dispose();
  });
}

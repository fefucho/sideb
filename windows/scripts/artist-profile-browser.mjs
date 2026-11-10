// Real ArtistDetailView in Chromium with synthetic metadata (no account, no audio, no WebView2).
// Usage: SIDEB_BROWSER=/path/to/chrome node scripts/artist-profile-browser.mjs
// Compares the recycled profile with the previous full `each` markup rendered by the same fixture ("legacy").
import assert from 'node:assert/strict';
import {writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {createServer} from 'vite';
import {svelte} from '@sveltejs/vite-plugin-svelte';
const root=fileURLToPath(new URL('../',import.meta.url)),cache=path.join(root,'.cache/artist-profile-browser');
await mkdir(cache,{recursive:true});
const SECTIONS=24,CARDS=120;
const fixture=String.raw`<script>
import '$lib/styles/fonts.css';import '$lib/styles/tokens.css';
import Artist from '$lib/components/detail/ArtistDetailView.svelte';
import MediaCard from '$lib/components/common/MediaCard.svelte';
import HorizontalNavigation from '$lib/components/common/HorizontalNavigation.svelte';
import {installNavigationGestures} from '$lib/navigation/gestures';
import {onMount} from 'svelte';
let mode=$state('recycled');
const calls=[];const call=(...args)=>calls.push(args);const noop=()=>{};
const cover='data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160"><rect width="160" height="160" fill="#61419b"/></svg>');
const long='A deliberately long collection title that must wrap over two lines and then clamp for every card ';
const card=(s,i)=>({kind:i%9===0?'video':i%3===0?'playlist':'album',id:'c-'+(i%40),title:(i%5===0?long:'Collection ')+s+'-'+i,subtitle:'Fixture Artist with a long credit line',artists:'Fixture Artist with a long credit line',artistId:'artist',artistRuns:[{id:'artist',text:'Fixture Artist with a long credit line'}],album:null,albumId:null,thumbnail:cover,duration:'3:20',explicit:false});
const sections=Array.from({length:${SECTIONS}},(_,s)=>({title:'Shelf '+s,items:Array.from({length:${CARDS}},(_,i)=>card(s,i)),moreBrowseId:s%2?'MPRE'+s:null,moreParams:null}));
sections.splice(3,0,{title:'Empty',items:[],moreBrowseId:null,moreParams:null});
const song=i=>({videoId:'song-'+i,setVideoId:'o'+i,title:'Song '+i,artists:'Fixture Artist',artistId:'artist',artistRuns:[],album:'Album',albumId:'album',thumbnail:cover,duration:'3:20',isVideo:false});
const artist={channelId:'artist',name:'Fixture Artist',thumbnail:cover,description:'Biography',subscribers:'1M',monthlyListeners:null,subscribed:false,radioPlaylistId:null,topSongs:Array.from({length:6},(_,i)=>song(i)),topSongsId:null,sections};
let commits=[];
onMount(()=>{
  const handle=installNavigationGestures(window,{context:()=>({revision:'artist',enabled:true,blocked:false,fullscreen:false,reduceMotion:true,height:700,backTitle:'Back',forwardTitle:null}),progress:()=>{},commit:action=>commits.push(action)});
  return ()=>handle.dispose();
});
window.lab={show:value=>{mode=value},calls,commits:()=>commits,reset:()=>{commits=[]}};
</script>
<div class="content-column" data-page-scroll>
{#if mode==='recycled'}
<Artist {artist} isLoading={false} error={null} currentTrackId={null} isPlaying={false} loggedIn={false} onRetry={noop} onPlay={noop} onStartRadio={async()=>{}} onToggleSubscription={async()=>{}} onOpenArtist={noop} onOpenAlbum={id=>call('album',id)} onOpenCatalog={(...a)=>call('catalog',...a)} onPlaySong={c=>call('play',c.id)} />
{:else}
<div class="legacy"><header style="height:320px">header</header>
{#each sections as section,sectionIndex (section.title+':'+sectionIndex)}{#if section.items.length>0}
<section class="carousel-section"><div class="section-heading"><h2>{section.title}</h2></div>
<HorizontalNavigation label={section.title} revision="artist" center="80px"><div class="carousel" data-horizontal-scroll>
{#each section.items as c,index (c.kind+':'+c.id+':'+index)}<div class="carousel-card"><MediaCard card={c} onOpen={noop} onPlay={noop} onOpenArtist={noop} onOpenAlbum={noop}/></div>{/each}
</div></HorizontalNavigation></section>{/if}{/each}</div>
{/if}
</div>
<style>:global(body){margin:0;background:#1b1b1e;color:white;font-family:var(--sideb-font-family,Inter,sans-serif)}.content-column{height:780px;overflow-y:auto;overflow-x:hidden;min-width:0}
.legacy{padding:28px 32px 120px}.carousel-section{display:flex;flex-direction:column;gap:14px;margin-inline:-32px;margin-bottom:32px}.section-heading{padding-inline:32px}.carousel{display:flex;gap:16px;overflow-x:auto;padding:0 32px 4px}.carousel-card{display:flex;width:144px;min-width:144px;flex-direction:column;align-items:flex-start}</style>`;
await writeFile(path.join(cache,'Fixture.svelte'),fixture);
await writeFile(path.join(cache,'main.js'),"import {mount} from 'svelte';import Fixture from './Fixture.svelte';mount(Fixture,{target:document.getElementById('app')});");
await writeFile(path.join(cache,'index.html'),'<div id="app"></div><script type="module" src="/main.js"></script>');
const server=await createServer({configFile:false,root:cache,publicDir:path.join(root,'static'),plugins:[svelte()],resolve:{alias:{$lib:path.join(root,'src/lib')}},server:{host:'127.0.0.1',port:0,watch:null,fs:{allow:[root]}},logLevel:'error'});
await server.listen();
const browser=spawn(process.env.SIDEB_BROWSER??'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless=new','--edge-skip-compat-layer-relaunch','--no-first-run','--disable-extensions','--remote-debugging-port=0',`--user-data-dir=${path.join(cache,'browser-'+Date.now())}`,'about:blank'],{windowsHide:true,stdio:['ignore','ignore','pipe']});
let stderr='',ws;browser.stderr.on('data',x=>stderr+=x);
try{
 for(let i=0;i<100&&!stderr.includes('DevTools listening on');i++)await new Promise(r=>setTimeout(r,100));
 const endpoint=stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/)?.[1];assert.ok(endpoint,stderr);
 const pages=await(await fetch(new URL('/json/list',endpoint.replace('ws:','http:')))).json();
 ws=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);await new Promise(r=>ws.addEventListener('open',r,{once:true}));
 let id=0;const pending=new Map(),errors=[];
 ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result)}else if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description??m.params.exceptionDetails.text)});
 const send=(method,params={})=>new Promise((resolve,reject)=>{const key=++id,timer=setTimeout(()=>reject(Error(method+' timeout')),30000);pending.set(key,{resolve:v=>{clearTimeout(timer);resolve(v)},reject:e=>{clearTimeout(timer);reject(e)}});ws.send(JSON.stringify({id:key,method,params}))});
 const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});assert.ok(!r.exceptionDetails,JSON.stringify(r.exceptionDetails));return r.result.value};
 const settle=(ms=220)=>new Promise(r=>setTimeout(r,ms));
 const wheel=(x,y,deltaX,deltaY,modifiers=0)=>send('Input.dispatchMouseEvent',{type:'mouseWheel',x,y,deltaX,deltaY,modifiers});
 await send('Runtime.enable');await send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});
 await send('Emulation.setDeviceMetricsOverride',{width:1000,height:900,deviceScaleFactor:1,mobile:false});
 await send('Page.navigate',{url:server.resolvedUrls.local[0]});
 for(let i=0;i<300;i++){if(await evaluate('!!window.lab'))break;await settle(100)}
 assert.ok(await evaluate('!!window.lab'),errors.join('\n'));await evaluate('document.fonts.ready');await settle();
 const counts=`(()=>({nodes:document.querySelectorAll('*').length,shelves:document.querySelectorAll('section.shelf,section.carousel-section').length,cards:document.querySelectorAll('.carousel-card').length,images:document.querySelectorAll('.carousel-card img').length}))()`;
 const evidence={fixture:{sections:SECTIONS,nonEmpty:SECTIONS,cardsPerSection:CARDS,cards:SECTIONS*CARDS},host:process.platform,browser:await evaluate('navigator.userAgent')};
 // Previous markup, for the same data.
 const legacyStart=Date.now();await evaluate('lab.show("legacy")');await settle(400);evidence.legacy=await evaluate(counts);evidence.legacy.settleMs=Date.now()-legacyStart;
 evidence.legacy.scrollHeight=await evaluate('document.querySelector(".content-column").scrollHeight');
 const start=Date.now();await evaluate('lab.show("recycled")');await settle(400);evidence.recycledInitial=await evaluate(counts);evidence.recycledInitial.settleMs=Date.now()-start;
 // Geometry: no card exceeds its fixed cell; scroll extent equals the full list.
 const geometry=await evaluate(`(()=>{const cells=[...document.querySelectorAll('.carousel-card')];const first=document.querySelector('[data-artist-carousel]');return {maxArticle:Math.max(...cells.map(c=>c.firstElementChild.getBoundingClientRect().height)),cell:cells[0].getBoundingClientRect().height,scrollWidth:first.scrollWidth,clientWidth:first.clientWidth,shelfHeight:document.querySelector('section.shelf').getBoundingClientRect().height,overflow:document.documentElement.scrollWidth>innerWidth}})()`);
 evidence.geometry=geometry;
 assert.ok(geometry.maxArticle<=geometry.cell+.01,'card content exceeds its fixed cell '+JSON.stringify(geometry));
 assert.equal(geometry.scrollWidth,64+CARDS*160-16,'virtual spacers must keep the full scroll extent');
 assert.equal(geometry.overflow,false);
 assert.ok(evidence.recycledInitial.cards<=60,'initial cards '+evidence.recycledInitial.cards);
 // Deep vertical scroll keeps counts bounded and ends on the last shelf.
 const bounded=[];
 for(const top of [2000,6000,12000,20000,1e7]){await evaluate(`document.querySelector('.content-column').scrollTop=${top}`);await settle(160);bounded.push(await evaluate(counts));}
 evidence.verticalScroll=bounded;
 for(const sample of bounded){assert.ok(sample.shelves<=6,'shelves '+sample.shelves);assert.ok(sample.cards<=6*40,'cards '+sample.cards);}
 const last=await evaluate(`(()=>{const s=[...document.querySelectorAll('section.shelf h2')].map(h=>h.textContent);return s.at(-1)})()`);assert.equal(last,'Shelf '+(SECTIONS-1));
 await evaluate(`document.querySelector('.content-column').scrollTop=0`);await settle();
 // Horizontal ownership: ordinary wheels (vertical, horizontal, shift) never navigate; Alt over a shelf is local.
 const rect=await evaluate(`(()=>{const c=document.querySelector('[data-artist-carousel]');c.scrollIntoView({block:'center'});const r=c.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,top:document.querySelector('.content-column').scrollTop}})()`);
 await settle(120);
 const at=await evaluate(`(()=>{const c=document.querySelector('[data-artist-carousel]'),r=c.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+60,top:document.querySelector('.content-column').scrollTop,left:c.scrollLeft}})()`);
 await evaluate('lab.reset()');
 await wheel(at.x,at.y,0,240);await settle(300);
 const afterVertical=await evaluate(`({top:document.querySelector('.content-column').scrollTop,left:document.querySelector('[data-artist-carousel]').scrollLeft,commits:lab.commits().length})`);
 assert.ok(afterVertical.top>at.top,'vertical wheel over a shelf must scroll the page');assert.equal(afterVertical.left,at.left);assert.equal(afterVertical.commits,0);
 const at2=await evaluate(`(()=>{const c=document.querySelector('[data-artist-carousel]'),r=c.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+60,left:c.scrollLeft}})()`);
 for(let i=0;i<6;i++){await wheel(at2.x,at2.y,160,0);await settle(40);}
 await settle(300);
 const afterHorizontal=await evaluate(`({left:document.querySelector('[data-artist-carousel]').scrollLeft,commits:lab.commits().length})`);
 assert.ok(afterHorizontal.left>at2.left,'horizontal wheel scrolls the shelf');assert.equal(afterHorizontal.commits,0,'ordinary horizontal wheel must not navigate history');
 for(let i=0;i<6;i++){await wheel(at2.x,at2.y,-160,0);await settle(40);}
 await settle(300);
 // Alt (modifiers=1) over the shelf: owner is local, no history commit even after release.
 await send('Input.dispatchKeyEvent',{type:'rawKeyDown',key:'Alt',code:'AltLeft',windowsVirtualKeyCode:18,modifiers:1});
 const atAlt=await evaluate(`(()=>{const c=document.querySelector('[data-artist-carousel]'),r=c.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+60}})()`);
 for(let i=0;i<6;i++){await wheel(atAlt.x,atAlt.y,120,0,1);await settle(30);}
 await settle(300);await send('Input.dispatchKeyEvent',{type:'keyUp',key:'Alt',code:'AltLeft',windowsVirtualKeyCode:18});await settle(250);
 const altShelf=await evaluate('lab.commits().length');assert.equal(altShelf,0,'Alt over a shelf must stay with the shelf');
 // Alt over the header remains the explicit history gesture.
 await evaluate(`document.querySelector('.content-column').scrollTop=0`);await settle();
 const head=await evaluate(`(()=>{const r=document.querySelector('.artist-header .artist-info').getBoundingClientRect();return {x:r.x+r.width*.7,y:r.y+r.height*.5}})()`);
 await send('Input.dispatchKeyEvent',{type:'rawKeyDown',key:'Alt',code:'AltLeft',windowsVirtualKeyCode:18,modifiers:1});
 for(let i=0;i<6;i++){await wheel(head.x,head.y,60,0,1);await settle(30);}
 await settle(300);await send('Input.dispatchKeyEvent',{type:'keyUp',key:'Alt',code:'AltLeft',windowsVirtualKeyCode:18});await settle(250);
 evidence.wheel={afterVertical,afterHorizontal,altOverShelf:altShelf,altOverHeader:await evaluate('lab.commits()')};
 assert.deepEqual(evidence.wheel.altOverHeader,['back'],'Alt over non-shelf content still navigates explicitly');
 // Offsets survive recycling.
 const restored=await evaluate(`(async()=>{const sc=document.querySelector('.content-column');const find=t=>[...document.querySelectorAll('section.shelf')].find(s=>s.querySelector('h2').textContent===t);
   const frame=()=>new Promise(r=>setTimeout(r,200));
   sc.scrollTop=0;await frame();
   // Shelf 0 sits at the first shelf; stride is the fixed shelf height.
   let shelf=find('Shelf 0');
   if(!shelf){sc.scrollTop=300;await frame();shelf=find('Shelf 0');}
   const carousel=shelf.querySelector('[data-artist-carousel]');carousel.scrollLeft=2400;await frame();
   const set=carousel.scrollLeft;
   sc.scrollTop=1e7;await frame();const gone=!find('Shelf 0');
   sc.scrollTop=0;await frame();shelf=find('Shelf 0')??(sc.scrollTop=300,await frame(),find('Shelf 0'));
   const back=shelf.querySelector('[data-artist-carousel]');
   return {set,gone,restored:back.scrollLeft,cards:back.querySelectorAll('.carousel-card').length,first:back.querySelector('h3')?.textContent}})()`);
 evidence.offsetRestore=restored;assert.equal(restored.gone,true);assert.equal(restored.restored,restored.set);assert.ok(restored.cards<=24,JSON.stringify(restored));
 // Arrows page by whole cards and stay bounded at deep offsets.
 const arrows=await evaluate(`(async()=>{const frame=()=>new Promise(r=>setTimeout(r,350));const sc=document.querySelector('.content-column');sc.scrollTop=0;await frame();
   const host=document.querySelector('[data-horizontal-navigation="Shelf 0"]');host.scrollIntoView({block:'center'});await frame();
   const next=host.querySelector('[data-horizontal-arrow="next"]'),scroll=host.querySelector('[data-horizontal-scroll]');const before=scroll.scrollLeft;
   const hasNext=next.getAttribute('aria-disabled');next.click();await frame();
   return {before,after:scroll.scrollLeft,hasNext,cards:scroll.querySelectorAll('.carousel-card').length,aligned:(scroll.scrollLeft)%160}})()`);
 evidence.arrows=arrows;assert.equal(arrows.hasNext,'false');assert.ok(arrows.after>arrows.before);assert.equal(arrows.aligned,0,'page target stays on the card stride');
 // Resize keeps counts bounded and no outer overflow.
 const resized=[];
 for(const width of [600,1400]){await send('Emulation.setDeviceMetricsOverride',{width,height:900,deviceScaleFactor:1,mobile:false});await settle(350);resized.push({width,...await evaluate(counts),overflow:await evaluate('document.documentElement.scrollWidth>innerWidth')});}
 evidence.resize=resized;for(const sample of resized){assert.ok(sample.cards<=6*45);assert.equal(sample.overflow,false);}
 // Actions still reach the callbacks.
 await send('Emulation.setDeviceMetricsOverride',{width:1000,height:900,deviceScaleFactor:1,mobile:false});await settle(300);
 await evaluate(`(()=>{document.querySelector('.content-column').scrollTop=0})()`);await settle(200);
 await evaluate(`(()=>{const b=[...document.querySelectorAll('section.shelf .carousel-card .primary')].find(b=>{const r=b.getBoundingClientRect();return r.left>=0&&r.right<=innerWidth});b.scrollIntoView({block:'center'});})()`);await settle(250);
 const target=await evaluate(`(()=>{const b=[...document.querySelectorAll('section.shelf .carousel-card .primary')].find(b=>{const r=b.getBoundingClientRect();return r.left>=0&&r.right<=innerWidth&&r.top>=0&&r.bottom<=innerHeight});const r=b.getBoundingClientRect();return {x:r.x+10,y:r.y+10}})()`);
 await send('Input.dispatchMouseEvent',{type:'mousePressed',x:target.x,y:target.y,button:'left',clickCount:1});await send('Input.dispatchMouseEvent',{type:'mouseReleased',x:target.x,y:target.y,button:'left',clickCount:1});await settle(150);
 evidence.hit=await evaluate(`(()=>{const e=document.elementFromPoint(${target.x},${target.y});return e?e.tagName+'.'+e.className+' in '+e.closest('article')?.className:null})()`);
 evidence.calls=await evaluate('lab.calls.length');if(!(evidence.calls>=1))console.log(JSON.stringify({target,hit:evidence.hit}));assert.ok(evidence.calls>=1,'card activation reaches the page callback');
 assert.deepEqual(errors,[]);
 await writeFile(path.join(cache,'results.json'),JSON.stringify({synthetic:true,errors,evidence},null,2));
 console.log(JSON.stringify({ok:true,evidence},null,1));
}finally{ws?.close();browser.kill();await server.close()}

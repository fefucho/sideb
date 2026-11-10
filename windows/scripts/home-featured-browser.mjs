// Real Svelte Home in Chromium: measured geometry of the featured rails. Synthetic data, no account, no audio.
// Windows: Edge by default. Elsewhere: SIDEB_BROWSER=/path/to/chrome. Only proves layout, never FPS or WebView2.
import assert from 'node:assert/strict';
import {writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {createServer} from 'vite';
import {svelte} from '@sveltejs/vite-plugin-svelte';
const root=fileURLToPath(new URL('../',import.meta.url)),cache=path.join(root,'.cache/home-featured-browser');
await mkdir(cache,{recursive:true});
const fixture=String.raw`<script>
import '$lib/styles/fonts.css';import '$lib/styles/tokens.css';
import Home from '$lib/components/home/HomeView.svelte';
import {defaults} from '$lib/home/settings';
let sidebar=$state(false),session=$state('arrows'),active=$state(true);
const noop=()=>{};const calls=[];
const cover='data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="480" height="480"><rect width="480" height="480" fill="#61419b"/><circle cx="240" cy="240" r="150" fill="#bc8d83"/></svg>');
const card=(i,kind)=>({kind,id:kind+'-'+i,title:(i===0?'A very long album title that cannot fit in one line of a fixed width card ':'Title ')+i,subtitle:'Fixture Artist',artists:'Fixture Artist',artistId:'UCartist',artistRuns:[{id:'UCartist',text:'Fixture Artist'}],album:'Album',albumId:'album-'+i,thumbnail:cover,duration:'3:20',explicit:false});
const sections=[{title:'Quick picks',format:'compactSongs',items:Array.from({length:30},(_,i)=>card(i,'song')),moreBrowseId:null,moreParams:null},{title:'Albums for you',format:'largeCards',items:Array.from({length:40},(_,i)=>card(i,'album')),moreBrowseId:null,moreParams:null}];
const metadata={'album|album-0':{title:'A very long album title that cannot fit in one line of a fixed width card',summary:'Álbum • 2016 • 17 canciones • 1 h 5 min',artists:'An artist with a name too long to fit in the width of one card',artistId:'UCartist'}};
const settings=defaults();
window.lab={sidebar:v=>sidebar=v,session:v=>session=v,active:v=>active=v,calls,visible:[]};
</script>
<div class="content-column" data-page-scroll>
<Home chips={[]} {sections} selectedChipParams={null} isLoading={false} error={null} onSelectChip={noop} onRetry={noop} onOpenAlbum={id=>calls.push(['album',id])} onPlaySong={s=>calls.push(['play',s.id])} onOpenArtist={id=>calls.push(['artist',id])} onOpenPlaylist={noop} hasMore={false} isLoadingMore={false} moreError={null} moreNotice={null} onLoadMore={noop} auth={{state:'ready',name:'Fixture',thumbnail:null}} {session} {settings} kind="albums" albums={[]} playlists={[]} history={[]} onSettings={noop} onKind={noop} interactive={active} libraryError={null} onRetryLibrary={noop} {metadata} onVisibleCollections={items=>window.lab.visible=items.map(i=>i.id)} sidebarOpen={sidebar}/>
</div>
<style>:global(body){margin:0;background:#1b1b1e;color:white;font-family:var(--sideb-font-family,Inter,sans-serif)}.content-column{height:780px;overflow-y:auto;overflow-x:hidden;min-width:0}.content-column :global(.home){min-height:0}</style>`;
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
 const send=(method,params={})=>new Promise((resolve,reject)=>{const key=++id,timer=setTimeout(()=>reject(Error(method+' timeout')),20000);pending.set(key,{resolve:v=>{clearTimeout(timer);resolve(v)},reject:e=>{clearTimeout(timer);reject(e)}});ws.send(JSON.stringify({id:key,method,params}))});
 const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});assert.ok(!r.exceptionDetails,JSON.stringify(r.exceptionDetails));return r.result.value};
 const settle=(ms=250)=>new Promise(r=>setTimeout(r,ms));
 await send('Runtime.enable');await send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});
 await send('Emulation.setDeviceMetricsOverride',{width:1200,height:900,deviceScaleFactor:1,mobile:false});
 await send('Page.navigate',{url:server.resolvedUrls.local[0]});
 for(let i=0;i<300;i++){if(await evaluate('!!window.lab'))break;await settle(100)}
 assert.ok(await evaluate('!!window.lab'),errors.join('\n'));await evaluate('document.fonts.ready');await settle(500);
 const measure=()=>evaluate(`(()=>{
   const box=e=>{const r=e.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height,r:r.right,b:r.bottom}};
   const rail=name=>[...document.querySelectorAll('[data-featured-rail]')].find(e=>e.dataset.featuredRail===name);
   const songs=rail('Acceso rápido')??rail('Speed Dial'),albums=rail('Álbumes')??rail('Albums');
   const tiles=[...songs.querySelectorAll('.media-card.tile')].map(box),cards=[...albums.querySelectorAll('.collection-card')];
   const first=cards[0],art=first.querySelector('.artwork'),h3=first.querySelector('h3'),credits=first.querySelector('.credits'),summary=first.querySelector('.summary');
   const heads=[...document.querySelectorAll('.panel-head')].map(box);
   const featured=document.querySelector('[data-featured]'),home=document.querySelector('.home');
   const host=e=>e.closest('.horizontal-navigation');
   return {viewport:innerWidth,
     songRail:box(songs),albumRail:box(albums),tiles:tiles.slice(0,12),tileSizes:[...new Set(tiles.map(t=>t.w+'x'+t.h))],
     tileTitle:getComputedStyle(songs.querySelector('.media-card.tile h3')).fontSize,tileRadius:getComputedStyle(songs.querySelector('.media-card.tile .artwork')).borderRadius,
     cardSizes:[...new Set(cards.map(c=>{const b=box(c);return b.w+'x'+b.h}))],cardCount:cards.length,
     art:box(art),artRadius:getComputedStyle(art).borderRadius,
     text:{title:box(h3),credits:box(credits),summary:box(summary),card:box(first),h3Lines:Math.round(box(h3).h/16),titleOverflow:h3.scrollWidth>h3.clientWidth+1||getComputedStyle(h3).webkitLineClamp==='1'},
     lastTextBottom:box(summary).b,cardBottom:box(first).b,
     heads,featured:box(featured),trailing:getComputedStyle(home).getPropertyValue('--featured-trailing').trim(),
     albumPadRight:getComputedStyle(albums).paddingRight,albumPadLeft:getComputedStyle(albums).paddingLeft,
     songsHost:{leading:host(songs).classList.contains('leading'),trailing:host(songs).classList.contains('trailing'),prevHidden:host(songs).querySelector('[data-horizontal-arrow=previous]').classList.contains('hidden'),nextHidden:host(songs).querySelector('[data-horizontal-arrow=next]').classList.contains('hidden')},
     albumsHost:{leading:host(albums).classList.contains('leading'),trailing:host(albums).classList.contains('trailing'),fadeLeft:getComputedStyle(host(albums).querySelector('.fade.left')).opacity,fadeRight:getComputedStyle(host(albums).querySelector('.fade.right')).opacity},
     pageOverflow:document.documentElement.scrollWidth>innerWidth,albumScroll:albums.scrollLeft,songScroll:songs.scrollLeft,albumMax:albums.scrollWidth-albums.clientWidth,
     visible:window.lab.visible};
 })()`);
 const evidence=[];
 for(const width of [700,1000,1600]){
   await send('Emulation.setDeviceMetricsOverride',{width,height:900,deviceScaleFactor:1,mobile:false});await settle();
   const m=await measure();evidence.push({width,...m});
   // Fixed card sizes at every width.
   assert.deepEqual(m.tileSizes,['190x126'],width+': Speed Dial tiles');assert.deepEqual(m.cardSizes,['176x240'],width+': collection cards');
   assert.equal(m.songRail.h,3*126+2*12+8,width+': three rows of 126 with 12 gaps (+8 focus room)');
   assert.equal(m.albumRail.h,240+8,width+': 176 artwork + 64 text');
   // Tiles: 3 rows, column-major, 12 gaps.
   const t=m.tiles;assert.equal(t[1].y-t[0].y,138,'row pitch');assert.equal(t[3].x-t[0].x,202,'column pitch');assert.equal(t[0].x,28,'leading inset');
   // Artwork is a square of the card width with radius 10; text fits inside the 64px block.
   assert.equal(m.art.w,176);assert.equal(m.art.h,176);assert.equal(m.artRadius,'10px');assert.equal(m.tileRadius,'10px');
   assert.ok(m.lastTextBottom<=m.cardBottom,width+': text overflows the card by '+(m.lastTextBottom-m.cardBottom));
   assert.equal(m.text.h3Lines,1,'a long title is clamped to one line');
   assert.ok(m.text.title.h<=16.5&&m.text.credits.h<=15.5&&m.text.summary.h<=14.5,JSON.stringify(m.text));
   // Headings 38px tall, rails 8px below; blocks 30 apart; 20 before the next section.
   assert.deepEqual(m.heads.map(h=>h.h),[38,38]);
   // The first rail starts 4px above its box (focus room), so heading bottom + 8 = box top + 4.
   assert.equal(m.songRail.y+4,m.heads[0].b+8);assert.equal(m.albumRail.y+4,m.heads[1].b+8);
   assert.equal(m.heads[1].y-(m.songRail.b-4),30,'30 between the blocks');
   assert.equal(m.pageOverflow,false);
   // Arrows and fades only where there is content out of view.
   assert.deepEqual([m.albumsHost.leading,m.albumsHost.trailing],[false,true]);assert.equal(m.albumsHost.fadeLeft,'0');assert.equal(m.albumsHost.fadeRight,'1');
   assert.equal(m.songsHost.prevHidden,true);
   assert.ok(m.visible.length>=1&&m.visible.length<=Math.ceil(width/190)+1,width+': visible metadata '+m.visible.join());
   await writeFile(path.join(cache,`home-${width}.png`),Buffer.from((await send('Page.captureScreenshot',{format:'png'})).data,'base64'));
   await evaluate('document.querySelector(".content-column").scrollTop=330');await settle(100);
   await writeFile(path.join(cache,`home-${width}-albums.png`),Buffer.from((await send('Page.captureScreenshot',{format:'png'})).data,'base64'));
   await evaluate('document.querySelector(".content-column").scrollTop=0');await settle(100);
 }
 // Paging by arrow moves whole columns and shows the leading arrow/fade.
 await send('Emulation.setDeviceMetricsOverride',{width:1000,height:900,deviceScaleFactor:1,mobile:false});await settle();
 const point=await evaluate(`(()=>{const a=document.querySelector('[data-featured-rail="Álbumes"]').closest('.horizontal-navigation').querySelector('[data-horizontal-arrow=next]');a.scrollIntoView({block:'center'});const r=a.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`);
 await send('Input.dispatchMouseEvent',{type:'mousePressed',x:point.x,y:point.y,button:'left',clickCount:1});await send('Input.dispatchMouseEvent',{type:'mouseReleased',x:point.x,y:point.y,button:'left',clickCount:1});await settle(700);
 const paged=await measure();assert.ok(paged.albumScroll>0&&paged.albumScroll%190===0,'one arrow click moves whole 190px columns, got '+paged.albumScroll);
 assert.equal(paged.albumsHost.leading,true);assert.equal(paged.albumsHost.fadeLeft,'1');
 assert.ok(paged.cardCount<=Math.ceil(1000/190)+3,'recycled, not all 36 mounted: '+paged.cardCount);assert.ok(paged.visible.every(v=>Number(v.split('-')[1])>=Math.floor(paged.albumScroll/190)-1));
 // A vertical wheel over a rail scrolls the page, not the rail.
 const before=await evaluate('document.querySelector(".content-column").scrollTop');
 await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:300,y:await evaluate(`(()=>{const r=document.querySelector('[data-featured-rail="Álbumes"]').getBoundingClientRect();return r.y+r.height/2})()`),deltaX:0,deltaY:120});await settle(500);
 const afterWheel=await evaluate('({page:document.querySelector(".content-column").scrollTop,rail:document.querySelector("[data-featured-rail=\\"Álbumes\\"]").scrollLeft})');
 assert.ok(afterWheel.page>before,'vertical wheel reaches the page');assert.equal(afterWheel.rail,paged.albumScroll,'and leaves the rail alone');
 // The playback sidebar removes the right inset of the featured block; closing it brings the 28px back.
 await evaluate('document.querySelector(".content-column").scrollTop=0');
 await evaluate('lab.sidebar(true)');await settle();
 const open=await measure();assert.equal(open.albumPadRight,'0px');assert.equal(open.albumPadLeft,'28px');
 await evaluate('lab.sidebar(false)');await settle();
 assert.equal((await measure()).albumPadRight,'28px');
 // Covered Home keeps its offset when it comes back (display:none resets scrollers).
 await evaluate('document.querySelector(".home").style.display="none"');await evaluate('lab.active(false)');await settle();
 await evaluate('document.querySelector(".home").style.display="";lab.active(true)');await settle(600);
 assert.equal((await measure()).albumScroll,paged.albumScroll,'offset restored after the page was hidden');
 await writeFile(path.join(cache,'results.json'),JSON.stringify({synthetic:true,host:process.platform,evidence},null,2));
 assert.deepEqual(errors,[]);console.log(JSON.stringify({ok:true,widths:evidence.map(e=>e.width),errors}));
}finally{ws?.close();browser.kill();await server.close()}

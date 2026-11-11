// Real Svelte Home in Chromium: measured geometry of the Speed Dial mosaic and the collection row. Synthetic data, no account, no audio.
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
   const track=document.querySelector('.mosaic .track'),row=document.querySelector('.collection-row'),home=document.querySelector('.home');
   const cards=[...row.querySelectorAll('.item')],first=cards[0].querySelector('article.media-card.panel');
   const host=e=>e.closest('.horizontal-navigation');
   return {viewport:innerWidth,
     track:box(track),row:box(row),cardWidths:[...new Set(cards.map(c=>Math.round(box(c).w*10)/10))],cardCount:cards.length,firstCard:box(first),
     cells:[...track.querySelectorAll('article.media-card.mosaic')].length,
     heads:[...document.querySelectorAll('.collections .panel-head,.mosaic h2')].map(box),viewAll:!!document.querySelector('.collections .panel-head button'),
     trailing:getComputedStyle(home).getPropertyValue('--featured-trailing').trim(),
     rowPad:[getComputedStyle(row).paddingLeft,getComputedStyle(row).paddingRight],trackPad:[getComputedStyle(track).paddingLeft,getComputedStyle(track).paddingRight],
     rowHost:{leading:host(row).classList.contains('leading'),trailing:host(row).classList.contains('trailing')},
     pageOverflow:document.documentElement.scrollWidth>innerWidth,rowScroll:row.scrollLeft,trackScroll:track.scrollLeft,
     visible:window.lab.visible};
 })()`);
 const evidence=[];
 for(const width of [700,1000,1600]){
   await send('Emulation.setDeviceMetricsOverride',{width,height:900,deviceScaleFactor:1,mobile:false});await settle();
   const m=await measure();evidence.push({width,...m});
   // The mosaic is a 488px band; the row is whole cards of equal width between the 28px insets (24px gaps).
   assert.equal(m.track.h,488,width+': mosaic band');assert.ok(m.cells>0,width+': mosaic cells');
   assert.equal(m.cardWidths.length,1,width+': one card width '+m.cardWidths.join());assert.ok(m.cardWidths[0]>=200&&m.cardWidths[0]<=320.1,width+': card width '+m.cardWidths[0]);
   assert.ok(m.firstCard.h>m.firstCard.w,width+': tall panel card');
   assert.equal(m.rowPad[0],'28px');assert.equal(m.trackPad[0],'28px');assert.equal(m.rowPad[1],'28px');assert.equal(m.trackPad[1],'28px');
   assert.equal(m.viewAll,true,width+': Ver todo stays in the collections header');
   assert.equal(m.pageOverflow,false);
   assert.deepEqual([m.rowHost.leading,m.rowHost.trailing],[false,true]);
   assert.ok(m.visible.length>=1,width+': visible metadata '+m.visible.join());
   await writeFile(path.join(cache,`home-${width}.png`),Buffer.from((await send('Page.captureScreenshot',{format:'png'})).data,'base64'));
 }
 // Paging by arrow moves the row and shows the leading arrow/fade.
 await send('Emulation.setDeviceMetricsOverride',{width:1000,height:900,deviceScaleFactor:1,mobile:false});await settle();
 const point=await evaluate(`(()=>{const a=document.querySelector('.collection-row').closest('.horizontal-navigation').querySelector('[data-horizontal-arrow=next]');a.scrollIntoView({block:'center'});const r=a.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`);
 await send('Input.dispatchMouseEvent',{type:'mousePressed',x:point.x,y:point.y,button:'left',clickCount:1});await send('Input.dispatchMouseEvent',{type:'mouseReleased',x:point.x,y:point.y,button:'left',clickCount:1});await settle(700);
 const paged=await measure();assert.ok(paged.rowScroll>0,'one arrow click moves the row, got '+paged.rowScroll);
 assert.equal(paged.rowHost.leading,true);
 // A vertical wheel over the row scrolls the page, not the row.
 const before=await evaluate('document.querySelector(".content-column").scrollTop');
 await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:300,y:await evaluate(`(()=>{const r=document.querySelector('.collection-row').getBoundingClientRect();return r.y+r.height/2})()`),deltaX:0,deltaY:120});await settle(500);
 const afterWheel=await evaluate('({page:document.querySelector(".content-column").scrollTop,row:document.querySelector(".collection-row").scrollLeft})');
 assert.ok(afterWheel.page>before,'vertical wheel reaches the page');assert.equal(afterWheel.row,paged.rowScroll,'and leaves the row alone');
 // The playback sidebar removes the right inset of the mosaic and the row; closing it brings the 28px back.
 await evaluate('document.querySelector(".content-column").scrollTop=0');
 await evaluate('lab.sidebar(true)');await settle();
 const open=await measure();assert.equal(open.rowPad[1],'0px');assert.equal(open.trackPad[1],'0px');assert.equal(open.rowPad[0],'28px');
 await evaluate('lab.sidebar(false)');await settle();
 const closed=await measure();assert.equal(closed.rowPad[1],'28px');assert.equal(closed.trackPad[1],'28px');
 // Covered Home keeps its anchor when it comes back (display:none resets scrollers).
 await evaluate('document.querySelector(".home").style.display="none"');await evaluate('lab.active(false)');await settle();
 await evaluate('document.querySelector(".home").style.display="";lab.active(true)');await settle(600);
 // The row keeps the anchor card, not the pixel offset: it comes back aligned to the card it was on.
 const restored=await measure(),stride=closed.cardWidths[0]+24;
 assert.ok(closed.rowScroll>0&&Math.round(restored.rowScroll/stride)===Math.round(closed.rowScroll/stride),`anchor card restored after the page was hidden: ${closed.rowScroll} -> ${restored.rowScroll} (stride ${stride})`);
 await writeFile(path.join(cache,'results.json'),JSON.stringify({synthetic:true,host:process.platform,evidence},null,2));
 assert.deepEqual(errors,[]);console.log(JSON.stringify({ok:true,widths:evidence.map(e=>e.width),errors}));
}finally{ws?.close();browser.kill();await server.close()}

// Real Svelte and Edge layout. Synthetic metadata, no user account or playback.
import assert from 'node:assert/strict';
import {writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {createServer} from 'vite';
import {svelte} from '@sveltejs/vite-plugin-svelte';
const root=fileURLToPath(new URL('../',import.meta.url)),cache=path.join(root,'.cache/player-bar-browser');
await mkdir(cache,{recursive:true});
await writeFile(path.join(cache,'Fixture.svelte'),String.raw`<script>
import '$lib/styles/fonts.css';import '$lib/styles/tokens.css';import PlayerBar from '$lib/components/player/PlayerBar.svelte';import {setContext} from 'svelte';import {FEATURED_ARTIST_CONTEXT,featuredClauses} from '$lib/featured/artists';
let width=$state(820),liked=$state(false);const calls=[];const long='Very long music title with many words to test full scrolling and another long phrase (feat. Guest Artist)';
let playback=$state({currentTrack:{videoId:'fixture',title:long,artists:'Fixture Artist',artistId:'artist',album:'Fixture Album',albumId:'album',thumbnail:null,contentRating:'explicit'},isPlaying:true,isLoading:false,isEnded:false,isShuffle:false,isRepeat:false,position:30,duration:240,volume:70,error:null,generation:1,queue:{items:[],currentIndex:null}});
setContext(FEATURED_ARTIST_CONTEXT,{scopeRevision:1,title:async track=>featuredClauses(track.title).map(c=>({...c,id:'guest'})),open:async(track,name,open)=>open('guest'),search:()=>{},candidates:async()=>[],choose:()=>{},clearChoice:()=>{}});
window.lab={metadata:v=>playback={...playback,currentTrack:{...playback.currentTrack,...v}},width:v=>width=v,patch:v=>playback={...playback,...v},title:v=>playback={...playback,currentTrack:{...playback.currentTrack,title:v}},long:()=>playback={...playback,currentTrack:{...playback.currentTrack,title:long}},calls};
</script><main style:width={width+'px'}><PlayerBar {playback} {liked} loggedIn fullscreenOpen={false} onTogglePlayback={()=>calls.push('play')} onRetryPlayback={()=>calls.push('retry')} onPrevious={()=>calls.push('previous')} onNext={()=>calls.push('next')} onSeek={v=>calls.push(['seek',v])} onVolumeChange={v=>calls.push(['volume',v])} onSetShuffle={async()=>calls.push('shuffle')} onSetRepeat={async()=>calls.push('repeat')} onToggleFullscreen={()=>calls.push('fullscreen')} onToggleLike={()=>{liked=!liked;calls.push('like')}} onDislike={()=>{liked=false;calls.push('dislike')}} onOpenArtist={id=>calls.push(id)} onOpenAlbum={id=>calls.push(id)} onOpenMenu={()=>calls.push('menu')} onSelectPanel={id=>calls.push(id)}/></main><style>:global(body){margin:0;background:#19191c;color:white;font-family:var(--sideb-font-family,Inter,sans-serif)}main{position:absolute;top:180px;left:20px;max-width:calc(100vw - 40px)}</style>`);
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
 let id=0;const pending=new Map(),errors=[],evidence=[];
 ws.addEventListener('message',event=>{const m=JSON.parse(event.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result)}else if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description??m.params.exceptionDetails.text)});
 const send=(method,params={})=>new Promise((resolve,reject)=>{const key=++id,timer=setTimeout(()=>reject(Error(method+' timeout')),20000);pending.set(key,{resolve:value=>{clearTimeout(timer);resolve(value)},reject:error=>{clearTimeout(timer);reject(error)}});ws.send(JSON.stringify({id:key,method,params}))});
 const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});assert.ok(!r.exceptionDetails,JSON.stringify(r.exceptionDetails));return r.result.value};
 const settle=()=>new Promise(resolve=>setTimeout(resolve,150));
 // Geometry/motion assertions run with an explicit preference, independent of the runner OS.
 await send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'no-preference'}]});
 await send('Emulation.setFocusEmulationEnabled',{enabled:true});
 await send('Runtime.enable');await send('Page.navigate',{url:server.resolvedUrls.local[0]});
 for(let i=0;i<300;i++){if(await evaluate('!!window.lab'))break;await settle()}
 assert.ok(await evaluate('!!window.lab'),errors.join('\n'));await evaluate('document.fonts.ready');assert.equal(await evaluate('matchMedia("(prefers-reduced-motion: reduce)").matches'),false);
 assert.equal(await evaluate('document.querySelector(".album-separator").textContent'),'\u2022');
 const sleep=ms=>new Promise(r=>setTimeout(r,ms));
 const geom=()=>evaluate(`(()=>{const box=s=>{const r=document.querySelector(s).getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height,right:r.right,bottom:r.bottom}};return {bar:box('.player-bar'),metadata:box('.metadata'),title:box('.title'),artist:box('.artist-line'),actions:box('.track-actions'),like:box('.like-toggle'),more:box('.more-toggle'),dislike:box('.dislike-toggle'),lyrics:box('.panel-shortcut'),parts:box('.title-parts'),viewport:box('.featured-title'),reduced:matchMedia('(prefers-reduced-motion: reduce)').matches,focused:document.hasFocus(),hidden:document.hidden,animations:document.querySelector('.title-parts').getAnimations().map(a=>({time:a.currentTime,state:a.playState}))}})()`);
 const move=async(x,y)=>send('Input.dispatchMouseEvent',{type:'mouseMoved',x,y});
 for(const dpr of [1,1.25,1.5,2]){
  await send('Emulation.setDeviceMetricsOverride',{width:1000,height:600,deviceScaleFactor:dpr,mobile:false});
  for(const width of [620,700,760,820]){
   await evaluate(`lab.width(${width})`);await settle();const g=await geom();
   assert.equal(g.bar.width,width);assert.equal(g.bar.height,74);assert.equal(g.actions.width,60);assert.equal(g.actions.height,46);
   assert.equal(g.like.width,32);assert.equal(g.like.height,44);assert.equal(g.dislike.x,g.more.x);assert.equal(g.dislike.height,22);assert.equal(g.more.y-g.dislike.bottom,2);assert.equal(g.more.x-g.like.right,4);
   assert.equal(g.lyrics.x-g.actions.right,17);assert.equal(g.title.right,g.artist.right);assert.equal(g.actions.x-g.metadata.right,10);assert.equal(g.lyrics.x-g.actions.right,17);evidence.length&&assert.ok(g.metadata.width>0);
   evidence.push({dpr,width,...g});
  }
 }
 await evaluate('lab.width(820)');await settle();await move(5,5);await sleep(1800);
 let before=await geom();assert.ok(before.parts.x<before.viewport.x-5,JSON.stringify(before));
 await move(before.viewport.x+10,before.viewport.y+6);await sleep(60);const paused=await geom();await sleep(2100);const held=await geom();
 assert.ok(Math.abs(paused.parts.x-held.parts.x)<0.2,'hover preserves actual offset for 2 seconds');assert.equal(held.animations[0].state,'paused');
 await move(5,5);await sleep(500);const resumed=await geom();assert.ok(resumed.parts.x<held.parts.x-5,'mouseleave continues existing offset');
 await evaluate(`window.savedAnimation=document.querySelector('.title-parts').getAnimations()[0];lab.patch({position:99});document.querySelector('.like-toggle').click()`);await settle();
 assert.equal(await evaluate('savedAnimation===document.querySelector(".title-parts").getAnimations()[0]'),true,'progress and Like keep animation identity');
 await evaluate('document.querySelector(".title-credit").focus({preventScroll:true})');await settle();
 const focusGeometry=()=>evaluate(`(()=>{const a=document.querySelector('.title-credit').getBoundingClientRect(),b=document.querySelector('.featured-title').getBoundingClientRect();return {left:a.left,right:a.right,clipLeft:b.left,clipRight:b.right,scroll:document.scrollingElement.scrollTop}})()`);
 let focus=await focusGeometry();assert.ok(focus.left>=focus.clipLeft-1&&focus.right<=focus.clipRight+1,JSON.stringify(focus));assert.equal(focus.scroll,0);assert.equal((await geom()).animations[0].state,'paused');
 await evaluate('document.querySelector(".title-credit").click()');await settle();assert.equal(await evaluate('lab.calls.at(-1)'),'guest');
 await evaluate('document.querySelector(".title-credit").dispatchEvent(new MouseEvent("contextmenu",{bubbles:true,cancelable:true}))');await settle();
 assert.equal(await evaluate('document.querySelector(".match-menu").parentElement===document.body'),true);
 assert.equal(await evaluate('document.activeElement===document.querySelector(".match-menu button")'),true,'portal menu receives keyboard focus');
 await evaluate('document.querySelector(".title-credit").blur()');await move(5,5);await settle();assert.equal((await geom()).animations[0].state,'paused','menu keeps pause outside title');
 await evaluate('document.querySelector(".match-menu button:last-child").click()');await settle();assert.equal((await geom()).animations[0].state,'running');
 await evaluate('lab.width(700)');await settle();assert.ok((await geom()).animations[0].time<600,'resize restarts at initial wait');
 await evaluate(`(()=>{const a=document.querySelector('.title-parts').getAnimations()[0];a.currentTime=a.effect.getTiming().duration-700})()`);await settle();const end=await geom();assert.ok(Math.abs(end.parts.right-end.viewport.right)<1,'cycle reaches the final title characters');await sleep(850);const restarted=await geom();assert.ok(Math.abs(restarted.parts.x-restarted.viewport.x)<1,'cycle returns to its initial hold');
 await evaluate('document.querySelector("main").style.transform="translateY(1000px)"');await sleep(200);assert.equal((await geom()).animations[0].state,'paused','offscreen intersection pauses the title');await evaluate('document.querySelector("main").style.transform="none"');await sleep(200);
 await evaluate('window.dispatchEvent(new Event("blur"))');await settle();assert.equal((await geom()).animations[0].state,'paused');await evaluate('window.dispatchEvent(new Event("focus"))');await settle();assert.equal((await geom()).animations[0].state,'running');
 const widthBefore=(await geom()).metadata.width;await evaluate('document.querySelector(".volume-toggle").click()');await settle();assert.equal((await geom()).metadata.width,widthBefore);assert.equal(await evaluate('document.querySelector(".panel-shortcuts").inert'),true);
 await send('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape'});await settle();assert.equal(await evaluate('document.querySelector(".volume").classList.contains("open")'),false);
 await evaluate('lab.title("Short")');await settle();assert.equal((await geom()).animations.length,0,'short title stays still');
 const shortGeometry=await geom();const natural=await evaluate(`(()=>{const title=document.querySelector('.title-parts').getBoundingClientRect(),artist=document.querySelector('.artist-credits').getBoundingClientRect(),actions=document.querySelector('.track-actions').getBoundingClientRect();return {gap:actions.left-Math.max(title.right,artist.right),lyrics:document.querySelector('.panel-shortcut').getBoundingClientRect().left,separator:getComputedStyle(document.querySelector('.end-controls'),'::before').backgroundColor}})()`);assert.ok(Math.abs(natural.gap-10)<1,JSON.stringify(natural));assert.equal(natural.separator,'rgba(0, 0, 0, 0)');
 assert.equal(await evaluate('getComputedStyle(document.querySelector(".track"),"::before").content'),'none','transport separation stays invisible');
 assert.equal(await evaluate('getComputedStyle(document.querySelector(".artwork")).borderRadius'),'2px','bottom cover uses queue artwork radius');
 const anchoredLyrics=natural.lyrics;
 await evaluate('lab.metadata({title:"A somewhat longer short title",artists:"X",album:"Y"})');await settle();
 const titleNatural=await evaluate(`(()=>{const title=document.querySelector('.title-parts').getBoundingClientRect(),actions=document.querySelector('.track-actions').getBoundingClientRect();return {gap:actions.left-title.right,lyrics:document.querySelector('.panel-shortcut').getBoundingClientRect().left}})()`);
 assert.ok(Math.abs(titleNatural.gap-10)<1,JSON.stringify(titleNatural));assert.equal(titleNatural.lyrics,anchoredLyrics,'short metadata never shifts anchored controls');
 const actionX=(await geom()).actions.x;await evaluate('lab.patch({position:130})');await settle();assert.equal((await geom()).actions.x,actionX,'playback ticks keep actions still');

 await evaluate('document.querySelector(".like-toggle").click();document.querySelector(".dislike-toggle").click()');await settle();assert.equal(await evaluate('document.querySelector(".like-toggle").getAttribute("aria-pressed")'),'false');assert.equal(await evaluate('lab.calls.at(-1)'),'dislike');
 await evaluate('lab.long()');await settle();await send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});await settle();assert.equal((await geom()).animations.length,0);
 await evaluate('document.querySelector(".title-credit").focus({preventScroll:true})');await settle();const reducedFocus=await focusGeometry();assert.ok(reducedFocus.left>=reducedFocus.clipLeft-1&&reducedFocus.right<=reducedFocus.clipRight+1,JSON.stringify(reducedFocus));
 assert.equal(await evaluate('document.querySelectorAll(".title-credit").length'),1,'one accessible interactive title');
 assert.deepEqual(errors,[]);await writeFile(path.join(cache,'results.json'),JSON.stringify({synthetic:true,host:process.platform,evidence,paused,held,resumed,focus,reducedFocus,shortGeometry,natural,errors},null,2));
 const shot=await send('Page.captureScreenshot',{format:'png'});await writeFile(path.join(cache,'player-bar.png'),Buffer.from(shot.data,'base64'));
 await send('Emulation.setEmulatedMedia',{features:[]});await send('Emulation.setDeviceMetricsOverride',{width:1000,height:600,deviceScaleFactor:1,mobile:false});await evaluate('document.activeElement?.blur();lab.width(820);lab.title("Canción para escuchar con calma 🎵")');await settle();const initialShot=await send('Page.captureScreenshot',{format:'png',clip:{x:12,y:172,width:836,height:90,scale:1}});await writeFile(path.join(cache,'player-bar-820.png'),Buffer.from(initialShot.data,'base64'));
 console.log(JSON.stringify({ok:true,layoutCases:evidence.length,hoverPauseMilliseconds:2100,focus,reducedFocus,errors}));
}finally{ws?.close();browser.kill();await server.close()}

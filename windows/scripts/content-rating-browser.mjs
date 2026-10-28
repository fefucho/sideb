// Real Svelte and Edge layout. Synthetic metadata, no user account or playback.
import assert from 'node:assert/strict';
import {writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {createServer} from 'vite';
import {svelte} from '@sveltejs/vite-plugin-svelte';
const root=fileURLToPath(new URL('../',import.meta.url)),cache=path.join(root,'.cache/content-rating-browser');
await mkdir(cache,{recursive:true});
await writeFile(path.join(cache,'Fixture.svelte'),String.raw`<script>
import '$lib/styles/fonts.css';import '$lib/styles/tokens.css';
import Header from '$lib/components/detail/CollectionHeader.svelte';
import Credits from '$lib/components/ArtistCredits.svelte';import Player from '$lib/components/player/PlayerBar.svelte';import Fullscreen from '$lib/components/fullscreen/FullscreenNowPlaying.svelte';import Recommended from '$lib/components/fullscreen/RecommendedSongRow.svelte';
import Home from '$lib/components/home/HomeCard.svelte';import Title from '$lib/components/FeaturedTrackTitle.svelte';import Card from '$lib/components/common/MediaCard.svelte';
import {setLanguage} from '$lib/i18n';let rating=$state('explicit'),fullscreen=$state(false),scene=$state(false);const calls=[];const noop=()=>{};
window.__TAURI_INTERNALS={invoke:async()=>null,transformCallback:()=>0,unregisterCallback:noop};
const playback=$derived({isPlaying:false,isLoading:false,isEnded:false,isShuffle:false,isRepeat:false,position:0,duration:200,volume:100,generation:1,currentTrack:track,error:null,queue:{items:[{...track,entryId:'entry-1'}],currentIndex:0,revision:1,radio:null,source:null}});
const playerCallbacks={onTogglePlayback:noop,onRetryPlayback:noop,onPrevious:noop,onNext:noop,onSeek:noop,onVolumeChange:noop,onSetShuffle:async()=>{},onSetRepeat:async()=>{},onToggleFullscreen:()=>fullscreen=!fullscreen};
const fullscreenCallbacks={onSelectQueue:noop,onTogglePlayback:noop,onMoveQueue:async()=>{},onSeek:noop,onRetryLyrics:noop,onRefreshRecommendations:noop,onPlayRecommendation:noop,onEnqueueRecommendation:noop,onSongContextMenu:noop,onArtistContextMenu:noop,onClose:()=>fullscreen=false,onOpenExternal:noop};
const track=$derived({videoId:'same-id',title:'A long song title that should truncate before the badge',artists:'Fixture Artist',contentRating:rating});
const card=$derived({kind:'album',id:'album',title:'A long album title for wrapping',subtitle:'Fixture Artist',artists:'Fixture Artist',contentRating:rating,thumbnail:null,duration:null});
window.lab={update:(value,lang)=>{rating=value;setLanguage(lang)},scene:()=>scene=true,fullscreen:value=>fullscreen=value,calls,identity:()=>[track.videoId,track.contentRating]};
</script>
<main>{#if !scene}<h1>Contenido · Mac / Windows</h1><p>Insignia proporcional a metadata; geometría centrada.</p>
{#each [10,11.5,13,17.5] as size}<div class="sample" style:font-size={size+'px'}><div><Title track={track} onPlay={()=>calls.push(track.videoId)}/><Credits {track} artists={track.artists} artistId="artist-id" onOpenArtist={id=>calls.push(id)} /></div></div>{/each}
<div class="cards"><div class="card"><Card {card} onOpen={()=>calls.push(card.id)}/></div><div class="card"><Home item={{...card,artistRuns:[],explicit:rating==='explicit'}}/></div></div><Header content={card} identity="album" title={card.title} thumbnail={null} kind="Album">{#snippet credit()}<Credits artists="Fixture Artist" />{/snippet}{#snippet actions()}<button>Play</button>{/snippet}</Header><div class="missing-credits"><Credits track={{...track,artists:""}} /></div>{:else}<Player {playback} fullscreenOpen={fullscreen} {...playerCallbacks}/>{#if fullscreen}<Fullscreen session={1} {playback} geniusState={{phase:"idle"}} geniusController={{ensureNow:async()=>{}}} lyricsState={{status:"idle",lyrics:null,trackKey:null,error:null}} recommendationsState={{loading:false,data:null,error:null}} {...fullscreenCallbacks}/><div class="related-fixture"><Recommended song={track} index={0} currentTrackId={track.videoId} isPlaying={false} onPlaySong={noop}/></div>{/if}{/if}</main>
<style>:global(body){margin:0;background:#1b1b1e;color:white;font-family:var(--sideb-font-family,Inter,sans-serif)}main{padding:32px;max-width:700px}h1{font-size:24px}p{color:#aaa}.sample{width:480px;max-width:100%;height:70px;display:flex;align-items:center}.sample :global(.featured-title){width:100%}.sample>div{min-width:0;width:100%}.related-fixture{position:fixed;z-index:1000;bottom:110px;right:30px;width:260px;background:#222}.cards{display:flex;gap:32px;margin-top:20px}.card{width:160px}</style>`);
await writeFile(path.join(cache,'main.js'),"import {mount} from 'svelte';import Fixture from './Fixture.svelte';mount(Fixture,{target:document.getElementById('app')});");
await writeFile(path.join(cache,'index.html'),'<div id="app"></div><script type="module" src="/main.js"></script>');
const server=await createServer({configFile:false,root:cache,publicDir:path.join(root,'static'),plugins:[svelte()],resolve:{alias:{$lib:path.join(root,'src/lib')}},server:{host:'127.0.0.1',port:0,fs:{allow:[root]}},logLevel:'error'});
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
 const send=(method,params={})=>new Promise((resolve,reject)=>{const key=++id,timer=setTimeout(()=>reject(Error(method+' timeout '+JSON.stringify(params))),20000);pending.set(key,{resolve:value=>{clearTimeout(timer);resolve(value)},reject:error=>{clearTimeout(timer);reject(error)}});ws.send(JSON.stringify({id:key,method,params}))});
 const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});assert.ok(!r.exceptionDetails,JSON.stringify(r.exceptionDetails));return r.result.value};
 const settle=()=>new Promise(resolve=>setTimeout(resolve,150));
 console.log('fixture: navigating');await send('Runtime.enable');await send('Page.navigate',{url:server.resolvedUrls.local[0]});
 for(let i=0;i<300;i++){if(await evaluate('!!window.lab'))break;await settle()}
 assert.ok(await evaluate('!!window.lab'),errors.join('\n'));await evaluate('document.fonts.ready');
 console.log('fixture: mounted');for(const dpr of [1,1.5,2]){
  await send('Emulation.setDeviceMetricsOverride',{width:800,height:720,deviceScaleFactor:dpr,mobile:false});
  for(const [rating,lang]of [['explicit','es'],['clean','es'],['clean','en'],['unknown','es']]){
   await evaluate(`lab.update(${JSON.stringify(rating)},${JSON.stringify(lang)})`);await settle();
   const rows=await evaluate(`(()=>[...document.querySelectorAll('.explicit-badge')].map(chip=>{const box=chip.getBoundingClientRect(),ink=chip.querySelector('path').getBBox(),owner=chip.closest('.artist-credits,.credit'),outer=owner.getBoundingClientRect();return {before:chip===owner.firstElementChild,placement:owner.className,fontSize:parseFloat(getComputedStyle(chip).fontSize),gap:parseFloat(getComputedStyle(owner).columnGap),radius:parseFloat(getComputedStyle(chip).borderRadius),width:box.width,height:box.height,center:[ink.x+ink.width/2,ink.y+ink.height/2],inside:box.left>=outer.left&&box.right<=outer.right&&box.top>=outer.top-1&&box.bottom<=outer.bottom+1,label:chip.getAttribute('aria-label'),path:chip.querySelector('path').getAttribute('d'),background:getComputedStyle(chip).backgroundColor,color:getComputedStyle(chip).color}}))()`);
   assert.equal(rows.length,rating==='unknown'?0:8);
   for(const row of rows){const expected=Math.max(9,Math.min(12,Math.round(row.fontSize*.85)));assert.equal(row.width,expected);assert.equal(row.height,expected);assert.equal(row.gap,4);assert.ok(Math.abs(row.radius-expected*3/14)<.001);assert.equal(row.before,true);assert.deepEqual(row.center,[7,7]);assert.ok(row.inside,JSON.stringify(row));assert.equal(row.label,rating==='explicit'?'Contenido explícito':lang==='es'?'Versión limpia confirmada':'Confirmed clean version');}
   assert.equal(await evaluate('document.querySelectorAll(".featured-title .explicit-badge,.title-row .explicit-badge").length'),0);
   if(rating==='unknown')assert.ok((await evaluate('document.body.textContent')).includes('Sin información de contenido'));
   if(rating==='explicit'){
    await evaluate('document.querySelector(".sample .title-text").click()');assert.equal(await evaluate('lab.calls.at(-1)'),'same-id');
    const shot=await send('Page.captureScreenshot',{format:'png'});await writeFile(path.join(cache,`explicit-dpr-${dpr}.png`),Buffer.from(shot.data,'base64'));
   }
   evidence.push({dpr,rating,lang,rows});
  }
 }
 await evaluate('lab.update("explicit","es")');await settle();
 await send('Emulation.setEmulatedMedia',{features:[{name:'forced-colors',value:'active'}]});
 const contrast=await evaluate('(()=>{const style=getComputedStyle(document.querySelector(".explicit-badge"));return {background:style.backgroundColor,color:style.color}})()');assert.notEqual(contrast.background,contrast.color);
 await send('Emulation.setEmulatedMedia',{features:[]});
 console.log('fixture: player scenes');await evaluate('lab.scene()');await settle();
 assert.equal(await evaluate('document.querySelectorAll(".artist-line .explicit-badge").length'),1);
 for(const open of [true,false,true,false]){
  await evaluate(`lab.fullscreen(${open})`);await new Promise(r=>setTimeout(r,500));
  assert.deepEqual(await evaluate('lab.identity()'),['same-id','explicit']);
  assert.equal(await evaluate('document.querySelectorAll(".title .explicit-badge,.title-line .explicit-badge,.queue-title .explicit-badge").length'),0,'player/fullscreen titles stay free');
  assert.equal(await evaluate('document.querySelectorAll(".artist-line .explicit-badge").length'),1,'only bottom bar metadata keeps its chip');
  assert.equal(await evaluate('document.querySelectorAll(".queue-meta .explicit-badge").length'),open?1:0,'fullscreen queue keeps badge');
  assert.equal(await evaluate('document.querySelectorAll(".recommended-song .credits .explicit-badge").length'),open?1:0,'related real row keeps badge');
 }
 assert.deepEqual(errors,[]);await writeFile(path.join(cache,'results.json'),JSON.stringify({synthetic:true,host:process.platform,evidence,contrast,errors},null,2));console.log(JSON.stringify({ok:true,cases:evidence.length,contrast,errors}));
}finally{ws?.close();browser.kill();await server.close()}

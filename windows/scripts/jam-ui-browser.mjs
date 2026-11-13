// Real Svelte + a real Chromium/Edge: Jam UI screenshots and geometry (no account, no Jam, fixture states only).
// Usage: SIDEB_BROWSER=<chrome|edge> JAM_UI_SHOTS=<dir> node scripts/jam-ui-browser.mjs
import assert from 'node:assert/strict';
import {writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {createServer} from 'vite';
import {svelte} from '@sveltejs/vite-plugin-svelte';
const root=fileURLToPath(new URL('../',import.meta.url)),cache=path.join(root,'.cache/jam-ui-browser');
const shots=process.env.JAM_UI_SHOTS??path.join(cache,'shots');
await mkdir(cache,{recursive:true});await mkdir(shots,{recursive:true});
const fixtures=await import('./jam-ui-fixtures.mjs');
await writeFile(path.join(cache,'Fixture.svelte'),String.raw`<script>
import '$lib/styles/fonts.css';import '$lib/styles/tokens.css';
import {setContext} from 'svelte';import {writable} from 'svelte/store';
import {FEATURED_ARTIST_CONTEXT,featuredClauses} from '$lib/featured/artists';
import {provideJamUi} from '$lib/components/jam/context';
import {emptyLyricsState} from '$lib/player/lyrics';import {emptyRecommendationsSnapshot} from '$lib/player/recommendations';import {emptyGeniusState} from '$lib/genius/types';
import PlayerBar from '$lib/components/player/PlayerBar.svelte';
import JamPanel from '$lib/components/jam/JamPanel.svelte';import JamQueueList from '$lib/components/jam/JamQueueList.svelte';
import JamToasts from '$lib/components/jam/JamToasts.svelte';import JamExitDialog from '$lib/components/jam/JamExitDialog.svelte';
import FullscreenNowPlaying from '$lib/components/fullscreen/FullscreenNowPlaying.svelte';
import SidebarArtwork from '$lib/components/playback-sidebar/SidebarArtwork.svelte';import SidebarUpcomingQueue from '$lib/components/playback-sidebar/SidebarUpcomingQueue.svelte';
const store=writable(window.__initial);const calls=[];
const actions=new Proxy({},{get:(_,name)=>(...args)=>{calls.push([name,...args]);return Promise.resolve(name==='addSong')}});
const searchSongs=async()=>[{videoId:'alt1',title:'Blinding Lights (Live)',artists:'The Weeknd',album:null,duration:'3:25',thumbnail:null,isVideo:false,artistId:null,albumId:null},{videoId:'alt2',title:'Blinding Lights (Official Video)',artists:'The Weeknd',album:null,duration:'3:21',thumbnail:null,isVideo:true,artistId:null,albumId:null}];
provideJamUi({state:store,actions,searchSongs});
setContext(FEATURED_ARTIST_CONTEXT,{scopeRevision:1,title:async track=>featuredClauses(track.title).map(c=>({...c,id:'guest'})),open:async()=>{},search:()=>{},candidates:async()=>[],choose:()=>{},clearChoice:()=>{}});
let panelSel=$state('queue'),mode=$state('panel'),playback=$state(window.__playback),variant=$state('popover');
window.lab={store,calls,mode:v=>mode=v,set:patch=>store.update(s=>({...s,...patch})),playback:v=>playback=v,variant:v=>variant=v};
const noop=()=>{};const genius={ensureNow:noop,dispose:noop};
</script>
{#if mode==='panel'}<div class="surface popover"><JamPanel state={$store} {actions} {searchSongs} {variant}/></div>
{:else if mode==='queue'}<div class="surface queue"><JamQueueList {playback} onSelectQueue={noop} onTogglePlayback={noop}/></div>
{:else if mode==='upcoming'}<div class="surface upcoming"><SidebarUpcomingQueue session={0} {playback} onSelectQueue={noop}/></div>
{:else if mode==='toasts'}<JamToasts toasts={$store.toasts} onDismiss={id=>actions.dismissToast(id)} duration={600000}/><JamExitDialog pending={$store.pendingExit} {actions}/>
{:else if mode==='bar'}<main class="bar"><PlayerBar {playback} loggedIn fullscreenOpen={false} onTogglePlayback={noop} onRetryPlayback={noop} onPrevious={noop} onNext={noop} onSeek={noop} onVolumeChange={noop} onSetShuffle={async()=>{}} onSetRepeat={async()=>{}} onToggleFullscreen={noop} onSelectPanel={noop} onOpenMenu={noop}/></main>
{:else if mode==='fullscreen'}<FullscreenNowPlaying session={0} {playback} geniusState={emptyGeniusState()} geniusController={genius} onOpenExternal={noop} onSelectQueue={noop} onTogglePlayback={noop} onMoveQueue={noop} lyricsState={emptyLyricsState()} recommendationsState={emptyRecommendationsSnapshot()} onSeek={noop} onRetryLyrics={noop} onRefreshRecommendations={noop} onPlayRecommendation={noop} onEnqueueRecommendation={noop} onSongContextMenu={noop} onArtistContextMenu={noop} onClose={noop} selectedPanel={panelSel} onSelectPanel={p=>panelSel=p}/>
{:else if mode==='sidebar'}<div class="sidebar"><SidebarArtwork session={0} {playback} active presented/></div>{/if}
<style>:global(body){margin:0;background:#1b1b1e;color:white;font-family:var(--sideb-font-family,Inter,sans-serif)}
.surface{position:absolute;top:20px;left:20px;box-sizing:border-box;background:#29292f;border:1px solid rgb(255 255 255 / 12%);border-radius:14px;box-shadow:0 16px 44px rgb(0 0 0 / 50%)}.popover{width:340px}.queue{width:520px;height:420px;display:flex;padding:12px}.upcoming{width:360px;padding:14px}
.bar{position:absolute;left:20px;right:20px;bottom:30px;display:flex;justify-content:center}.sidebar{position:absolute;top:0;left:20px;width:380px;height:640px;background:#24242a;overflow:hidden;border-radius:16px}</style>`);
await writeFile(path.join(cache,'main.js'),`import {mount} from 'svelte';import Fixture from './Fixture.svelte';window.__initial=${JSON.stringify(fixtures.activeState())};window.__playback=${JSON.stringify(fixtures.jamPlayback({currentTrack:{videoId:'vid1',title:'Blinding Lights',artists:'The Weeknd',album:'After Hours',thumbnail:null,artistId:null,albumId:null},duration:200,position:60}))};mount(Fixture,{target:document.getElementById('app')});`);
await writeFile(path.join(cache,'index.html'),'<div id="app"></div><script type="module" src="/main.js"></script>');
const mockFile=path.join(cache,'tauri-mock.js');
await writeFile(mockFile,'export const invoke = async cmd => cmd === "get_animated_artwork_runtime_state" ? ({ visible: true, minimized: false, cloaked: false, powerSaver: false, memoryPressure: false }) : null; export const listen = async () => () => {}; export const convertFileSrc = path => path; export const getCurrentWindow = () => ({ isFullscreen: async () => false, setFullscreen: async () => {} });');
const server=await createServer({configFile:false,root:cache,publicDir:path.join(root,'static'),plugins:[svelte()],optimizeDeps:{entries:[path.join(cache,'index.html')]},resolve:{alias:{$lib:path.join(root,'src/lib'),'@tauri-apps/api/core':mockFile,'@tauri-apps/api/event':mockFile,'@tauri-apps/api/window':mockFile}},server:{watch:null,host:'127.0.0.1',port:0,fs:{allow:[root]}},logLevel:'error'});
await server.listen();
const browser=spawn(process.env.SIDEB_BROWSER??'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless=new','--edge-skip-compat-layer-relaunch','--no-first-run','--no-default-browser-check','--disable-extensions','--disable-background-networking','--disable-background-timer-throttling','--hide-scrollbars','--remote-debugging-port=0',`--user-data-dir=${path.join(cache,'browser-'+Date.now())}`,'about:blank'],{windowsHide:true,stdio:['ignore','ignore','pipe']});
let stderr='',ws;browser.stderr.on('data',x=>stderr+=x);
try{
 for(let i=0;i<100&&!stderr.includes('DevTools listening on');i++)await new Promise(r=>setTimeout(r,100));
 const endpoint=stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/)?.[1];assert.ok(endpoint,stderr);
 const pages=await(await fetch(new URL('/json/list',endpoint.replace('ws:','http:')))).json();
 ws=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);await new Promise(r=>ws.addEventListener('open',r,{once:true}));
 let id=0;const pending=new Map(),errors=[];
 ws.addEventListener('message',event=>{const m=JSON.parse(event.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result)}else if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description??m.params.exceptionDetails.text)});
 const send=(method,params={})=>new Promise((resolve,reject)=>{const key=++id,timer=setTimeout(()=>reject(Error(method+' timeout')),20000);pending.set(key,{resolve:v=>{clearTimeout(timer);resolve(v)},reject:e=>{clearTimeout(timer);reject(e)}});ws.send(JSON.stringify({id:key,method,params}))});
 const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});assert.ok(!r.exceptionDetails,JSON.stringify(r.exceptionDetails));return r.result.value};
 const settle=(ms=250)=>new Promise(resolve=>setTimeout(resolve,ms));
 await send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});await send('Emulation.setFocusEmulationEnabled',{enabled:true});
 await send('Runtime.enable');await send('Page.navigate',{url:server.resolvedUrls.local[0]});
 for(let i=0;i<600;i++){if(await evaluate('!!window.lab')){await settle(150);if(await evaluate('!!window.lab'))break;}if(i===150||i===300||i===450)await send('Page.reload',{ignoreCache:true});await settle(100)}
 const hasLab=await evaluate('!!window.lab');
 if(!hasLab){const diag=await evaluate('({href:location.href,ready:document.readyState,html:document.body?.innerHTML?.slice(0,300)})');assert.ok(hasLab,`window.lab missing: ${JSON.stringify({errors,diag})}`)}
 await evaluate('document.fonts.ready');
 const out=[];
 const shot=async(name,clip)=>{await settle();const r=await send('Page.captureScreenshot',{format:'png',...(clip?{clip:{...clip,scale:1}}:{})});const file=path.join(shots,name+'.png');await writeFile(file,Buffer.from(r.data,'base64'));out.push(file)};
 const viewport=(width,height,dpr=2)=>send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:dpr,mobile:false});
 const rectOf=sel=>evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(sel)});if(!e)return null;const r=e.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height,right:r.right,bottom:r.bottom}})()`);
 const clipOf=async(sel,pad=12)=>{const r=await rectOf(sel);return {x:Math.max(0,r.x-pad),y:Math.max(0,r.y-pad),width:r.width+pad*2,height:r.height+pad*2}};
 const lab=code=>evaluate(`(async()=>{${code};await new Promise(r=>setTimeout(r,120))})()`);

 // Panel in each phase.
 await viewport(420,900);
 const idle={...fixtures.emptyState()},signedOut={...idle,runtime:{pluginAvailable:true,running:false,signedIn:false}},joining={...idle,phase:'joining'};
 const active=fixtures.activeState({sync:{status:'locked',offsetMs:6,manualOffsetMs:0},log:['join: ok','state: Blinding Lights','sync: locked']});
 active.current={...active.current,title:'Blinding Lights',artists:'The Weeknd',matched:{...active.current.matched,title:'Blinding Lights',artists:'The Weeknd',durationSecs:201}};
 for(const [name,state,extra] of [['panel-signed-out',signedOut],['panel-idle-join',idle],['panel-joining',joining],['panel-active',active],['panel-active-searching',{...active,current:fixtures.searching(1)}],['panel-active-nomatch',{...active,current:fixtures.unavailable(1),paused:false}],['panel-active-nocontrol',{...active,canControl:false}],['panel-error',{...idle,phase:'error',messageKey:'jam.error.linkInvalid'}],['panel-ended',{...idle,phase:'ended',messageKey:'jam.ended.host'}]]){
  await lab(`lab.mode('panel');lab.set(${JSON.stringify({...fixtures.emptyState(),...state})})`);await shot(name,await clipOf('.surface'));
 }
 await lab(`lab.set(${JSON.stringify(active)})`);
 await evaluate(`document.querySelector('[data-jam-choose]').click()`);await settle(400);await shot('panel-active-versions',await clipOf('.surface'));
 await evaluate(`document.querySelector('[data-jam-choose]').click()`);
 await evaluate(`document.querySelector('[data-jam-more]').click()`);await settle();await evaluate(`document.querySelector('[data-jam-menu="debug"]').click()`);await settle();await evaluate(`document.querySelector('[data-jam-more]').click()`);await settle();await evaluate(`document.querySelector('[data-jam-menu="sync"]').click()`);await settle();await shot('panel-active-debug-sync',await clipOf('.surface'));
 await evaluate(`document.querySelector('[data-jam-more]').click()`);await settle();await shot('panel-menu-open',await clipOf('.surface'));await evaluate(`document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))`);

 // Queue rows.
 await viewport(560,480);await lab(`lab.set(${JSON.stringify(active)});lab.mode('queue')`);await shot('queue-rows',await clipOf('.surface',4));
 await viewport(420,300);await lab(`lab.mode('upcoming')`);await shot('sidebar-upcoming-jam',await clipOf('.surface',4));

 // Toasts + exit dialog.
 await viewport(720,420);
 await lab(`lab.mode('toasts');lab.set({toasts:[{id:3,key:'jam.notice.localOnly'},{id:2,key:'jam.error.connection'},{id:1,key:'jam.action.added',values:{title:'Blinding Lights'}}],pendingExit:null})`);await shot('toasts');
 await lab(`lab.set({toasts:[],pendingExit:{reasonKey:'jam.exit.playOther'}})`);await shot('exit-dialog');
 await lab(`lab.set({pendingExit:null})`);

 // Player bar with the Connections button, idle and in a Jam, flyout open.
 await viewport(1000,700,2);await lab(`lab.mode('bar');lab.set(${JSON.stringify(fixtures.emptyState())})`);
 const barClip={x:60,y:580,width:880,height:100};
 await shot('bar-idle',barClip);
 await lab(`lab.set(${JSON.stringify(active)})`);await shot('bar-jam',barClip);
 const cb=await rectOf('.connections-button'),badge=await rectOf('[data-host-badge]');
 assert.ok(cb&&badge&&badge.x>cb.x+cb.width/2&&badge.y>cb.y+cb.height/2,'the host badge sits on the bottom-right corner of the Connections glyph');
 await evaluate(`document.querySelector('.connections-button').click()`);await settle(400);
 const fly=await rectOf('.flyout');assert.ok(fly&&fly.bottom<=cb.y-6&&fly.right<=1000&&fly.x>=0&&fly.y>=0,'the flyout opens above the button, inside the window '+JSON.stringify({fly,cb}));
 await shot('bar-jam-flyout',{x:500,y:0,width:500,height:700});
 await evaluate(`document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))`);

 // Fullscreen: marker centred ~10 px above the cover, outside it; the cover does not move or resize.
 await viewport(1280,760,1);
 await lab(`lab.mode('fullscreen');lab.set(${JSON.stringify(fixtures.emptyState())})`);await settle(600);
 const coverIdle=await rectOf('button.artwork');assert.equal(await rectOf('[data-jam-marker]'),null,'no marker outside a Jam');
 assert.equal(await rectOf('#fullscreen-tab-jam'),null,'no Jam tab in fullscreen until a Jam is live');
 assert.ok(await rectOf('#fullscreen-tab-related'),'related tab stays visible outside a Jam');
 await shot('fullscreen-idle');
 await lab(`lab.set(${JSON.stringify(active)})`);await settle(600);
 const cover=await rectOf('button.artwork'),marker=await rectOf('[data-jam-marker] .badge');
 assert.deepEqual(cover,coverIdle,'starting a Jam never moves or resizes the artwork');
 assert.ok(marker.bottom<=cover.y-9.5&&marker.bottom>=cover.y-10.5,'the marker ends 10 px above the cover: '+JSON.stringify({marker,cover}));
 assert.ok(Math.abs((marker.x+marker.width/2)-(cover.x+cover.width/2))<1.5,'the marker is centred on the cover');assert.ok(marker.y>=0&&marker.right<=cover.right+1&&marker.x>=cover.x-1,'and fully visible, within the cover column');
 assert.ok(await rectOf('#fullscreen-tab-jam'),'Jam tab appears once a Jam is live');
 assert.ok(await rectOf('#fullscreen-tab-related'),'related tab stays visible while a Jam is live');
 await shot('fullscreen-jam');
 await evaluate(`document.querySelector('#fullscreen-tab-related').click()`);await settle(400);
 assert.equal(await evaluate(`document.querySelector('#fullscreen-tab-related')?.getAttribute('aria-selected')`),'true','related tab is selectable while a Jam is live');
 assert.ok(await evaluate(`!!document.querySelector('#fullscreen-panel .recommendations')`),'related panel mounts while a Jam is live');
 await evaluate(`document.querySelector('[data-jam-marker] .badge').click()`);await settle(600);
 assert.ok(await evaluate(`!!document.querySelector('#fullscreen-panel [data-jam-panel]')`),'the marker opens the Jam tab');await shot('fullscreen-jam-tab');
 await viewport(900,620,1);await settle(400);
 const smallCover=await rectOf('button.artwork'),smallMarker=await rectOf('[data-jam-marker] .badge');assert.ok(smallMarker.y>=0&&smallMarker.bottom<=smallCover.y-9.5,'the marker also fits the smallest layouts '+JSON.stringify({smallMarker,smallCover}));await shot('fullscreen-jam-small');
 await lab(`lab.set(${JSON.stringify({...fixtures.emptyState(),phase:'ended',messageKey:'jam.ended.host'})})`);await settle(400);
 assert.equal(await rectOf('#fullscreen-tab-jam'),null,'Jam tab hides again when the Jam ends');
 assert.equal(await evaluate(`document.querySelector('#fullscreen-tab-queue')?.getAttribute('aria-selected')`),'true','leaving or ending a Jam while on the Jam tab falls back to queue');
 assert.equal(await evaluate(`!!document.querySelector('#fullscreen-panel [data-jam-panel]')`),false,'Jam panel unmounts when the Jam ends');

 // Playback sidebar hero: compact marker over the cover's top edge.
 await viewport(1000,720,2);await lab(`lab.mode('sidebar');lab.set(${JSON.stringify(active)})`);await settle(500);
 const hero=await rectOf('.poster'),side=await rectOf('[data-jam-marker] .badge');
 assert.ok(hero&&side&&side.y>=hero.y&&side.y<=hero.y+16&&Math.abs((side.x+side.width/2)-(hero.x+hero.width/2))<1.5,'the sidebar marker overlays the top edge of the cover, centred '+JSON.stringify({hero,side}));
 await shot('sidebar-artwork-jam',{x:0,y:0,width:440,height:720});
 await evaluate(`document.querySelector('[data-jam-marker] .badge').click()`);await settle(400);await shot('sidebar-jam-flyout',{x:0,y:0,width:440,height:720});

 console.log(JSON.stringify({ok:true,shots:out,errors}));
}finally{ws?.close();browser.kill();await server.close()}

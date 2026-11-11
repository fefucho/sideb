// Real Svelte + Chromium layout of PlaybackDock, PlaybackSidebar and the shared PlayerBar footer.
// Synthetic playback only: no account, audio or Tauri. It proves geometry/inert/progress behavior of the
// DOM, not WebView2 rendering, frame rate or the smoothness of the animation.
import assert from 'node:assert/strict';
import { writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { createServer } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

const root = fileURLToPath(new URL('../', import.meta.url)), cache = path.join(root, '.cache/playback-sidebar-browser');
await mkdir(cache, { recursive: true });
await writeFile(path.join(cache, 'Fixture.svelte'), String.raw`<script>
import '$lib/styles/fonts.css';import '$lib/styles/tokens.css';
import {Tween} from 'svelte/motion';import {untrack,onMount} from 'svelte';
import PlayerBar from '$lib/components/player/PlayerBar.svelte';
import PlaybackDock from '$lib/components/playback-sidebar/PlaybackDock.svelte';
import PlaybackSidebar from '$lib/components/playback-sidebar/PlaybackSidebar.svelte';
import {initialPresentation,toggleSidebar,closeSidebar,setFullscreen,selectSidebarPanel,dampedEase,syncProgress,contentReserve,footerHeight,panelHeight,showsUpcoming,barWidth} from '$lib/player/playbackPresentation';
import {emptyLyricsState} from '$lib/player/lyrics';import {emptyRecommendationsSnapshot} from '$lib/player/recommendations';import {setContext} from 'svelte';import {FEATURED_ARTIST_CONTEXT,featuredClauses} from '$lib/featured/artists';
setContext(FEATURED_ARTIST_CONTEXT,{scopeRevision:1,title:async track=>featuredClauses(track.title).map(c=>({...c,id:'guest'})),open:async(track,name,open)=>open('guest'),search:()=>{},candidates:async()=>[],choose:()=>{},clearChoice:()=>{}});
let presentation=$state(initialPresentation()),reduced=$state(false),width=$state(380),viewport=$state(window.innerWidth),lyricsMode=$state('synced');
const calls=[];
let playback=$state({currentTrack:{videoId:'fixture',title:'A fairly long fixture title that has to fit inside the panel',artists:'Fixture Artist',artistId:'artist',album:'Fixture Album',albumId:'album',thumbnail:null,contentRating:null},isPlaying:true,isLoading:false,isEnded:false,isShuffle:false,isRepeat:false,position:30,duration:240,volume:70,error:null,generation:1,queue:{items:[{entryId:'a',videoId:'fixture'},{entryId:'b',videoId:'b'}],currentIndex:0}});
const progress=new Tween(0,{easing:dampedEase});
$effect(()=>{const mode=presentation.mode,r=reduced;untrack(()=>syncProgress(progress,mode,r));});
const sidebarOpen=$derived(presentation.mode==='sidebar');
const mounted=$derived(presentation.mode==='sidebar'||(presentation.mode==='bar'&&progress.current>0.001));
const reserve=$derived(contentReserve({windowWidth:viewport,leftReserve:253,presented:sidebarOpen,width}));
let dock=$state();
onMount(()=>{const m=matchMedia('(prefers-reduced-motion: reduce)');const sync=()=>reduced=m.matches;sync();m.addEventListener('change',sync);return()=>m.removeEventListener('change',sync)});
window.lab={
 toggle:panel=>{const was=sidebarOpen;presentation=toggleSidebar(presentation,panel);if(was&&presentation.mode!=='sidebar')queueMicrotask(()=>dock?.focusTrigger())},
 close:()=>presentation=closeSidebar(presentation),fullscreen:open=>presentation=setFullscreen(presentation,open,'lyrics'),select:p=>presentation=selectSidebarPanel(presentation,p),
 width:v=>width=v,patch:v=>playback={...playback,...v},viewport:()=>viewport=window.innerWidth,
 state:()=>({mode:presentation.mode,origin:presentation.origin,panel:presentation.sidebarPanel,progress:progress.current,target:progress.target,mounted,reserve,reduced,
  expectedFooter:footerHeight(panelHeight(window.innerHeight,32),presentation.sidebarPanel,false,width),expectedUpcoming:showsUpcoming(panelHeight(window.innerHeight,32),presentation.sidebarPanel,false),barWidth:barWidth(window.innerWidth-253)}),calls};
</script>
<div class="frame" style="--titlebar-height:32px;--sidebar-width:253px">
 <div class="titlebar"><span class="controls">window controls</span></div>
 <div class="content" style:margin-right={reserve?reserve+'px':undefined}>page content</div>
 <PlaybackDock bind:this={dock} mode={presentation.mode} progress={progress.current} {reduced} onToggleSidebar={()=>window.lab.toggle()}>
  <PlayerBar {playback} fullscreenOpen={false} loggedIn onTogglePlayback={()=>calls.push('play-bar')} onRetryPlayback={()=>{}} onPrevious={()=>calls.push('prev-bar')} onNext={()=>calls.push('next-bar')} onSeek={()=>{}} onVolumeChange={()=>{}} onSetShuffle={async()=>{}} onSetRepeat={async()=>{}} onToggleFullscreen={()=>{}} onSelectPanel={p=>calls.push('bar-'+p)} onOpenMenu={()=>{}}/>
 </PlaybackDock>
 {#if mounted}
  <PlaybackSidebar session={1} {playback} panel={presentation.sidebarPanel} onSelectPanel={p=>presentation=selectSidebarPanel(presentation,p)} {lyricsMode} onLyricsMode={m=>lyricsMode=m} progress={progress.current} {reduced} {width}
   interactive={sidebarOpen} onClose={()=>window.lab.toggle()} onExpand={()=>window.lab.fullscreen(true)} controls={sidebarControls} lyricsState={emptyLyricsState()} onSelectQueue={()=>calls.push('select-queue')} metadataProps={{loggedIn:true,onToggleLike:()=>{},onOpenMenu:()=>{}}} recommendationsProps={{snapshot:emptyRecommendationsSnapshot(),onRequestLoad:()=>{},onRefresh:()=>{},onPlaySong:()=>{},onTogglePlayback:()=>{},onAddToQueue:()=>{}}}>
   {#snippet queueBody()}<div class="queue-fake"><div class="queue-fake-list"><div style="height:4000px">queue host</div></div></div>{/snippet}
   {#snippet lyricsBody(mode)}<div class="host">lyrics host {mode}</div>{/snippet}
  </PlaybackSidebar>
 {/if}
</div>
{#snippet sidebarControls(lead,tail,spacing)}
 <PlayerBar variant="sidebar" sidebarLead={lead} sidebarTail={tail} sidebarSpacing={spacing} {playback} fullscreenOpen={false} loggedIn onTogglePlayback={()=>calls.push('play-sidebar')} onRetryPlayback={()=>{}} onPrevious={()=>calls.push('prev-sidebar')} onNext={()=>calls.push('next-sidebar')} onSeek={()=>{}} onVolumeChange={v=>calls.push(['volume',v])} onSetShuffle={async()=>{}} onSetRepeat={async()=>{}} onToggleFullscreen={()=>{}} onOpenMenu={()=>{}}/>
{/snippet}
<style>/* Same layout contract as QueuePanel: a flex column whose list is the scroller. */.queue-fake{display:flex;flex:1;flex-direction:column;width:100%;min-width:0;min-height:0;overflow:hidden}.queue-fake-list{flex:1;min-height:0;overflow-y:auto}:global(body){margin:0;background:#19191c;color:white;font-family:var(--sideb-font-family,Inter,sans-serif);overflow:hidden}.frame{position:fixed;inset:0}.titlebar{position:fixed;z-index:200;top:0;left:253px;right:0;height:32px}.controls{position:absolute;right:0;top:0;width:138px;height:32px}.content{position:absolute;top:32px;left:253px;right:0;bottom:0}.host{flex:1}</style>`);
await writeFile(path.join(cache, 'main.js'), "import {mount} from 'svelte';import Fixture from './Fixture.svelte';mount(Fixture,{target:document.getElementById('app')});");
await writeFile(path.join(cache, 'index.html'), '<div id="app"></div><script type="module" src="/main.js"></script>');
const server = await createServer({ configFile: false, root: cache, publicDir: path.join(root, 'static'), plugins: [svelte()], resolve: { alias: { $lib: path.join(root, 'src/lib') } }, server: { host: '127.0.0.1', port: 0, watch: null, fs: { allow: [root] } }, logLevel: 'error' });
await server.listen();
const exe = process.env.SIDEB_BROWSER ?? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser = spawn(exe, ['--headless=new', '--edge-skip-compat-layer-relaunch', '--no-first-run', '--disable-extensions', '--remote-debugging-port=0', `--user-data-dir=${path.join(cache, 'browser-' + Date.now())}`, 'about:blank'], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
let stderr = '', ws;
browser.stderr.on('data', x => stderr += x);
try {
  for (let i = 0; i < 100 && !stderr.includes('DevTools listening on'); i++) await new Promise(r => setTimeout(r, 100));
  const endpoint = stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/)?.[1];
  assert.ok(endpoint, stderr);
  const pages = await (await fetch(new URL('/json/list', endpoint.replace('ws:', 'http:')))).json();
  ws = new WebSocket(pages.find(p => p.type === 'page').webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener('open', r, { once: true }));
  let id = 0;
  const pending = new Map(), errors = [], evidence = [];
  ws.addEventListener('message', event => {
    const m = JSON.parse(event.data);
    if (m.id) { const p = pending.get(m.id); pending.delete(m.id); m.error ? p.reject(m.error) : p.resolve(m.result); }
    else if (m.method === 'Runtime.exceptionThrown') errors.push(m.params.exceptionDetails.exception?.description ?? m.params.exceptionDetails.text);
  });
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const key = ++id, timer = setTimeout(() => reject(Error(method + ' timeout')), 20000);
    pending.set(key, { resolve: v => { clearTimeout(timer); resolve(v); }, reject: e => { clearTimeout(timer); reject(e); } });
    ws.send(JSON.stringify({ id: key, method, params }));
  });
  const evaluate = async expression => { const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }); assert.ok(!r.exceptionDetails, JSON.stringify(r.exceptionDetails)); return r.result.value; };
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const settle = () => sleep(700);
  const state = () => evaluate('lab.state()');
  const rect = selector => evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});if(!e)return null;const r=e.getBoundingClientRect();return {x:r.x,y:r.y,right:r.right,bottom:r.bottom,width:r.width,height:r.height,scrollWidth:e.scrollWidth,clientWidth:e.clientWidth}})()`);
  const near = (a, b, message, tolerance = 0.75) => assert.ok(Math.abs(a - b) <= tolerance, `${message}: ${a} vs ${b}`);
  const interactivity = () => evaluate(`(()=>({dockInert:document.querySelector('.player-dock').inert,panelPresent:!!document.getElementById('playback-sidebar'),panelInert:document.getElementById('playback-sidebar')?.inert??null}))()`);
  const assertSingleDestination = (mode, snapshot, label) => {
    assert.equal(snapshot.dockInert, mode === 'sidebar', `${label}: bar inert exactly while the panel owns the controls`);
    if (snapshot.panelPresent) assert.equal(snapshot.panelInert, mode !== 'sidebar', `${label}: panel inert unless it owns the controls`);
    if (mode === 'sidebar') assert.equal(snapshot.panelPresent && !snapshot.panelInert && snapshot.dockInert, true, `${label}: one live destination`);
  };

  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'no-preference' }] });
  await send('Emulation.setFocusEmulationEnabled', { enabled: true });
  await send('Runtime.enable'); await send('Page.navigate', { url: server.resolvedUrls.local[0] });
  for (let i = 0; i < 300; i++) { if (await evaluate('!!window.lab')) break; await sleep(100); }
  assert.ok(await evaluate('!!window.lab'), errors.join('\n'));
  await evaluate('document.fonts.ready');

  // 1. Closed: bar centered in the content column, trigger at the trailing margin, no overlap, no panel.
  for (const [vw, vh] of [[960, 640], [1100, 700], [1440, 900]]) {
    await send('Emulation.setDeviceMetricsOverride', { width: vw, height: vh, deviceScaleFactor: 1, mobile: false });
    await evaluate('lab.viewport()'); await sleep(200);
    const s = await state(), bar = await rect('.player-bar'), trigger = await rect('.sidebar-trigger'), dock = await rect('.player-dock');
    assert.equal(s.mounted, false); assert.equal(await evaluate("!!document.getElementById('playback-sidebar')"), false);
    near(bar.width, s.barWidth, `${vw}: bar width follows content - 160`);
    near(bar.x + bar.width / 2, 253 + (vw - 253) / 2, `${vw}: bar centered in content column`);
    near(trigger.width, 44, 'trigger width'); near(trigger.height, 44, 'trigger height');
    near(trigger.right, vw - 20, 'trigger trailing margin'); near(trigger.y + trigger.height / 2, bar.y + bar.height / 2, 'trigger centered on the bar');
    assert.ok(trigger.x - bar.right >= 15.5, `${vw}: bar and trigger never overlap (${trigger.x - bar.right})`);
    near(dock.bottom, vh - 20, 'dock bottom margin');
    // The 74 px bar must still lay its three groups out without overlap at its narrowest.
    const groups = await evaluate(`(()=>{const q=s=>document.querySelector('.player-bar '+s).getBoundingClientRect();const b=document.querySelector('.player-bar').getBoundingClientRect();const t=q('.transport'),k=q('.track'),e=q('.end-controls');return {t:[t.left-b.left,t.right-b.left],k:[k.left-b.left,k.right-b.left],e:[e.left-b.left,e.right-b.left],w:b.width}})()`);
    assert.ok(groups.t[1] <= groups.k[0] + 0.5 && groups.k[1] <= groups.e[0] + 0.5 && groups.e[1] <= groups.w + 0.5, `${vw}: bar groups do not overlap ${JSON.stringify(groups)}`);
    evidence.push({ closed: vw, bar: bar.width, groups });
  }

  // 2. Panel geometry at 350 / 380 / 420 and several heights; both lateral sections that host heavy content.
  for (const [vw, vh] of [[1280, 640], [1280, 760], [1280, 1000]]) {
    for (const w of [350, 380, 420]) {
      await send('Emulation.setDeviceMetricsOverride', { width: vw, height: vh, deviceScaleFactor: 1, mobile: false });
      await evaluate(`lab.close();lab.width(${w});lab.viewport();lab.select('artwork')`); await settle();
      assert.equal((await state()).mode, 'bar');
      await evaluate('lab.toggle()');
      assertSingleDestination('sidebar', await interactivity(), `${vw}x${vh}@${w} first frame`);
      await settle();
      const s = await state();
      assert.equal(s.mode, 'sidebar'); near(s.progress, 1, 'progress reaches the panel', 0.001);
      assertSingleDestination('sidebar', await interactivity(), `${vw}x${vh}@${w} settled`);
      const panel = await rect('#playback-sidebar'), header = await rect('.playback-sidebar .header'), footer = await rect('.playback-sidebar .footer');
      near(panel.width, w, 'panel width'); near(panel.y, 38, 'panel starts below the 32px titlebar + 6'); near(panel.right, vw - 6, 'panel trailing inset 6'); near(panel.bottom, vh - 6, 'panel bottom inset 6');
      assert.ok(panel.y >= 32, 'window controls (titlebar) stay uncovered');
      near(header.height, 58, 'header height'); near(footer.height, s.expectedFooter, 'footer height follows the shared formula', 1);
      near(footer.bottom, panel.bottom, 'footer pinned to the bottom');
      const controls = await evaluate(`(()=>{const p=document.getElementById('playback-sidebar').getBoundingClientRect(),r=s=>document.querySelector('.playback-sidebar '+s).getBoundingClientRect();const items=[...document.querySelectorAll('.playback-sidebar .side-transport > *')].map(e=>e.getBoundingClientRect());const play=r('.play-toggle'),vol=r('.side-volume'),prog=r('.side-progress'),seg=document.querySelector('.playback-sidebar .segments');const hdr=document.querySelector('.playback-sidebar .header');return {p:{l:p.left,r:p.right,t:p.top,b:p.bottom},left:Math.min(...items.map(i=>i.left)),right:Math.max(...items.map(i=>i.right)),playSize:[play.width,play.height],volBottom:vol.bottom,volRight:vol.right,volLeft:vol.left,progTop:prog.top,playTop:play.top,playBottom:play.bottom,hdrOverflow:hdr.scrollWidth-hdr.clientWidth,segOverflow:seg.scrollWidth-seg.clientWidth,docOverflow:document.documentElement.scrollWidth-document.documentElement.clientWidth,panelOverflow:document.getElementById('playback-sidebar').scrollWidth-document.getElementById('playback-sidebar').clientWidth}})()`);
      assert.ok(controls.left >= controls.p.l + 19 && controls.right <= controls.p.r - 19, `${vw}x${vh}@${w}: transport inside 20px padding ${JSON.stringify(controls)}`);
      assert.deepEqual(controls.playSize, [78, 78]);
      assert.ok(controls.progTop < controls.playTop && controls.playBottom <= controls.volBottom, 'progress, transport and volume stack top to bottom');
      // The free height of the footer goes under the transport (lyrics sample / queue), never between the metadata and the progress.
      if (s.panel === 'artwork') near(controls.progTop - footer.y, 12 + 10, `${vw}x${vh}@${w}: progress stays glued to the top of the footer`, 1.5);
      assert.ok(controls.volBottom <= controls.p.b && controls.volRight <= controls.p.r - 19 && controls.volLeft >= controls.p.l + 19, 'volume row inside the panel');
      assert.ok(controls.hdrOverflow <= 0 && controls.segOverflow <= 0 && controls.docOverflow <= 0 && controls.panelOverflow <= 0, `${vw}x${vh}@${w}: no horizontal overflow ${JSON.stringify(controls)}`);
      assert.ok(panel.height - header.height - footer.height >= 0 || s.panel === 'artwork', 'body keeps its height');
      assert.equal(await evaluate("document.querySelectorAll('.playback-sidebar [aria-label]').length>0"), true);
      // Reserve vs overlay follows the real thresholds.
      const reserved = w + 12, fits = vw - 253 - reserved >= 480;
      assert.equal(s.reserve, fits ? reserved : 0, `${vw}@${w}: reserve ${fits ? 'applies' : 'falls back to overlay'}`);
      const contentRight = (await rect('.content')).right;
      near(contentRight, vw - s.reserve, 'page content gives room only when reserved');
      assert.equal(await evaluate('Boolean(document.querySelector(".playback-sidebar .side-tail"))'), s.expectedUpcoming, 'up-next only on tall artwork panels');
      evidence.push({ vw, vh, w, footer: footer.height, reserve: s.reserve });
    }
  }

  // 3. Duplicated controls: only one live destination; the panel footer drives the same actions.
  await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 760, deviceScaleFactor: 1, mobile: false });
  await evaluate('lab.viewport();lab.width(380)'); await settle();
  await evaluate("document.querySelector('.playback-sidebar .play-toggle').click();document.querySelectorAll('.playback-sidebar .side-transport .skip')[1].click()");
  const side = await evaluate('lab.calls.slice(-2)');
  assert.deepEqual(side, ['play-sidebar', 'next-sidebar']);
  assert.equal(await evaluate("document.querySelector('.player-dock').getAttribute('aria-hidden')"), 'true');
  assert.ok(await evaluate("document.activeElement?.closest('#playback-sidebar')!==null"), 'focus moved into the panel when it opened');

  // 4. Rapid open/close: never both live, ends where the last request says, panel unmounted when closed.
  await evaluate('lab.close()'); await settle();
  for (let i = 0; i < 9; i++) {
    await evaluate('lab.toggle()'); await sleep(30);
    const s = await state(); assertSingleDestination(s.mode, await interactivity(), `rapid ${i}`);
  }
  await settle();
  let s = await state(); assert.equal(s.mode, 'sidebar'); near(s.progress, 1, 'rapid sequence settles on the last request', 0.001);
  await evaluate('lab.toggle()'); await settle();
  s = await state(); assert.equal(s.mode, 'bar'); assert.equal(s.mounted, false); near(s.progress, 0, 'closed', 0.001);
  assert.equal(await evaluate("!!document.getElementById('playback-sidebar')"), false, 'panel unmounted after closing');
  const closedDock = await evaluate("(()=>{const d=document.querySelector('.player-dock');return {opacity:getComputedStyle(d).opacity,transform:getComputedStyle(d).transform,inert:d.inert}})()");
  assert.deepEqual(closedDock, { opacity: '1', transform: 'none', inert: false });
  assert.ok(await evaluate("document.activeElement===document.querySelector('.sidebar-trigger')"), 'focus returns to the trigger on close');

  // 5. Reversal retraces from where the animation is, never from the endpoint.
  await evaluate('lab.toggle()'); await sleep(140);
  const mid = (await state()).progress; assert.ok(mid > 0.05 && mid < 0.95, `captured mid-flight (${mid})`);
  await evaluate('lab.toggle()');
  const samples = [];
  for (let i = 0; i < 40; i++) { samples.push((await state()).progress); await sleep(20); }
  assert.ok(samples[0] <= mid + 0.08, `reversal starts at the animated position (${samples[0]} vs ${mid})`);
  for (let i = 1; i < samples.length; i++) assert.ok(samples[i] <= samples[i - 1] + 1e-9, 'progress decreases monotonically after reversal');
  await settle(); near((await state()).progress, 0, 'ends at the bar', 0.001);
  assert.equal(await evaluate("!!document.getElementById('playback-sidebar')"), false);

  // 6. Both surfaces cross-fade over the same progress: mid-flight the bar is partly retired while the panel is entering.
  await evaluate('lab.toggle()'); await sleep(120);
  const crossing = await evaluate(`(()=>{const d=getComputedStyle(document.querySelector('.player-dock')),p=getComputedStyle(document.getElementById('playback-sidebar'));return {dock:[+d.opacity,d.transform],panel:[+p.opacity,p.transform]}})()`);
  assert.ok(crossing.dock[0] < 1 && crossing.panel[0] > 0 && crossing.panel[0] <= 1, JSON.stringify(crossing));
  assert.notEqual(crossing.panel[1], 'none'); assert.notEqual(crossing.dock[1], 'none');
  await settle(); await evaluate('lab.close()'); await settle();

  // 7. Fullscreen origin and return.
  await evaluate("lab.toggle('queue')"); await settle();
  // The queue body is bounded by the panel: a long queue scrolls inside it instead of being clipped.
  const queue = await evaluate("(()=>{const l=document.querySelector('.queue-fake-list'),b=document.getElementById('playback-sidebar-body');if(!l)return null;l.scrollTop=300;return {client:l.clientHeight,scroll:l.scrollHeight,top:l.scrollTop,body:b.clientHeight}})()");
  assert.ok(queue && queue.client > 0 && queue.client <= queue.body && queue.scroll > queue.client && queue.top === 300, 'the queue list scrolls inside the panel body: ' + JSON.stringify(queue));
  await evaluate('lab.fullscreen(true)'); await sleep(50);
  s = await state(); assert.equal(s.mode, 'fullscreen'); assert.equal(await evaluate("!!document.getElementById('playback-sidebar')"), false, 'single host: the panel is gone while fullscreen is open');
  assert.equal((await interactivity()).dockInert, false);
  await evaluate('lab.fullscreen(false)'); await settle();
  s = await state(); assert.deepEqual([s.mode, s.panel], ['sidebar', 'lyrics']); assert.equal(s.mounted, true);
  await evaluate('lab.close();lab.fullscreen(true)'); await evaluate('lab.fullscreen(false)'); await settle();
  assert.equal((await state()).mode, 'bar', 'fullscreen opened from the bar collapses to the bar');

  // 8. Reduce Motion: pure cross-fade, no translation or scale on either surface.
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] }); await sleep(200);
  assert.equal((await state()).reduced, true);
  await evaluate('lab.toggle()'); await sleep(60);
  const reducedMid = await evaluate(`(()=>{const d=getComputedStyle(document.querySelector('.player-dock')),p=getComputedStyle(document.getElementById('playback-sidebar'));return {dock:[+d.opacity,d.transform],panel:[+p.opacity,p.transform]}})()`);
  assert.equal(reducedMid.dock[1], 'none'); assert.equal(reducedMid.panel[1], 'none');
  await settle();
  near((await state()).progress, 1, 'reduced motion still reaches the panel', 0.001);
  await evaluate('lab.close()'); await settle();

  // 9. Escape-equivalent close path and keyboard reachability of the selector.
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'no-preference' }] }); await sleep(200);
  await evaluate("lab.toggle('lyrics')"); await settle();
  assert.equal(await evaluate("document.querySelectorAll('.playback-sidebar [role=tab]').length"), 3);
  assert.equal(await evaluate("document.querySelector('.playback-sidebar [role=tab][aria-selected=true]').dataset.value"), 'lyrics');
  assert.equal(await evaluate("document.querySelectorAll('.playback-sidebar [role=tab][tabindex=\"0\"]').length"), 1, 'selector is one tab stop');
  assert.deepEqual(errors, []);
  const shot = await send('Page.captureScreenshot', { format: 'png' });
  await writeFile(path.join(cache, 'playback-sidebar.png'), Buffer.from(shot.data, 'base64'));
  await evaluate("lab.select('artwork')"); await settle();
  await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false }); await sleep(600);
  const shot2 = await send('Page.captureScreenshot', { format: 'png' });
  await writeFile(path.join(cache, 'playback-sidebar-artwork.png'), Buffer.from(shot2.data, 'base64'));
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ ok: true, cases: evidence.length, errors }));
} finally { ws?.close(); browser.kill(); await server.close(); }

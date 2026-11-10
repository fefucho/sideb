// Real Svelte/CSS geometry in a standalone file; synthetic songs, no account or audio.
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { build } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
const root = fileURLToPath(new URL('../', import.meta.url));
const cache = path.join(root, '.cache/queue-continuous-browser');
await mkdir(cache, { recursive: true });
await writeFile(path.join(cache, 'Fixture.svelte'), `<script>
import QueuePanel from '$lib/components/fullscreen/QueuePanel.svelte';
import {setLanguage} from '$lib/i18n';
let width=$state(350);
const entry=i=>({entryId:'e'+i,videoId:'v'+i,title:'A very long song title with additional credits to test truncation '+i,artists:'An artist with a long name',album:'A long album name',duration:240});
let playback=$state({generation:1,isPlaying:false,isLoading:false,currentTrack:entry(100),queue:{items:Array.from({length:1000},(_,i)=>entry(i)),currentIndex:100,source:{kind:'playlist',title:'A playlist with a very long name',id:'list'},recommendations:[entry(2000),entry(2001)]}});
const noop=()=>{};
window.lab={width:v=>width=v,language:setLanguage,advance:()=>{const index=playback.queue.currentIndex+1;playback={...playback,generation:playback.generation+1,currentTrack:entry(index),queue:{...playback.queue,currentIndex:index}};},reserve:()=>playback={...playback,queue:{...playback.queue,recommendations:[entry(2000),entry(2001),entry(2002)]}}};
</script><main style:width={width+'px'}><QueuePanel {playback} loggedIn={true} onSelectQueue={noop} onMoveQueue={noop} onToggleLike={noop} onDislike={noop} onRecommendationAction={noop}/></main>
<style>:global(body){margin:0;background:#101223;color:#eee;font-family:system-ui}main{height:520px;display:flex;flex-direction:column}</style>`);
await writeFile(path.join(cache, 'main.js'), `import {mount,tick} from 'svelte';import Fixture from './Fixture.svelte';
// dump-dom virtual time does not consistently drive compositor frames.
window.requestAnimationFrame=callback=>setTimeout(()=>callback(performance.now()),16);window.cancelAnimationFrame=clearTimeout;
mount(Fixture,{target:document.getElementById('app')});
const settle=async()=>{await tick();await new Promise(r=>setTimeout(r,60));};
const check=(value,label)=>{if(!value)throw Error(label)};
(async()=>{const evidence=[];await settle();const list=document.querySelector('.queue-list');
check(!!list,'queue mounted');check(list.scrollTop>0,'opens around current');
for(const language of ['es','en'])for(const width of [320,350,480,600]){lab.language(language);lab.width(width);await settle();
check(list.scrollWidth<=list.clientWidth+1,'horizontal overflow '+width);
check(document.querySelectorAll('.queue-row').length<35,'bounded DOM');
const y=list.scrollTop;list.scrollLeft=20;check(list.scrollLeft===0,'horizontal offset '+width);
list.scrollTop=list.scrollHeight;list.dispatchEvent(new Event("scroll"));await settle();
const row=document.querySelector('.queue-row.proposal');check(!!row,'proposals visible '+JSON.stringify({width,y:list.scrollTop,height:list.scrollHeight,viewport:list.clientHeight,ids:[...document.querySelectorAll("[data-entry-id]")].map(x=>x.dataset.entryId)}));
const bounds=row.getBoundingClientRect();const buttons=[...row.querySelectorAll('.queue-actions button')];
for(const button of buttons){const box=button.getBoundingClientRect();check(box.left>=bounds.left&&box.right<=bounds.right+1,'action inside row');}
check(row.querySelectorAll('.proposal-action').length===1,'one proposal action');
const plus=row.querySelector('.proposal-action'),duration=row.querySelector('.queue-duration');
check(getComputedStyle(plus).opacity==='0'&&getComputedStyle(duration).visibility==='visible','proposal idle shows duration only');
const pending=document.querySelector('[data-entry-id="e999"]');check(!!pending,'pending comparison row');
for(const selector of ['.queue-art','.like-action','.dislike-action','.queue-duration']){
 const a=pending.querySelector(selector).getBoundingClientRect(),b=row.querySelector(selector).getBoundingClientRect();
 check(Math.abs(a.x-b.x)<.1&&Math.abs(a.width-b.width)<.1,'shared columns '+selector);
}
const grip=pending.querySelector('.reorder-handle').getBoundingClientRect(),add=plus.getBoundingClientRect();
check(Math.abs(grip.x-add.x)<.1&&Math.abs(grip.width-add.width)<.1,'plus uses grip slot');
row.querySelector('.queue-select').focus({preventScroll:true});await settle();
check(getComputedStyle(plus).opacity==='1'&&getComputedStyle(duration).visibility==='hidden','focus swaps duration for plus');
document.activeElement.blur();await settle();
check(getComputedStyle(plus).opacity==='0'&&getComputedStyle(duration).visibility==='visible','blur restores duration');

check(!document.querySelector('.previous-toggle'),'no previous category');
evidence.push({language,width,viewport:list.clientWidth,document:list.scrollWidth,rows:document.querySelectorAll('.queue-row').length});
list.scrollTop=y;list.dispatchEvent(new Event("scroll"));await settle();}
list.dispatchEvent(new WheelEvent('wheel',{deltaY:400,bubbles:true}));list.scrollTop=60*48+13;list.dispatchEvent(new Event("scroll"));await settle();
const manual=list.scrollTop;lab.advance();await settle();check(list.scrollTop===manual,'manual viewport survives advance');lab.reserve();await settle();check(list.scrollTop===manual,'manual viewport survives reserve');
document.body.dataset.result='pass';document.getElementById('result').textContent=JSON.stringify(evidence);
})().catch(error=>{document.body.dataset.result='fail';document.getElementById('result').textContent=error.stack});`);
await writeFile(path.join(cache, 'index.html'), '<!doctype html><meta charset="utf-8"><div id="app"></div><pre id="result"></pre><script type="module" src="./main.js"></script>');
await build({ configFile: false, root: cache, base: './', publicDir: false, plugins: [svelte({ configFile: false })], resolve: { alias: { $lib: path.join(root, 'src/lib') } }, logLevel: 'error', build: { outDir: path.join(cache, 'dist'), emptyOutDir: true } });
const browser = process.env.SIDEB_BROWSER ?? (process.platform === 'darwin' ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' : 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe');
const { stdout } = await promisify(execFile)(browser, ['--headless=new', '--no-first-run', '--disable-extensions', '--allow-file-access-from-files', '--virtual-time-budget=5000', '--dump-dom', '--window-size=800,900', '--user-data-dir='+path.join(cache,'browser-'+Date.now()), pathToFileURL(path.join(cache, 'dist/index.html')).href], { timeout: 30000, maxBuffer: 4*1024*1024 });
await writeFile(path.join(cache, 'result.html'), stdout);
const result = stdout.match(/<pre id="result">([\s\S]*?)<\/pre>/)?.[1];
assert.ok(stdout.includes('data-result="pass"'), result ?? 'Fixture did not finish');
console.log('PASS real queue geometry: 320/350/480/600px × ES/EN, controls, bounded DOM, X lock and manual viewport.');
console.log(result);

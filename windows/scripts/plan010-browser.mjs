// Opt-in layout/compositing regression using real components and the current shell CSS.
// Run from windows/: node scripts/plan010-browser.mjs
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {createServer} from 'vite';
import {svelte} from '@sveltejs/vite-plugin-svelte';

const root=fileURLToPath(new URL('../',import.meta.url));
const cache=path.join(root,'.cache/plan010-browser');
await mkdir(cache,{recursive:true});
const shell=await readFile(path.join(root,'src/routes/+page.svelte'),'utf8');
const shellCSS=shell.match(/<style>([\s\S]*?)<\/style>/)[1];
const fixture=String.raw`<script>
import CollectionLayout from '../../scripts/fixtures/CollectionLayout.svelte';
import ExploreView from '$lib/components/explore/ExploreView.svelte';
import SpotlightSearch from '$lib/components/search/SpotlightSearch.svelte';
import TitleBar from '$lib/components/shell/TitleBar.svelte';
import HomeAmbient from '$lib/components/home/HomeAmbient.svelte';
import {emptyExploreData} from '$lib/explore/controller';
import '$lib/styles/tokens.css';
let options=$state({mode:'playlist',width:730,locale:'es',sidebar:230,spotlight:false});
let calls=$state([]);
export function configure(next){options={...options,...next};}
export function snapshot(){return {options,calls};}
const cover='data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="216" height="216"><rect width="216" height="216" fill="white"/></svg>');
const noop=()=>{};
const data=$derived({...emptyExploreData(),route:'discover',items:Array.from({length:30},(_,i)=>({kind:'album',id:'a'+i,title:'Album '+i,subtitle:'Artist',thumbnail:null,duration:null}))});
</script>
<div class="app-frame" class:sidebar-collapsed={options.sidebar===60}>
<HomeAmbient artwork={[cover]} session="fixture" collection active={true}/>
<TitleBar canBack canForward modalOpen={options.spotlight} onBack={()=>calls.push('back')}/>
<div class="sidebar-host" inert={options.spotlight}><aside style:width={options.sidebar+'px'} style:flex-basis={options.sidebar+'px'}><button id="launcher" onclick={()=>options.spotlight=true}>Buscar</button></aside></div>
<div class="content-column"><main class="shell home-shell" class:explore-shell={options.mode==='explore'} inert={options.spotlight}>
{#if options.mode==='explore'}<ExploreView {data} onNavigate={noop} onRefresh={noop} onOpenCard={noop}/>
{:else}<CollectionLayout mode={options.mode} width={options.width} locale={options.locale} artwork={cover} onAction={(...args)=>calls.push(args)}/>{/if}
</main></div>
<div class="player-dock" inert={options.spotlight}><div class="fake-player">Player</div></div>
{#if options.spotlight}<SpotlightSearch preview={{query:'',results:null}} backendReady onQueryChange={noop} onCommit={noop} onDismiss={()=>options.spotlight=false} onSelectCard={noop} onPlaySong={noop}/>{/if}
</div>
<style>__SHELL_CSS__
aside {position:relative;box-sizing:border-box;flex-shrink:0;height:100%;background:#24242a;padding:50px 4px;}
.fake-player {height:64px;background:#25252a;border-radius:16px;width:100%;}
</style>`;
await writeFile(path.join(cache,'Fixture.svelte'),fixture.replace('__SHELL_CSS__',shellCSS));
await writeFile(path.join(cache,'index.html'),'<html><body><div id="app"></div><script type="module" src="/main.js"></script></body></html>');
await writeFile(path.join(cache,'main.js'),"import {mount} from 'svelte';import Fixture from './Fixture.svelte';window.lab=mount(Fixture,{target:document.getElementById('app')});");
const server=await createServer({configFile:false,root:cache,plugins:[svelte({onwarn:(warning,handler)=>{if(!['css_unused_selector'].includes(warning.code))handler(warning);}})],resolve:{alias:{$lib:path.join(root,'src/lib')}},server:{host:'127.0.0.1',port:0,fs:{allow:[root]}},logLevel:'error'});
await server.listen();
const url=server.resolvedUrls.local[0];
console.log('Fixture server: '+url);
const edge=process.env.SIDEB_BROWSER??'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browser=spawn(edge,['--headless=new','--no-first-run','--no-default-browser-check','--disable-gpu','--disable-extensions','--disable-background-networking','--disable-background-timer-throttling','--remote-debugging-port=0',`--user-data-dir=${path.join(cache,'edge-'+Date.now())}`,'about:blank'],{windowsHide:true,stdio:['ignore','ignore','pipe']});
let stderr='';browser.stderr.on('data',chunk=>stderr+=chunk);
let ws;
const results=[];
try {
  for(let i=0;i<100&&!stderr.includes('DevTools listening on');i++)await new Promise(r=>setTimeout(r,100));
  const browserUrl=stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/)?.[1];
  assert.ok(browserUrl,stderr);
  const pages=await (await fetch(new URL('/json/list',browserUrl.replace('ws:','http:')))).json();
  ws=new WebSocket(pages.find(page=>page.type==='page').webSocketDebuggerUrl);
  await new Promise((resolve,reject)=>{ws.addEventListener('open',resolve,{once:true});ws.addEventListener('error',reject,{once:true});});
  let id=0;const pending=new Map();const errors=[];
  ws.addEventListener('message',event=>{const msg=JSON.parse(event.data);if(msg.id){const p=pending.get(msg.id);pending.delete(msg.id);msg.error?p.reject(msg.error):p.resolve(msg.result);}else if(msg.method==='Runtime.exceptionThrown')errors.push(msg.params.exceptionDetails.text+': '+msg.params.exceptionDetails.exception?.description);});
  const send=(method,params={})=>new Promise((resolve,reject)=>{const request=++id;const timer=setTimeout(()=>{pending.delete(request);reject(new Error('CDP timeout: '+method));},20000);pending.set(request,{resolve:value=>{clearTimeout(timer);resolve(value);},reject:error=>{clearTimeout(timer);reject(error);}});ws.send(JSON.stringify({id:request,method,params}));});
  const evaluate=async expression=>{const result=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});assert.ok(!result.exceptionDetails,JSON.stringify(result.exceptionDetails));return result.result.value;};
  const settle=()=>evaluate('new Promise(r=>setTimeout(r,100))');
  const configure=async options=>{await evaluate(`lab.configure(${JSON.stringify(options)})`);await settle();};
  await send('Runtime.enable');await send('Page.enable');
  await send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});
  await send('Emulation.setDeviceMetricsOverride',{width:960,height:640,deviceScaleFactor:1,mobile:false});
  await send('Page.navigate',{url});
  console.log('Browser navigated');
  for(let i=0;i<100;i++){if(await evaluate('Boolean(window.lab && document.querySelector(".collection-header"))'))break;await new Promise(r=>setTimeout(r,100));}
  assert.equal(await evaluate('Boolean(window.lab)'),true,'fixture mounted');await settle();
  console.log('Fixture mounted');
  // A white reference cover proves the decoration no longer paints over foreground.
  const clip=await evaluate('(()=>{const b=document.querySelector("img.artwork").getBoundingClientRect();return {x:b.x+80,y:b.y+80,width:16,height:16,scale:1}})()');
  const shot=()=>send('Page.captureScreenshot',{format:'png',clip});
  const foreground=(await shot()).data;
  await evaluate('document.querySelector(".ambient").style.visibility="hidden"');await settle();
  assert.equal((await shot()).data,foreground,'cover pixels unchanged when decoration hidden');
  await evaluate('document.querySelector(".ambient").style.visibility="visible";document.querySelector(".ambient").style.zIndex="0";document.querySelector(".collection-header").style.containerType="normal"');await settle();
  assert.notEqual((await shot()).data,foreground,'old z0 reproduces foreground veil');
  await evaluate('document.querySelector(".ambient").style.removeProperty("z-index");document.querySelector(".collection-header").style.removeProperty("container-type")');
  results.push('foreground pixels: old veil reproduced; corrected cover unchanged with decoration hidden');
  for(const [width,height]of [[960,640],[1100,720],[1440,900]])for(const sidebar of [230,60])for(const scale of [1,1.25,1.5])for(const mode of ['album','playlist','owned','liked'])for(const locale of ['es','en']){
    await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:scale,mobile:false});
    await configure({mode,width:width-sidebar,sidebar,locale});
    const geometry=await evaluate(`(()=>{const box=s=>document.querySelector(s).getBoundingClientRect();const art=box('.artwork'),toolbar=box('.toolbar'),header=box('.collection-header');return {toolbarBelow:toolbar.top>=art.bottom,aligned:Math.abs(toolbar.left-art.left)<1,headerWidth:header.width,overflow:document.documentElement.scrollWidth>innerWidth,controls:[...document.querySelectorAll('.toolbar button,.toolbar input,.toolbar select')].every(e=>{const b=e.getBoundingClientRect();return b.left>=header.left&&b.right<=header.right+1&&b.width>0})}})()`);
    assert.equal(geometry.toolbarBelow,true,JSON.stringify({width,sidebar,mode,geometry}));assert.equal(geometry.aligned,true);assert.equal(geometry.overflow,false);assert.equal(geometry.controls,true,JSON.stringify({width,sidebar,mode,geometry}));
  }
  results.push('144 collection configurations: geometry, control bounds, toolbar alignment, ES/EN, DPR1/1.25/1.5');
  for(const width of [480,600,730]){
    await configure({mode:'owned',width});
    const rows=await evaluate(`(()=>{const row=document.querySelector('.track-row'),actions=row.querySelector('.actions'),group=row.querySelector('.action-group'),duration=row.querySelector('.duration');return {width:${width},cell:actions.getBoundingClientRect().width,group:group.scrollWidth,overlap:group.getBoundingClientRect().left<duration.getBoundingClientRect().right,buttons:[...group.querySelectorAll('button')].length}})()`);
    console.log('Row action geometry: '+JSON.stringify(rows));
    assert.equal(rows.overlap,false,JSON.stringify(rows));
    const bounds=await evaluate('(()=>{const c=document.querySelector(".collection-fixture").getBoundingClientRect();return [...document.querySelectorAll(".toolbar button,.toolbar input,.toolbar select")].every(e=>{const b=e.getBoundingClientRect();return b.left>=c.left&&b.right<=c.right+1})})()');
    assert.equal(bounds,true,'all controls inside '+width+'px container');
    await evaluate('document.querySelector(".content-column").scrollTop=100000');await settle();
    assert.equal(await evaluate('document.querySelector(".track-row:last-of-type").getBoundingClientRect().bottom<=document.querySelector(".player-dock").getBoundingClientRect().top'),true,'last row clears player');
    await evaluate('document.querySelector(".content-column").scrollTop=0');
  }
  // This checks the flex group's box; individual button overflow still needs QA.
  results.push('480/600/730 container boundaries: action-group box, controls and last row above player');
  await configure({mode:'playlist',sidebar:230,width:730,spotlight:true});
  assert.deepEqual(await evaluate('(()=>{const b=document.querySelector(".scrim").getBoundingClientRect();return [b.top,b.left,b.right,b.bottom]})()'),[0,0,1440,900]);
  assert.equal(await evaluate('document.elementFromPoint(300,12).classList.contains("scrim")'),true);
  assert.equal(await evaluate('Boolean(document.elementFromPoint(innerWidth-23,12).closest(".window-controls"))'),true);
  assert.equal(await evaluate('Boolean(document.activeElement.closest(".spotlight"))'),true);
  for(let i=0;i<8;i++){await send('Input.dispatchKeyEvent',{type:'keyDown',key:'Tab',code:'Tab',windowsVirtualKeyCode:9});await send('Input.dispatchKeyEvent',{type:'keyUp',key:'Tab',code:'Tab',windowsVirtualKeyCode:9});}
  assert.equal(await evaluate('Boolean(document.activeElement.closest(".spotlight"))'),true);
  await send('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await settle();
  assert.equal(await evaluate('Boolean(document.querySelector(".scrim"))'),false);
  await evaluate('document.getElementById("launcher").focus();document.getElementById("launcher").click()');await settle();
  await send('Input.dispatchMouseEvent',{type:'mousePressed',x:300,y:12,button:'left',clickCount:1});await send('Input.dispatchMouseEvent',{type:'mouseReleased',x:300,y:12,button:'left',clickCount:1});await settle();
  assert.equal(await evaluate('document.activeElement.id'),'launcher');
  assert.equal(await evaluate('lab.snapshot().calls.includes("back")'),false);
  results.push('Spotlight full coverage, window buttons hit testing, background history blocked, Tab trap, Escape, outside click and restored focus');
  await configure({mode:'explore'});
  const explore=await evaluate('(()=>{const scroll=document.querySelector(".explore-scroll"),h=scroll.querySelector("h1"),nav=scroll.querySelector("nav");return {before:h.getBoundingClientRect().bottom<=nav.getBoundingClientRect().top,font:getComputedStyle(h).fontSize,nested:scroll.contains(nav),overflow:document.documentElement.scrollWidth>innerWidth}})()');
  assert.deepEqual(explore,{before:true,font:'40px',nested:true,overflow:false});
  await evaluate('document.querySelector(".explore-scroll").scrollTop=250');await settle();
  assert.equal(await evaluate('document.querySelector(".explore-scroll header").getBoundingClientRect().bottom<32'),true);
  results.push('Explore title/nav share scrolling viewport; title40 and no global horizontal overflow');
  await writeFile(path.join(cache,'final.png'),Buffer.from((await send('Page.captureScreenshot',{format:'png'})).data,'base64'));
  assert.deepEqual(errors,[]);
  await writeFile(path.join(cache,'results.json'),JSON.stringify({results,errors},null,2));
  console.log(JSON.stringify({results,errors,artifacts:cache},null,2));
} catch(error) {console.error(error);process.exitCode=1;} finally {ws?.close();browser.kill();await server.close();}

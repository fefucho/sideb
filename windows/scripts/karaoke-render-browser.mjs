// Opt-in real Chromium raster regression. From windows/: node scripts/karaoke-render-browser.mjs
// SIDEB_BROWSER selects Chromium; SIDEB_KARAOKE_COMPONENT selects a saved source for an A/B failure check.
import assert from 'node:assert/strict';
import {writeFile,mkdir} from 'node:fs/promises';
import path from 'node:path';import {fileURLToPath} from 'node:url';import {spawn} from 'node:child_process';
import {createServer} from 'vite';import {svelte} from '@sveltejs/vite-plugin-svelte';
const root=fileURLToPath(new URL('../',import.meta.url));
const cache=path.join(root,'.cache/karaoke-render-browser');
await mkdir(cache,{recursive:true});
const fixture=String.raw`<script>
import '$lib/styles/fonts.css';import Phrase from '$phrase';import {prepareKaraoke} from '$lib/player/karaoke';
let values=$state({text:'Kiss of life',width:360,size:36,time:2500,motion:true,reduced:false,scale:1,enabled:true,timed:true});
const listeners=new Set();let ms=values.time;
const clock={sample:()=>ms,subscribe:fn=>{listeners.add(fn);fn(ms);return()=>listeners.delete(fn)}};
const doc=$derived(prepareKaraoke({provider:'fixture',isSynced:true,instrumental:false,lines:[{text:values.text,timeMs:1000,endTimeMs:8000,words:!values.timed?[]:values.text.split(' ').map((text,i)=>({text,startMs:1000+i*1200,endMs:2200+i*1200}))}]},20));
export function configure(next){values={...values,...next};if(next.time!==undefined){ms=next.time;for(const fn of listeners)fn(ms)}}
export function step(time){ms=time;for(const fn of listeners)fn(ms)}
export function subscriptions(){return listeners.size}
</script>
<div id="test" style:width={values.width+'px'} style:font-size={values.size+'px'} style:transform={'scale('+values.scale+')'}><Phrase line={doc.lines[0]} {clock} enabled={values.enabled} offset={0} geometry={JSON.stringify([values.size,values.width,values.text])} motion={values.motion} reduced={values.reduced}/></div>
<style>:global(body){margin:0;background:#111;color:white;}#test{margin:40px;font-weight:700;letter-spacing:-.18px;line-height:1.25;transform-origin:left top;}</style>`;
await writeFile(path.join(cache,'RenderFixture.svelte'),fixture);
await writeFile(path.join(cache,'render.html'),'<html><body><div id="app"></div><script type="module" src="/render-main.js"></script></body></html>');
await writeFile(path.join(cache,'render-main.js'),"import {mount} from 'svelte';import Fixture from './RenderFixture.svelte';window.lab=mount(Fixture,{target:document.getElementById('app')});");
const server=await createServer({configFile:false,root:cache,publicDir:path.join(root,'static'),plugins:[svelte()],resolve:{alias:{$lib:path.join(root,'src/lib'),$phrase:process.env.SIDEB_KARAOKE_COMPONENT??path.join(root,'src/lib/components/fullscreen/KaraokePhrase.svelte')}},server:{host:'127.0.0.1',port:0,fs:{allow:[root]}},logLevel:'error'});
await server.listen();const url=new URL('render.html',server.resolvedUrls.local[0]).href;
const browser=spawn(process.env.SIDEB_BROWSER??'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless=new','--no-first-run','--no-default-browser-check','--disable-extensions','--disable-background-networking','--disable-background-timer-throttling','--remote-debugging-port=0',`--user-data-dir=${path.join(cache,'render-edge-'+Date.now())}`,'about:blank'],{windowsHide:true,stdio:['ignore','ignore','pipe']});
let stderr='',ws;browser.stderr.on('data',s=>stderr+=s);
try{
 for(let i=0;i<100&&!stderr.includes('DevTools listening on');i++)await new Promise(r=>setTimeout(r,100));
 const endpoint=stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/)?.[1];assert.ok(endpoint,stderr);
 const pages=await(await fetch(new URL('/json/list',endpoint.replace('ws:','http:')))).json();
 ws=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);await new Promise((resolve,reject)=>{ws.addEventListener('open',resolve,{once:true});ws.addEventListener('error',reject,{once:true});});
 let id=0;const pending=new Map(),errors=[],requests=[];
 ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result);}else if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description??m.params.exceptionDetails.text);else if(m.method==='Network.requestWillBeSent')requests.push(m.params.request.url);});
 const send=(method,params={})=>new Promise((resolve,reject)=>{const key=++id;const timer=setTimeout(()=>reject(new Error(method+' timed out')),20000);pending.set(key,{resolve:v=>{clearTimeout(timer);resolve(v);},reject:e=>{clearTimeout(timer);reject(e);}});ws.send(JSON.stringify({id:key,method,params}));});
 const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});assert.ok(!r.exceptionDetails,JSON.stringify(r.exceptionDetails));return r.result.value;};
 const settle=()=>evaluate('new Promise(r=>setTimeout(r,250))');
 await send('Runtime.enable');await send('Network.enable');await send('DOM.enable');await send('CSS.enable');
 await send('Network.setBlockedURLs',{urls:['https://*','http://*.google.com/*']});
 await send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'no-preference'}]});
 await send('Emulation.setDeviceMetricsOverride',{width:1100,height:800,deviceScaleFactor:1,mobile:false});
 await send('Page.navigate',{url});
 for(let i=0;i<100;i++){if(await evaluate('Boolean(window.lab&&document.querySelector(".phrase"))'))break;await new Promise(r=>setTimeout(r,100));}
 assert.ok(await evaluate('Boolean(window.lab)'));await evaluate('document.fonts.ready');await settle();

 const snapshot = async () => (await send('Page.captureScreenshot',{format:'png'})).data;
 // Read composited pixels instead of equating SVG counts with correct rendering.
 const pixels = async (data, rectangles) => evaluate(`(async()=>{
   const image=new Image();image.src='data:image/png;base64,'+${JSON.stringify(data)};await image.decode();
   const canvas=document.createElement('canvas');canvas.width=image.width;canvas.height=image.height;
   const ctx=canvas.getContext('2d');ctx.drawImage(image,0,0);const scale=image.width/1100;
   return ${JSON.stringify(rectangles)}.map(box=>{
     const data=ctx.getImageData(Math.round((box.x+2)*scale),Math.round((box.y+2)*scale),Math.max(1,Math.floor((box.width-4)*scale)),Math.max(1,Math.floor((box.height-4)*scale))).data;
     let ink=0;for(let i=0;i<data.length;i+=4)if(data[i]>35||data[i+1]>35||data[i+2]>35)ink++;
     return ink;
   });
 })()`);
 const bounds = () => evaluate(`(()=>{
   const host=document.querySelector('.phrase'),base=host.firstElementChild,node=base.firstChild;
   const line=base.textContent,words=line.split(' ');let cursor=0;
   const ranges=words.map(text=>{const start=line.indexOf(text,cursor);cursor=start+text.length;const r=document.createRange();r.setStart(node,start);r.setEnd(node,cursor);return [...r.getClientRects()].filter(b=>b.width>0&&b.height>0).map(b=>({x:b.x,y:b.y,width:b.width,height:b.height}));});
   return {ranges,height:host.getBoundingClientRect().height,text:line};
 })()`);
 const configure = async options => {await evaluate(`lab.configure(${JSON.stringify({motion:true,reduced:false,enabled:true,timed:true,scale:1,size:36,...options})})`);await settle();};
 const results=[];
 for(const [index,options] of [
   {text:'Kiss of life',width:300,time:4400},
   {text:'Something heavenly led me to you',width:520,time:7600},
   {text:'Something supercalifragilisticexpialidocious',width:260,time:2800},
   {text:'مرحبا بالعالم الجميل',width:270,time:2800},
   {text:'Café 👩🏽‍🚀 déjà vu',width:270,time:4000},
   {text:'שָׁלוֹם hello עולם',width:280,time:2800},
   {text:'Something heavenly led me to you',width:403,size:44,scale:.88,time:7600},
   {text:'Something heavenly led me to you',width:220,size:20,time:7600,dpi:1.25},
   {text:'Kiss of life',width:400,size:72,time:4400,dpi:2},
 ].entries()) {
   await send('Emulation.setDeviceMetricsOverride',{width:1100,height:800,deviceScaleFactor:options.dpi??1,mobile:false});
   await configure(options);
   const geometry=await bounds(),active=Math.floor((options.time-1000)/1200),boxes=geometry.ranges[active];
   assert.ok(boxes.length,'Native active glyph geometry');
   const full=await snapshot();await writeFile(path.join(cache,`case-${index}.png`),Buffer.from(full,'base64'));
   const fullInk=await pixels(full,boxes);assert.ok(fullInk.some(n=>n>70),'Active word remains visible');
   // Hide only moving ink. Its original position must be empty, proving both
   // the dim base and stationary fill were removed underneath it.
   await evaluate(`document.querySelectorAll('.word-effect,.word-highlight').forEach(e=>{if(e.classList.contains('word-effect')||getComputedStyle(e).transform!=='none')e.style.visibility='hidden'})`);
   const remainingInk=await pixels(await snapshot(),boxes);
   assert.ok(remainingInk.every(n=>n===0),`case ${index}: stationary ghost underneath moving word: ${remainingInk}`);
   await evaluate(`document.querySelectorAll('.word-effect,.word-highlight').forEach(e=>e.style.visibility='')`);
   if(index===1)assert.ok(boxes[0].y>geometry.ranges[0][0].y+30,'you is on the second visual line');
   if(index===2)assert.ok(boxes.length>=2,'One timed word wraps across native visual lines');
   const anchors=await evaluate(`(()=>{const host=document.querySelector('.phrase'),b=host.getBoundingClientRect(),scale=b.width/host.offsetWidth;return [...host.querySelectorAll('.word-effect')].map(e=>{const [x,y]=getComputedStyle(e).transformOrigin.split(' ').map(parseFloat);return {x:b.x+x*scale,y:b.y+y*scale}})})()`);
   assert.equal(anchors.length,boxes.length,'Each visual fragment gets its own anchor');
   for(const box of boxes)assert.ok(anchors.some(a=>Math.abs(a.x-box.x-box.width/2)<1&&Math.abs(a.y-box.y-box.height)<1),'Anchor matches native fragment, including the second line');
   await evaluate('lab.step(0)');await settle();
   assert.equal(await evaluate(`document.querySelectorAll('.word-effect').length`),0);
   assert.ok((await pixels(await snapshot(),boxes)).some(n=>n>70),'Backward seek restores base glyphs');
   await evaluate('lab.step(20000)');await settle();
   assert.equal(await evaluate(`document.querySelectorAll('.word-effect').length`),0);
   assert.ok((await pixels(await snapshot(),boxes)).some(n=>n>70),'Completed words remain visible');
   for(const setting of [{motion:false},{reduced:true}]) {
     await configure({...options,...setting});
     assert.equal(await evaluate(`document.querySelectorAll('.word-effect').length`),0);
     assert.ok((await pixels(await snapshot(),boxes)).some(n=>n>70),'No-motion still paints the word');
   }
   results.push({options,geometry,fullInk,remainingInk,anchors});
 }
 for(const options of [{enabled:false},{timed:false}]) {
   await configure({text:'Fallback without word timing',width:400,time:1600,...options});
   assert.equal(await evaluate(`document.querySelectorAll('.word-highlight').length`),0);
   assert.equal(await evaluate(`document.querySelector('.phrase').firstElementChild.textContent`),'Fallback without word timing');
 }
 await configure({text:'',width:300,time:0,timed:false});
 assert.equal(await evaluate(`document.querySelector('.phrase').firstElementChild.textContent`),'♪');
 await send('Emulation.setDeviceMetricsOverride',{width:1100,height:800,deviceScaleFactor:1,mobile:false});
 await configure({text:'Kiss of life',width:300,time:4400});
 const shape=await bounds();
 const paused=await snapshot();await settle();assert.equal(await snapshot(),paused,'Paused rendering is stable');
 await evaluate(`document.getElementById('test').style.marginTop='2000px'`);await settle();
 assert.equal(await evaluate('lab.subscriptions()'),0,'Offscreen rows unsubscribe from clock');
 assert.equal(await evaluate(`document.querySelectorAll('.word-effect').length`),0);
 await evaluate(`document.getElementById('test').style.marginTop='40px'`);await settle();
 assert.equal(await evaluate('lab.subscriptions()'),1,'Visible row resumes from current clock');
 assert.equal((await bounds()).height,shape.height,'Re-entry preserves layout');
 await send('Emulation.setEmulatedMedia',{features:[{name:'forced-colors',value:'active'}]});await settle();
 assert.equal(await evaluate(`getComputedStyle(document.querySelector('.effects')).display`),'none');
 assert.equal(await evaluate(`getComputedStyle(document.querySelector('.phrase').firstElementChild).maskImage`),'none');
 assert.deepEqual(errors,[]);
 assert.ok(requests.every(url=>!url.startsWith('http')||new URL(url).hostname==='127.0.0.1'),'No external provider or font requests');
 await writeFile(path.join(cache,'results.json'),JSON.stringify({results,errors},null,2));
 console.log(`Karaoke browser regression: ${results.length} shaped/animated cases + fallback, backward/end seek, reduced motion, pause, offscreen and forced colors passed.`);
}finally{ws?.close();browser.kill();await server.close();}

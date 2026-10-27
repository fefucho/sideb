// Opt-in blur containment raster regression using the real LyricsPanel.
// From windows/: node scripts/lyrics-blur-browser.mjs
// SIDEB_BROWSER selects Chromium; SIDEB_LYRICS_COMPONENT selects an A/B source; before records a failing baseline.
import assert from 'node:assert/strict';
import {writeFile,mkdir} from 'node:fs/promises';
import path from 'node:path';import {fileURLToPath} from 'node:url';import {spawn} from 'node:child_process';
import {createServer} from 'vite';import {svelte} from '@sveltejs/vite-plugin-svelte';
const root=fileURLToPath(new URL('../',import.meta.url));
const cache=path.join(root,'.cache/lyrics-blur');
await mkdir(cache,{recursive:true});
const fixture=String.raw`<script>
import '$lib/styles/fonts.css';import Panel from '$panel';
let values=$state({width:650,size:36,position:12.2});
const lines=Array.from({length:40},(_,i)=>({text:'Porque la noche de anoche fue',timeMs:1000+i*1000,endTimeMs:1900+i*1000,words:[]}));
window.__TAURI_INTERNALS__={invoke:async()=>({provider:'fixture',isSynced:true,instrumental:false,lines})};
const classic={status:'ready',trackKey:JSON.stringify(['fixture',1,JSON.stringify([1,'fixture'])]),lyrics:{provider:'fixture',isSynced:true,lines},error:null};
const playback=$derived({isPlaying:false,isLoading:false,position:values.position,duration:60,generation:1,queue:{items:[{entryId:'fixture'}],currentIndex:0},currentTrack:{videoId:'fixture',title:'Fixture',artists:'Fixture',duration:60}});
export function configure(next){values={...values,...next}}
</script>
<div id="test" style:width={values.width+'px'}><Panel state={classic} {playback} session={1} onSeek={()=>{}} onRetry={()=>{}}/></div>
<style>:global(body){margin:0;background:#111;color:white;}#test{margin:40px;height:650px;}</style>`;
await writeFile(path.join(cache,'RenderFixture.svelte'),fixture);
await writeFile(path.join(cache,'render.html'),'<html><body><div id="app"></div><script type="module" src="/render-main.js"></script></body></html>');
await writeFile(path.join(cache,'render-main.js'),"import {mount} from 'svelte';import Fixture from './RenderFixture.svelte';window.lab=mount(Fixture,{target:document.getElementById('app')});");
const server=await createServer({configFile:false,root:cache,publicDir:path.join(root,'static'),plugins:[svelte()],resolve:{alias:{$lib:path.join(root,'src/lib'),$panel:process.env.SIDEB_LYRICS_COMPONENT??path.join(root,'src/lib/components/fullscreen/LyricsPanel.svelte')}},server:{host:'127.0.0.1',port:0,fs:{allow:[root]}},logLevel:'error'});
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
 for(let i=0;i<100;i++){if(await evaluate('Boolean(window.lab&&document.querySelector(".lyrics-scroll"))'))break;await new Promise(r=>setTimeout(r,100));}
 assert.ok(await evaluate('Boolean(window.lab)'));assert.ok(await evaluate(`CSS.supports('overflow-clip-margin','24px')`));await evaluate('document.fonts.ready');await evaluate('new Promise(r=>setTimeout(r,1200))');

 const mode=process.argv[2]??'after';
 const results=[];
 for(const width of [650,310])for(const dpi of [1,1.25,2]) {
   await send('Emulation.setDeviceMetricsOverride',{width:1100,height:800,deviceScaleFactor:dpi,mobile:false});
   await evaluate(`lab.configure({width:${width}})`);await evaluate('new Promise(r=>setTimeout(r,1100))');
   const geometry=await evaluate(`(()=>{
     const scroll=document.querySelector('.lyrics-scroll'),v=scroll.getBoundingClientRect();
     const row=[...document.querySelectorAll('.row')].find(e=>{const b=e.getBoundingClientRect();return parseFloat(getComputedStyle(e).filter.match(/blur\\(([^p]+)/)?.[1]??'0')>=2.9&&b.top>v.top+90&&b.bottom<v.bottom-90});
     if(!row)return null;row.parentElement.id='target-group';const text=row.querySelector('.phrase').getBoundingClientRect(),group=row.parentElement.getBoundingClientRect();
     return {x:text.x,y:text.y,width:text.width,height:text.height,groupX:group.x,scrollWidth:scroll.scrollWidth,clientWidth:scroll.clientWidth,scrollTop:scroll.scrollTop};
   })()`);
   assert.ok(geometry,'Visible context row');
   const unchanged=await evaluate(`(()=>{const g=document.getElementById('target-group'),b=g.getBoundingClientRect(),scroll=document.querySelector('.lyrics-scroll'),top=scroll.scrollTop;g.style.overflowClipMargin='0px';const c=g.getBoundingClientRect();const same=b.x===c.x&&b.y===c.y&&b.width===c.width&&b.height===c.height&&top===scroll.scrollTop;g.style.overflowClipMargin='';return same})()`);assert.ok(unchanged,'Drawing room must not alter layout or scroll');
   const capture=async()=> (await send('Page.captureScreenshot',{format:'png'})).data;
   const actual=await capture();await writeFile(path.join(cache,`${mode}-${width}-${dpi}.png`),Buffer.from(actual,'base64'));
   await evaluate(`document.getElementById('target-group').style.contentVisibility='visible'`);
   const reference=await capture();
   const difference=await evaluate(`(async()=>{
     const images=await Promise.all(${JSON.stringify([actual,reference])}.map(async data=>{const image=new Image();image.src='data:image/png;base64,'+data;await image.decode();const c=document.createElement('canvas');c.width=image.width;c.height=image.height;const x=c.getContext('2d');x.drawImage(image,0,0);return x}));
     const g=${JSON.stringify(geometry)},scale=${dpi},x=Math.floor((g.x-12)*scale),y=Math.floor(g.y*scale),w=Math.ceil(10*scale),h=Math.floor(g.height*scale);
     const [a,b]=images.map(c=>c.getImageData(x,y,w,h).data);let changed=0,amount=0,actualHalo=0,referenceHalo=0;for(let i=0;i<a.length;i+=4){const d=Math.abs(a[i]-b[i]);if(d>1)changed++;amount+=d;actualHalo+=Math.max(0,a[i]-17);referenceHalo+=Math.max(0,b[i]-17);}return {changed,amount,actualHalo,referenceHalo};
   })()`);
   await evaluate(`document.getElementById('target-group').style.contentVisibility='';document.getElementById('target-group').removeAttribute('id')`);
   results.push({width,dpi,geometry,difference});
 }
 await writeFile(path.join(cache,mode+'-results.json'),JSON.stringify({results,errors},null,2));
 console.log(JSON.stringify({mode,results,errors}));
 if(mode!=='before')for(const result of results){assert.ok(result.difference.referenceHalo>100,'Reference blur extends left of the original clip');assert.ok(result.difference.actualHalo>=result.difference.referenceHalo*.98,'Blur halo must survive at the left edge, allowing minor raster differences');assert.ok(result.geometry.scrollWidth<=result.geometry.clientWidth,'No horizontal overflow');}
 assert.deepEqual(errors,[]);
}finally{ws?.close();browser.kill();await server.close();}

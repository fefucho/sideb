// PLAN-023 W8 (PAR-053): real Svelte + Chromium layout of the Settings modal at several window sizes.
// Synthetic data, no account/playback. Geometry only: it does not validate visual design, contrast or WebView2.
// Run: SIDEB_BROWSER="<path to Edge/Chrome>" node scripts/settings-modal-browser.mjs
import assert from 'node:assert/strict';
import {writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {createServer} from 'vite';
import {svelte} from '@sveltejs/vite-plugin-svelte';
const root=fileURLToPath(new URL('../',import.meta.url)),cache=path.join(root,'.cache/settings-modal-browser');
await mkdir(cache,{recursive:true});
await writeFile(path.join(cache,'Fixture.svelte'),String.raw`<script>
import '$lib/styles/fonts.css';import '$lib/styles/tokens.css';
import {setContext} from 'svelte';
import HomeSettings from '$lib/components/home/HomeSettings.svelte';
import {SETTINGS_HOST_CONTEXT} from '$lib/components/settings/settingsCategories';
import {defaults} from '$lib/home/settings';
import {setLanguage} from '$lib/i18n';
window.__TAURI_INTERNALS={invoke:async()=>0,transformCallback:()=>0,unregisterCallback:()=>{}};
setContext(SETTINGS_HOST_CONTEXT,{get auth(){return {state:'ready',name:'Usuario de prueba con un nombre bastante largo',handle:'@prueba',email:'prueba@example.test',thumbnail:null,message:null};},
  updater:{subscribe(fn){fn({state:{type:'idle'},currentVersion:'1.4.0',isModalOpen:false});return()=>{};},checkForUpdates:async()=>{}},login(){},cancelLogin(){},logout(){}});
const categories=Array.from({length:14},(_,i)=>({key:'c'+i,title:'Estante de recomendaciones número '+i}));
let closed=$state(0);
window.lab={closed:()=>closed,language:l=>setLanguage(l)};
</script>
<main><HomeSettings settings={defaults()} kind="albums" {categories} libraryError={null} onChange={()=>{}} onKind={()=>{}} onRetryLibrary={()=>{}} onClose={()=>closed++} exponentialVolume={false} onExponentialVolume={()=>{}} /></main>
<style>:global(body){margin:0;background:#1b1b1e;color:white;font-family:var(--sideb-font-family,Inter,system-ui,sans-serif);--titlebar-height:32px;--sidebar-width:253px}</style>`);
await writeFile(path.join(cache,'main.js'),"import {mount} from 'svelte';import Fixture from './Fixture.svelte';mount(Fixture,{target:document.getElementById('app')});");
await writeFile(path.join(cache,'index.html'),'<div id="app"></div><script type="module" src="/main.js"></script>');
const server=await createServer({configFile:false,root:cache,publicDir:path.join(root,'static'),plugins:[svelte()],resolve:{alias:{$lib:path.join(root,'src/lib')}},server:{host:'127.0.0.1',port:0,watch:null,fs:{allow:[root]}},logLevel:'error'});
await server.listen();
const browser=spawn(process.env.SIDEB_BROWSER??'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless=new','--no-first-run','--disable-extensions','--remote-debugging-port=0',`--user-data-dir=${path.join(cache,'browser-'+Date.now())}`,'about:blank'],{windowsHide:true,stdio:['ignore','ignore','pipe']});
let stderr='',ws;browser.stderr.on('data',x=>stderr+=x);
try{
  for(let i=0;i<100&&!stderr.includes('DevTools listening on');i++)await new Promise(r=>setTimeout(r,100));
  const endpoint=stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/)?.[1];assert.ok(endpoint,stderr);
  const pages=await(await fetch(new URL('/json/list',endpoint.replace('ws:','http:')))).json();
  ws=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);await new Promise(r=>ws.addEventListener('open',r,{once:true}));
  let id=0;const pending=new Map(),errors=[],evidence=[];
  ws.addEventListener('message',event=>{const m=JSON.parse(event.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result)}else if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description??m.params.exceptionDetails.text)});
  const send=(method,params={})=>new Promise((resolve,reject)=>{const key=++id,timer=setTimeout(()=>reject(Error(method+' timeout')),20000);pending.set(key,{resolve:v=>{clearTimeout(timer);resolve(v)},reject:e=>{clearTimeout(timer);reject(e)}});ws.send(JSON.stringify({id:key,method,params}))});
  const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});assert.ok(!r.exceptionDetails,JSON.stringify(r.exceptionDetails));return r.result.value};
  const settle=(ms=200)=>new Promise(resolve=>setTimeout(resolve,ms));
  await send('Runtime.enable');await send('Page.navigate',{url:server.resolvedUrls.local[0]});
  for(let i=0;i<300;i++){if(await evaluate('!!window.lab&&!!document.querySelector(".panel")'))break;await settle(100)}
  assert.ok(await evaluate('!!document.querySelector(".panel")'),errors.join('\n'));await evaluate('document.fonts.ready');
  const clamp=(v,lo,hi)=>Math.max(lo,Math.min(hi,v));
  for(const [width,height] of [[960,640],[1100,720],[1280,800],[1366,768],[1600,1000],[1920,1080],[2560,1440]]){
    await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await settle();
    for(const category of ['general','playback','appearance','shortcuts','homeFeed','visualProviders','account']){
      await evaluate(`document.querySelector('button.item[data-category="${category}"]').click()`);await settle(120);
      const m=await evaluate(`(()=>{const r=e=>{const b=e.getBoundingClientRect();return {x:b.x,y:b.y,w:b.width,h:b.height,right:b.right,bottom:b.bottom}};
        const panel=document.querySelector('.panel'),side=document.querySelector('.side'),detail=document.querySelector('.detail'),content=document.querySelector('.content'),cols=document.querySelector('.columns');
        return {panel:r(panel),side:r(side),detail:r(detail),content:r(content),detailScroll:{sw:detail.scrollWidth,cw:detail.clientWidth},
          items:[...document.querySelectorAll('button.item')].map(r),columns:cols?getComputedStyle(cols).gridTemplateColumns.split(' ').length:0,
          rows:[...document.querySelectorAll('.rows')].map(r),overflowX:[...document.querySelectorAll('.content *')].filter(e=>e.getBoundingClientRect().right>detail.getBoundingClientRect().right+0.5&&getComputedStyle(e).position!=='fixed').length,
          title:getComputedStyle(document.querySelector('h2')).fontSize}})()`);
      const expectedW=Math.min(clamp(width-48,780,1240),width-16),expectedH=Math.min(clamp(height-96,520,860),height-32-16);
      assert.ok(Math.abs(m.panel.w-expectedW)<=1,`panel width ${m.panel.w} vs ${expectedW} @${width}x${height}`);
      assert.ok(Math.abs(m.panel.h-expectedH)<=1,`panel height ${m.panel.h} vs ${expectedH} @${width}x${height}`);
      assert.ok(m.panel.w>=780&&m.panel.h>=520||width<796||height<568,'minimum panel size');
      assert.ok(m.panel.w<=1240&&m.panel.h<=860,'maximum panel size');
      assert.ok(m.panel.x>=0&&m.panel.right<=width&&m.panel.y>=32&&m.panel.bottom<=height,`panel stays inside the window below the titlebar @${width}x${height}`);
      assert.ok(Math.abs((m.panel.x+m.panel.w/2)-width/2)<=1,'horizontally centered');
      assert.ok(Math.abs(m.side.w-244)<=1,'sidebar is 244px');
      assert.ok(m.items.every(item=>Math.abs(item.h-30)<=0.5),'sidebar items are 30px tall');
      assert.equal(m.detailScroll.sw<=m.detailScroll.cw,true,`no horizontal scroll in ${category} @${width}x${height}`);
      assert.equal(m.overflowX,0,`content never exceeds the detail pane in ${category} @${width}x${height}`);
      assert.equal(m.title,'28px');
      assert.ok(m.content.w<= (category==='homeFeed'?980:720)+0.5,'content max width');
      if(category==='homeFeed')assert.equal(m.columns,m.detail.w>=896?2:1,`Home feed uses ${m.detail.w>=896?'two columns':'one column'} at detail width ${m.detail.w}`);
      evidence.push({width,height,category,panel:[m.panel.w,m.panel.h],detail:m.detail.w,columns:m.columns});
      if(width===1280||width===960){const shot=await send('Page.captureScreenshot',{format:'png'});await writeFile(path.join(cache,`settings-${width}x${height}-${category}.png`),Buffer.from(shot.data,'base64'));}
    }
  }
  // Keyboard: Escape reaches onClose; focus stays inside the panel after Tab cycles.
  await evaluate("document.querySelector('.close').focus()");
  for(let i=0;i<60;i++){await send('Input.dispatchKeyEvent',{type:'keyDown',key:'Tab',code:'Tab',windowsVirtualKeyCode:9});await send('Input.dispatchKeyEvent',{type:'keyUp',key:'Tab',code:'Tab',windowsVirtualKeyCode:9});
    assert.equal(await evaluate("!!document.activeElement?.closest('.panel')"),true,'focus never leaves the dialog on Tab #'+i);}
  await send('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await settle();
  assert.equal(await evaluate('lab.closed()'),1);
  assert.deepEqual(errors,[]);
  await writeFile(path.join(cache,'results.json'),JSON.stringify({synthetic:true,host:process.platform,evidence,errors},null,2));
  console.log(JSON.stringify({ok:true,cases:evidence.length,errors}));
}finally{ws?.close();browser.kill();await server.close()}

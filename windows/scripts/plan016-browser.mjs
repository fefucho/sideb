// Opt-in production-shell UI integration with synthetic provider data. No native/audio claim.
// SIDEB_BROWSER='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' node scripts/plan016-browser.mjs
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {createServer} from 'vite';
import {svelte} from '@sveltejs/vite-plugin-svelte';

const root=fileURLToPath(new URL('../',import.meta.url));
const cache=path.join(root,'.cache/plan016-browser');await mkdir(cache,{recursive:true});
const mock=String.raw`
import {emptyPlaybackData} from '$lib/player/controller';
const listeners=new Map();export const calls=[];
export async function listen(name,callback){let group=listeners.get(name);if(!group){group=new Set();listeners.set(name,group);}group.add(callback);return()=>group.delete(callback);}
function emit(name,payload){for(const callback of listeners.get(name)??[])callback({payload});}
const cover='data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="216" height="216"><defs><linearGradient id="g"><stop stop-color="#b72c9c"/><stop offset="1" stop-color="#3652c5"/></linearGradient></defs><rect width="216" height="216" fill="url(#g)"/><circle cx="108" cy="108" r="56" fill="#e0bda9"/><text x="108" y="115" text-anchor="middle" fill="#231835" font-size="26">SIDE B</text></svg>');
const card=(i,kind='album')=>({kind,id:kind+'-'+i,title:'Collection '+i,subtitle:'Fixture Artist',artists:'Fixture Artist',artistId:'artist',artistRuns:[{id:'artist',text:'Fixture Artist'}],album:null,albumId:null,thumbnail:cover,duration:null});
const song=i=>({videoId:'video-'+i,title:i===0?'Homecoming (feat. Chris Martin)':'Result '+i,artists:'Kanye West',artistId:'artist',artistRuns:[{id:'artist',text:'Kanye West'}],album:'Graduation',albumId:'album',duration:'3:24',thumbnail:cover,isVideo:false,setVideoId:'occurrence-'+i});
let playing={...emptyPlaybackData(),generation:1,authGeneration:1,currentTrack:{...song(0),duration:204},duration:204,position:22,queue:{items:[{...song(0),duration:204,entryId:'occurrence-0'}],revision:1,currentIndex:0,source:{kind:'search',id:'fixture',title:'Fixture'}}};
const listSection=(start,count)=>({id:'list-'+start,title:'',layout:'list',items:[],songs:Array.from({length:count},(_,i)=>song(start+i)),actions:[],moreParams:null,moreQuery:null,moreBrowseId:null});
function searchPage(query){const artist=query.includes('kendrick'),album=query.includes('butterfly');const primary=artist?{...card(1,'artist'),id:'artist',title:'Kendrick Lamar'}:album?{...card(1),title:'To Pimp a Butterfly'}:{...card(0,'song'),id:'video-0',title:song(0).title};return {chips:['Songs','Albums','Videos','Episodes','Community playlists','Artists','Profiles','Library'].map((title,i)=>({id:'chip-'+i,title,params:'opaque-'+i,selected:false})),correction:null,sections:[{id:'top',title:'Top result',layout:'top',items:[primary,...(artist?[card(2,'song'),card(3,'song'),card(4,'song')]:[])],songs:artist||album?[]:[song(0)],primaryItemIndex:0,relatedItemIndices:artist?[1,2,3]:[],actions:[{title:'Play',videoId:'video-0',playlistId:null,browseId:null,params:'opaque'}],moreParams:null,moreQuery:null,moreBrowseId:null},listSection(1,5000)],continuation:'page-2'};}
const home={chips:[],sections:[{title:'Speed dial',format:'compactSong',items:Array.from({length:9},(_,i)=>({...card(i,'song'),id:'video-'+i,artists:'Fixture Artist',explicit:false}))},...Array.from({length:20},(_,i)=>({title:'Recommended albums '+i,format:'largeCards',items:Array.from({length:20},(_,j)=>({...card(i*20+j),explicit:false})),moreBrowseId:null,moreParams:null}))],continuation:null};
const classic={provider:'fixture',isSynced:true,lines:Array.from({length:30},(_,i)=>({text:['When words cross the line','La música sigue al volver','声を重ねて歌う'][i%3],timeMs:i*3000,endTimeMs:i*3000+2500}))};
let auth={state:'ready',name:'Fixture Listener',email:null,channelId:'fixture',handle:'fixture',thumbnail:null,message:null};
export async function invoke(command,args={}){
 calls.push({command,args});
 switch(command){
  case 'get_backend_status':return {ready:true,version:'fixture'};
  case 'get_auth_status':return auth;
  case 'get_app_version':return '1.2.6';
  case 'check_for_updates':case 'get_skipped_version':return null;
  case 'get_home_page':return home;
  case 'get_playback_state':return playing;
  case 'get_browse_grid':return Array.from({length:500},(_,i)=>card(i));
  case 'get_library_albums':case 'get_library_artists':case 'get_library_playlists':return Array.from({length:60},(_,i)=>card(i,command.includes('artists')?'artist':command.includes('playlists')?'playlist':'album'));
  case 'get_playlist':return {id:args.playlistId,title:'Fixture playlist',items:[],continuation:null,inLibrary:true,owned:false};
  case 'get_history':return [];
  case 'get_library_songs':return {items:Array.from({length:250},(_,i)=>song(i)),continuation:null};
  case 'search_page':return searchPage(args.query??'homecoming');
  case 'search_page_continuation':return {chips:[],correction:null,sections:[listSection(5001,100)],continuation:null};
  case 'search_suggestions_page':return {entries:[...Array.from({length:6},(_,i)=>({id:'text-'+i,kind:'query',query:'homecoming '+i,runs:[{text:'homecoming '+i,bold:false}],card:null,song:null,feedbackToken:null})),...Array.from({length:2},(_,i)=>({id:'media-'+i,kind:'media',query:null,runs:[],card:null,song:song(i),feedbackToken:null}))]};
  case 'get_lyrics':return classic;
  case 'get_karaoke_lyrics':return {...classic,instrumental:false,lines:classic.lines.map(line=>({...line,words:line.text.split(' ').map((text,i)=>({text,startMs:line.timeMs+i*300,endMs:line.timeMs+i*300+260})),role:'lead',groupId:null,agent:null,section:null,translation:null}))};
  case 'get_animated_artwork_runtime_state':return {visible:true,minimized:false,cloaked:false,powerSaver:false,memoryPressure:false};
  case 'seek_playback_identified':playing={...playing,position:args.seconds,seekRevision:(playing.seekRevision??0)+1};emit('playback-state-changed',playing);return playing;
  case 'start_song_radio':playing={...playing,isPlaying:false,generation:playing.generation+1,currentTrack:{...args.song,duration:204}};return playing;
  case 'get_song_info':case 'genius_find_cached_match':case 'prepare_animated_artwork':return null;
  default:return null;
 }
}
export const convertFileSrc=path=>path;
const nativeWindow={isMaximized:async()=>false,onResized:async()=>()=>{},isFullscreen:async()=>false,setFullscreen:async()=>{},minimize:async()=>{},close:async()=>{},toggleMaximize:async()=>{}};
export const getCurrentWindow=()=>nativeWindow;
globalThis.fixture={calls,emit,account(){auth={...auth,channelId:'second-fixture'};emit('auth-status-changed',auth);},playback(){return playing;}};
`;
await writeFile(path.join(cache,'mock.js'),mock);
await writeFile(path.join(cache,'index.html'),'<html><body><div id="app"></div><script type="module" src="/main.js"></script></body></html>');
await writeFile(path.join(cache,'main.js'),`import {mount} from 'svelte';import App from '../../src/routes/+page.svelte';import '$lib/styles/tokens.css';import '$lib/styles/fonts.css';localStorage.setItem('sideb.ui.language.v1','en');window.app=mount(App,{target:document.getElementById('app')});`);
const mockFile=path.join(cache,'mock.js');
const server=await createServer({configFile:false,root:cache,publicDir:path.join(root,'static'),plugins:[svelte()],resolve:{alias:{$lib:path.join(root,'src/lib'),'@tauri-apps/api/core':mockFile,'@tauri-apps/api/event':mockFile,'@tauri-apps/api/window':mockFile}},server:{host:'127.0.0.1',port:0,fs:{allow:[root]}},logLevel:'error'});
await server.listen();
const browserStarted=Date.now(),software=process.env.SIDEB_BROWSER_SOFTWARE==='1';
const browser=spawn(process.env.SIDEB_BROWSER??'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless=new',...(software?['--disable-gpu']:[]),'--disable-features=OverlayScrollbar,FluentOverlayScrollbar','--no-first-run','--no-default-browser-check','--disable-extensions','--disable-background-networking','--remote-debugging-port=0',`--user-data-dir=${path.join(cache,'browser-'+Date.now())}`,'about:blank'],{stdio:['ignore','ignore','pipe']});
let stderr='';browser.stderr.on('data',chunk=>stderr+=chunk);browser.on('error',error=>stderr+=String(error));
let ws;const evidence=[];
browser.on('exit',(code,signal)=>console.log('browser process exit',JSON.stringify({code,signal,elapsedMs:Date.now()-browserStarted})));

try{
 for(let i=0;i<100&&!stderr.includes('DevTools listening on');i++)await new Promise(r=>setTimeout(r,100));
 const endpoint=stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/)?.[1];assert.ok(endpoint,stderr);
 const pages=await(await fetch(new URL('/json/list',endpoint.replace('ws:','http:')))).json();
 ws=new WebSocket(pages.find(page=>page.type==='page').webSocketDebuggerUrl);await new Promise(r=>ws.addEventListener('open',r,{once:true}));ws.addEventListener('close',event=>console.log('CDP closed',event.code,event.reason));
 let sequence=0;const pending=new Map(),errors=[];
 ws.addEventListener('message',event=>{const message=JSON.parse(event.data);if(message.id){const callback=pending.get(message.id);pending.delete(message.id);if(callback)message.error?callback.reject(message.error):callback.resolve(message.result);}else if(message.method==='Inspector.targetCrashed'||message.method==='Inspector.detached')console.log(message.method,JSON.stringify(message.params));else if(message.method==='Runtime.exceptionThrown')errors.push(message.params.exceptionDetails.exception?.description??message.params.exceptionDetails.text);});
 const send=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;const timeout=setTimeout(()=>reject(Error(method+' timeout'+(typeof params.expression==='string'?' at '+params.expression.slice(0,160):''))),20000);pending.set(id,{resolve:value=>{clearTimeout(timeout);resolve(value);},reject});ws.send(JSON.stringify({id,method,params}));});
 const evaluate=async expression=>{const result=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});assert.ok(!result.exceptionDetails,JSON.stringify(result.exceptionDetails));return result.result.value;};
 // Keep the harness delay outside the renderer; every subsequent DOM assertion
 // still requires a responsive page and observes the actual production state.
 const settle=()=>new Promise(r=>setTimeout(r,150));
 const screenshot=async name=>writeFile(path.join(cache,name+'.png'),Buffer.from((await send('Page.captureScreenshot',{format:'png'})).data,'base64'));
 const click=async selector=>{const point=await evaluate(`(()=>{const element=document.querySelector(${JSON.stringify(selector)});if(!element)throw Error('missing '+${JSON.stringify(selector)});const b=element.getBoundingClientRect();return {x:b.x+b.width/2,y:b.y+b.height/2};})()`);await send('Input.dispatchMouseEvent',{type:'mouseMoved',...point});await send('Input.dispatchMouseEvent',{type:'mousePressed',button:'left',clickCount:1,...point});await send('Input.dispatchMouseEvent',{type:'mouseReleased',button:'left',clickCount:1,...point});await settle();};
 const key=async(name,code=name)=>{const windowsVirtualKeyCode={Escape:27,Enter:13,Tab:9}[name]??0;await send('Input.dispatchKeyEvent',{type:'keyDown',key:name,code,windowsVirtualKeyCode,...(name==='Enter'?{text:'\r',unmodifiedText:'\r'}:{})});await send('Input.dispatchKeyEvent',{type:'keyUp',key:name,code,windowsVirtualKeyCode});await settle();};
 const searchGeometry=()=>evaluate(`(()=>{const b=s=>document.querySelector(s).getBoundingClientRect(),header=b('.search-form'),row=b('.principal'),view=b('.search-page'),scroller=document.querySelector('.search-page .results-scroll'),gutter=scroller.offsetWidth-scroller.clientWidth,actions=[...document.querySelectorAll('.principal .actions button')].map(e=>{const r=e.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height,center:r.y+r.height/2}});return {left:header.left-view.left,right:view.right-header.right-gutter,gutter,aligned:Math.abs(header.left-row.left)<1&&Math.abs(header.right-row.right)<1,overflow:document.documentElement.scrollWidth>innerWidth,mounted:Number(document.querySelector('.search-viewport').dataset.mountedCount),header:header.width,row:row.width,principalHeight:row.height,principalCenter:row.y+row.height/2,actions};})()`);
 const assertSearchGeometry=geometry=>{assert.ok(Math.abs(geometry.left-28)<1,JSON.stringify(geometry));assert.ok(Math.abs(geometry.right-28)<1,JSON.stringify(geometry));assert.equal(geometry.aligned,true,JSON.stringify(geometry));assert.equal(geometry.overflow,false);assert.ok(geometry.mounted<45,JSON.stringify(geometry));};
 const querySearch=async query=>{await click('.search-form input');await evaluate(`document.querySelector('.search-form input').select()`);await send('Input.insertText',{text:query});await key('Enter');await settle();};

 await send('Page.enable');await send('Runtime.enable');await send('Emulation.setDeviceMetricsOverride',{width:960,height:680,deviceScaleFactor:1,mobile:false});
 await send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});
 await send('Page.navigate',{url:server.resolvedUrls.local[0]});
 for(let i=0;i<100;i++){if(await evaluate('!!document.querySelector(".home .featured")'))break;await new Promise(r=>setTimeout(r,100));}
 if(!await evaluate('!!document.querySelector(".home .featured")')){await screenshot('debug-start');console.log(await evaluate('({text:document.body.innerText,calls:globalThis.fixture?.calls,html:document.body.innerHTML.slice(0,4000)})'));}
 assert.equal(await evaluate('!!document.querySelector(".home .featured")'),true,errors.join('\n'));
 await evaluate('document.fonts.ready');assert.equal(await evaluate(`document.fonts.check('16px Inter')`),true,'bundled Inter must be loaded');await settle();await screenshot('home');console.log('production shell mounted');
 await evaluate(`window.homeNode=document.querySelector('[data-retained-page="feed"]');homeNode.scrollTop=600;homeNode.dispatchEvent(new Event('scroll'));`);await settle();
 // Open a real modal using real keyboard handling, without calling any private App functions.
 await send('Input.dispatchKeyEvent',{type:'keyDown',key:'k',code:'KeyK',modifiers:2});await settle();
 assert.equal(await evaluate('!!document.querySelector(".spotlight")'),true);
 assert.equal(await evaluate('homeNode.hidden===false&&homeNode.inert&&homeNode.getAttribute("aria-hidden")==="true"'),true);
 await screenshot('spotlight-home');await key('Escape');assert.equal(await evaluate('!!document.querySelector(".spotlight")'),false,'closed updater must not intercept Spotlight Escape');
 assert.equal(await evaluate('homeNode.scrollTop'),600);
 await click('.sidebar-row[aria-label="Explorar"],.sidebar-row[aria-label="Explore"]');
 if(!await evaluate('!!document.querySelector(".explore-scroll")')){await screenshot('debug-nav');console.log(await evaluate('({text:document.body.innerText.slice(0,1600),retained:[...document.querySelectorAll("[data-retained-page]")].map(e=>({id:e.dataset.retainedPage,hidden:e.hidden})),spotlight:!!document.querySelector(".spotlight"),calls:fixture.calls.slice(-5),buttons:[...document.querySelectorAll(".sidebar-row")].map(e=>({label:e.getAttribute("aria-label"),rect:e.getBoundingClientRect().toJSON()}))})'));}
 await evaluate(`window.exploreNode=document.querySelector('.explore-scroll');exploreNode.scrollTop=300;exploreNode.dispatchEvent(new Event('scroll'));`);await settle();
 await send('Input.dispatchKeyEvent',{type:'keyDown',key:'k',code:'KeyK',modifiers:2});await settle();await key('Escape');
 assert.equal(await evaluate('exploreNode.scrollTop'),300,'cover/reveal keeps actual Explore offset');
 await click('.sidebar-row[aria-label="Biblioteca"],.sidebar-row[aria-label="Library"]');
 assert.equal(await evaluate('!!document.querySelector(".category-toolbar .heading-actions")'),true);
 await screenshot('library');
 await click('.sidebar-row[aria-label="Inicio"],.sidebar-row[aria-label="Home"]');
 assert.equal(await evaluate('document.querySelector(".home").closest("[data-retained-page]")===homeNode'),true);
 assert.equal(await evaluate('homeNode.scrollTop'),600,'navigation restores Home offset');
 console.log('retained shell/Spotlight keyboard passed');evidence.push('production shell: Home/Explore/Library retained; Spotlight inert/AX and scroll stable');
 // Full search submit through Spotlight.
 await send('Input.dispatchKeyEvent',{type:'keyDown',key:'k',code:'KeyK',modifiers:2});await settle();
 await send('Input.insertText',{text:'homecoming'});await settle();await key('Enter');
 for(let i=0;i<40;i++){if(await evaluate('!!document.querySelector(".search-viewport .principal")'))break;await settle();}
 if(!await evaluate('!!document.querySelector(".search-viewport .principal")')){await screenshot('debug-search-submit');console.log(await evaluate('({spotlight:!!document.querySelector(".spotlight"),input:document.activeElement?.outerHTML,calls:fixture.calls.slice(-10),text:document.body.innerText.slice(-1500)})'));}
 assert.equal(await evaluate('!!document.querySelector(".search-viewport .principal")'),true,errors.join('\n'));
 for(const [width,height,scale] of [[960,680,1],[1280,720,1.25],[1440,900,1.5],[1920,1080,2]]){
  await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:scale,mobile:false});await settle();
  for(const collapsed of [false,true]){
   const current=await evaluate('document.querySelector(".app-frame").classList.contains("sidebar-collapsed")');
   if(current!==collapsed)await click('.sidebar .toolbar-button,aside .toolbar-button');
   const geometry=await searchGeometry();
   assertSearchGeometry(geometry);
   if(width===960&&!collapsed){assert.ok(geometry.principalHeight<=116,JSON.stringify(geometry));assert.ok(geometry.actions.every(action=>Math.abs(action.center-geometry.principalCenter)<1),JSON.stringify(geometry));}
   evidence.push({width,height,scale,collapsed,geometry});
   await screenshot(`search-${width}-${collapsed?'closed':'open'}`);
  }
 }

 console.log('song matrix8 captures passed');
 await evaluate(`{const style=document.createElement('style');style.id='classic-scrollbar';style.textContent='.search-page .results-scroll{overflow-y:scroll!important;scrollbar-width:auto!important;scrollbar-color:auto!important;scrollbar-gutter:stable!important}.search-page .results-scroll::-webkit-scrollbar{width:17px;display:block!important;-webkit-appearance:none;background:#222}.search-page .results-scroll::-webkit-scrollbar-thumb{background:#777}';document.head.append(style);}`);
 await settle();
 let gutterTestMode='native-css-scrollbar';
 if(await evaluate(`(()=>{const e=document.querySelector('.search-page .results-scroll');return e.offsetWidth-e.clientWidth;})()`)!==17){
  // Chrome on macOS may retain overlay scrollbars despite CSS. Reserve the same
  // physical gutter explicitly; report it as a layout simulation, never native QA.
  gutterTestMode='simulated-border-gutter';
  await evaluate(`document.querySelector('#classic-scrollbar').textContent+=' .search-page .results-scroll{scrollbar-width:none!important;scrollbar-gutter:auto!important;border-right:17px solid #333!important;box-sizing:border-box}'`);
  await settle();
 }
 evidence.push({gutterTestMode,width:17,nativeWindows:false});
 for(const kind of ['song','artist','album']){
  await querySearch(kind==='artist'?'kendrick lamar':kind==='album'?'to pimp a butterfly':'homecoming');
  for(const width of [960,1440]){
   await send('Emulation.setDeviceMetricsOverride',{width,height:800,deviceScaleFactor:1,mobile:false});await settle();
   for(const collapsed of [false,true]){
    if(await evaluate('document.querySelector(".app-frame").classList.contains("sidebar-collapsed")')!==collapsed)await click('.sidebar .toolbar-button,aside .toolbar-button');
    const geometry=await searchGeometry();assertSearchGeometry(geometry);if(geometry.gutter!==17)console.log('scrollbar diagnostic',await evaluate(`(()=>{const e=document.querySelector('.search-page .results-scroll');return {offset:e.offsetWidth,client:e.clientWidth,scroll:e.scrollHeight,height:e.clientHeight,css:getComputedStyle(e).cssText,pseudoWidth:getComputedStyle(e,'::-webkit-scrollbar').width,pseudoDisplay:getComputedStyle(e,'::-webkit-scrollbar').display,gutter:getComputedStyle(e).scrollbarGutter};})()`));assert.equal(geometry.gutter,17,JSON.stringify(geometry));
    if(kind==='artist'){
     const artist=await evaluate(`(()=>{const cover=document.querySelector('.principal .cover').getBoundingClientRect(),copy=document.querySelector('.principal .text').getBoundingClientRect(),actions=document.querySelector('.principal .actions').getBoundingClientRect(),container=document.querySelector('.principal-container').clientWidth;return {cover:cover.toJSON(),copy:copy.toJSON(),actions:actions.toJSON(),container};})()`);
     if(artist.container>=680)assert.ok(Math.abs(artist.actions.x-artist.copy.x)<1,JSON.stringify(artist));
     else assert.ok(Math.abs(artist.actions.x-artist.cover.x)<1,JSON.stringify(artist));
    }
    for(const action of geometry.actions){assert.ok(action.h===40||action.h===32,JSON.stringify(geometry));}
    const main=geometry.actions.find(action=>action.h===40),menu=geometry.actions.find(action=>action.h===32);
    if(main&&menu&&Math.abs(main.y-menu.y)<20)assert.ok(Math.abs(main.center-menu.center)<1,JSON.stringify(geometry));
    evidence.push({kind,width,collapsed,gutterTestMode,geometry});
    await screenshot(`classic-${kind}-${width}-${collapsed?'closed':'open'}`);
   }
  }
 }
 console.log('gutter17 /3kinds /12captures passed: '+gutterTestMode);
 await evaluate(`document.querySelector('#classic-scrollbar').remove()`);await querySearch('homecoming');
 await send('Emulation.setDeviceMetricsOverride',{width:960,height:680,deviceScaleFactor:1,mobile:false});await settle();
 await click('.search-form input');
 assert.equal(await evaluate('document.querySelectorAll(".preview-popover .query-suggestion").length'),3);
 assert.equal(await evaluate('document.querySelectorAll(".preview-popover .song-row").length'),2);
 const before=await evaluate('document.querySelector(".principal").getBoundingClientRect().top');
 await click('.search-header h1');assert.equal(await evaluate('!!document.querySelector(".preview-popover")'),false);
 assert.equal(await evaluate('document.querySelector(".principal").getBoundingClientRect().top'),before);
 console.log('preview interactions passed');evidence.push('preview: 3 text suggestions + all musical entries; outside click dismisses without a page jump');
 await evaluate(`window.searchNode=document.querySelector('.results-scroll');searchNode.scrollTop=260000;searchNode.dispatchEvent(new Event('scroll'));`);await settle();
 assert.ok(await evaluate('Number(document.querySelector(".search-viewport").dataset.mountedCount)<45'));
 assert.ok(await evaluate('Number(document.querySelector(".search-viewport .song-row .title").textContent.match(/\\d+/)?.[0])>4000'));
 await screenshot('search-deep');console.log('deep5000 viewport passed');
 // Real fullscreen/lyrics components, synthetic playback and lyric provider.
 await click('.player-bar .panel-shortcuts .panel-shortcut');
 for(let i=0;i<30;i++){if(await evaluate('!!document.querySelector(".lyrics-panel .line")'))break;await settle();}
 assert.equal(await evaluate('!!document.querySelector(".lyrics-panel .line")'),true,errors.join('\n'));
 const fullscreenGeometry=()=>evaluate(`(()=>{const close=document.querySelector('.fullscreen .close-button'),tabs=[...document.querySelectorAll('.fullscreen [role=tab]')],rect=e=>e.getBoundingClientRect().toJSON(),c=rect(close);return {close:c,closeHit:close.contains(document.elementFromPoint(c.x+c.width/2,c.y+c.height/2)),tabs:tabs.map(tab=>{const b=rect(tab);return {id:tab.id,rect:b,hit:tab.contains(document.elementFromPoint(b.x+b.width/2,b.y+b.height/2))};})};})()`);
 const assertFullscreenGeometry=geometry=>{
  assert.equal(geometry.closeHit,true,JSON.stringify(geometry));
  for(const tab of geometry.tabs){const a=geometry.close,b=tab.rect;const overlap=a.left<b.right&&a.right>b.left&&a.top<b.bottom&&a.bottom>b.top;assert.equal(overlap,false,JSON.stringify(geometry));assert.equal(tab.hit,true,JSON.stringify(geometry));}
 };
 for(const width of [960,1440]){
  for(const collapsed of [false,true]){
   console.log('fullscreen matrix',width,collapsed);await click('.fullscreen .close-button');
   await send('Emulation.setDeviceMetricsOverride',{width,height:680,deviceScaleFactor:1,mobile:false});await settle();
   if(await evaluate('document.querySelector(".app-frame").classList.contains("sidebar-collapsed")')!==collapsed)await click('.sidebar .toolbar-button,aside .toolbar-button');
   await click('.player-bar .panel-shortcuts .panel-shortcut');
   const geometry=await fullscreenGeometry();assertFullscreenGeometry(geometry);
   evidence.push({fullscreenLayout:true,width,collapsed,geometry});
   await screenshot(`fullscreen-layout-${width}-${collapsed?'closed':'open'}`);
  }
 }
 await send('Emulation.setDeviceMetricsOverride',{width:960,height:680,deviceScaleFactor:1,mobile:false});await settle();
 assertFullscreenGeometry(await fullscreenGeometry());
 await screenshot('lyrics-new');console.log('lyrics mounted / fullscreen close and tabs do not overlap');

 console.log('lyrics manual wheel');await evaluate('document.querySelector(".lyrics-scroll").dispatchEvent(new WheelEvent("wheel",{deltaY:100,bubbles:true}))');await settle();
 assert.equal(await evaluate('document.querySelector(".lyrics-panel").classList.contains("manual")'),true);
 console.log('lyrics options');await click('.lyrics-panel .more');await screenshot('lyrics-options');
 console.log('lyrics source switch');
 const lyricsMenu=await evaluate(`(()=>{const menu=document.querySelector('.lyrics-panel .menu'),panel=document.querySelector('.lyrics-panel'),last=menu.querySelector('button:last-child');last.scrollIntoView({block:'nearest'});const m=menu.getBoundingClientRect(),p=panel.getBoundingClientRect(),b=last.getBoundingClientRect();return {menuBottom:m.bottom,panelBottom:p.bottom,sourceVisible:b.top>=m.top&&b.bottom<=m.bottom,sourceHit:last.contains(document.elementFromPoint(b.x+b.width/2,b.y+b.height/2))};})()`);
 assert.ok(lyricsMenu.menuBottom<=lyricsMenu.panelBottom,JSON.stringify(lyricsMenu));assert.equal(lyricsMenu.sourceVisible,true,JSON.stringify(lyricsMenu));assert.equal(lyricsMenu.sourceHit,true,JSON.stringify(lyricsMenu));
 await screenshot('lyrics-options-source');await click('.lyrics-panel .menu button:last-child');await settle();
 assert.equal(await evaluate(`document.querySelector('.lyrics-panel .menu button:last-child').textContent.includes('Usar nuevas letras')||document.querySelector('.lyrics-panel .menu button:last-child').textContent.includes('Try new')`),true,'source click changes to Original');
 await screenshot('lyrics-original');
 assert.equal(await evaluate('document.querySelector(".lyrics-panel").classList.contains("manual")'),true,'source switch preserves manual');
 evidence.push('fullscreen: new/Original, options and manual follow state use production components; no audible/native seek claim');
 await key('Escape');
 console.log('account DOM purge');await evaluate('fixture.account()');await settle();
 assert.equal(await evaluate('homeNode.isConnected'),false,'account purges retained private DOM');
 assert.deepEqual(errors,[]);
 await writeFile(path.join(cache,'results.json'),JSON.stringify({host:process.platform,browser:process.env.SIDEB_BROWSER??'Edge',synthetic:true,software,evidence,errors},null,2));
 console.log(JSON.stringify({ok:true,checks:evidence.length,cache}));
}finally{await writeFile(path.join(cache,'browser-stderr.log'),stderr);ws?.close();browser.kill();await server.close();}

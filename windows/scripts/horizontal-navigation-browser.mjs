// Real Svelte components and Chromium layout/input; synthetic metadata, no account/audio.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {createServer} from 'vite';
import {svelte} from '@sveltejs/vite-plugin-svelte';
const root=fileURLToPath(new URL('../',import.meta.url)),cache=path.join(root,'.cache/horizontal-navigation-browser');
await mkdir(cache,{recursive:true});
const fixture=String.raw`<script>
import '$lib/styles/fonts.css';import '$lib/styles/tokens.css';
import Navigation from '$lib/components/common/HorizontalNavigation.svelte';
import Home from '$lib/components/home/HomeView.svelte';import Shelf from '$lib/components/home/HomeShelf.svelte';
import Explore from '$lib/components/explore/ExploreView.svelte';import Search from '$lib/components/search/SearchView.svelte';
import Library from '$lib/components/library/LibraryView.svelte';import Album from '$lib/components/detail/AlbumDetailView.svelte';
import Artist from '$lib/components/detail/ArtistDetailView.svelte';import Related from '$lib/components/fullscreen/RecommendedPanel.svelte';
import {defaults} from '$lib/home/settings';import {emptyProviderSearchData} from '$lib/search/provider';
let mode=$state('home'),active=$state(true),tab=$state('all');let searchScroll=$state(null);
const calls=[];const call=(...args)=>calls.push(args);const noop=()=>{};
const cover='data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160"><rect width="160" height="160" fill="#61419b"/><circle cx="80" cy="80" r="48" fill="#bc8d83"/></svg>');
const card=(i,kind='album')=>({kind,id:kind+'-'+i,title:'Collection '+i,subtitle:'Fixture Artist',artists:'Fixture Artist',artistId:'artist',artistRuns:[{id:'artist',text:'Fixture Artist'}],album:null,albumId:null,thumbnail:cover,duration:'3:20',explicit:false});
const song=i=>({videoId:'song-'+i,setVideoId:'occurrence-'+i,title:'Song '+i,artists:'Fixture Artist',artistId:'artist',artistRuns:[],album:'Album',albumId:'album',thumbnail:cover,duration:'3:20',isVideo:false});
const cards=Array.from({length:30},(_,i)=>card(i)),songs=Array.from({length:5000},(_,i)=>song(i));
localStorage.setItem('sideb.library.v1:arrows',JSON.stringify({version:1,tab:'all',layout:'grid',order:'original',pins:cards.slice(0,8)}));
const chips=Array.from({length:12},(_,i)=>({title:'Category '+i,params:'opaque-'+i}));
const carousels=[{title:'Other versions',items:cards,moreBrowseId:null,moreParams:null}];
const settings=defaults();
const homeSections=[{title:'Speed dial',format:'compactSong',items:Array.from({length:27},(_,i)=>({...card(i,'song'),album:'Album'}))},{title:'Recommended albums',format:'largeCards',items:cards}];
const search={...emptyProviderSearchData(),query:'fixture',lastSearchedQuery:'fixture',hasSearched:true,page:{chips:chips.map((c,i)=>({...c,id:String(i),selected:i===0})),correction:null,sections:[{id:'albums',title:'Albums',layout:'carousel',items:cards,songs:[],actions:[],moreParams:null,moreQuery:null,moreBrowseId:null}],continuation:null}};
const artist={channelId:'artist',name:'Fixture Artist',thumbnail:cover,description:null,subscribers:null,monthlyListeners:null,subscribed:false,radioPlaylistId:null,topSongs:[],topSongsId:null,sections:carousels};
const album={browseId:'album',title:'Fixture Album',artist:'Fixture Artist',artistId:'artist',artistRuns:[],subtitle:null,secondSubtitle:null,description:null,thumbnail:cover,items:[],playlistId:null,inLibrary:false,sections:carousels};
const track={...song(0),duration:200};
const related={loadedVideoId:'song-0',requestIdentity:JSON.stringify(['song-0','artist','album']),contextKey:'fixture',artistName:'Fixture Artist',artistBrowseId:'artist',artistSongs:songs,albumTitle:'Album',albumBrowseId:'album',albumSongs:songs,similarSongs:songs,relatedArtists:cards.map(c=>({...c,kind:'artist'}))};
window.lab={show:value=>{mode=value;active=true},suspend:value=>active=!value,calls};
</script>
<div class="content-column" data-page-scroll>
{#if mode==='home'}<Home {chips} sections={homeSections} selectedChipParams={null} isLoading={false} error={null} onSelectChip={noop} onRetry={noop} onOpenAlbum={id=>call('album',id)} onPlaySong={s=>call('play',s)} onOpenArtist={noop} onOpenPlaylist={noop} hasMore={false} isLoadingMore={false} moreError={null} moreNotice={null} onLoadMore={noop} auth={{state:'ready',name:'Fixture',thumbnail:null}} session="arrows" {settings} kind="albums" albums={cards} playlists={[]} history={[]} onSettings={noop} onKind={noop} interactive={active} libraryError={null} onRetryLibrary={noop} metadata={{}} onVisibleCollections={noop} onCapacity={noop}/>
{:else if mode==='shelf'||mode==='compact'}<Shelf {active} section={{id:mode,title:'Fixture shelf',style:mode==='compact'?'compactSong':'largeCards',items:Array.from({length:5000},(_,i)=>({id:String(i),record:card(i,mode==='compact'?'song':'album')}))}} onPlaySong={s=>call('play',s)} onOpenAlbum={id=>call('album',id)}/>
{:else if mode==='explore'}<Explore {active} data={{route:'discover',items:cards,sections:[],countries:[],detectedCountry:null,regionMessage:null,isLoading:false,error:null,scrollTop:0}} onNavigate={noop} onRefresh={noop} onOpenCard={c=>call('open',c)}/>
{:else if mode==='search'}<Search {active} data={search} bind:contentScrollElement={searchScroll} backendReady currentTrackId={null} isPlaying={false} draftQuery="fixture" preview={{query:"fixture",associatedQuery:"fixture",entries:[],results:null,isLoading:false,error:null}} onDraftChange={noop} onPreviewFocus={noop} onPreviewDismiss={noop} onAction={noop} onSelectParams={noop} onLoadMore={noop} onMore={noop} onSubmit={noop} onRetry={noop} onModeChange={noop} onPlaySong={s=>call('play',s)} onOpenAlbum={noop} onOpenArtist={noop} onOpenPlaylist={noop}/>
{:else if mode==='library'}<Library {active} accountKey="arrows" loggedIn {tab} songs={[]} playlists={cards.map(c=>({...c,kind:'playlist'}))} albums={cards} artists={cards.map(c=>({...c,kind:'artist'}))} loading={false} loadingMore={false} error={null} continuation={null} currentTrackId={null} isPlaying={false} likedIds={new Set()} pendingIds={new Set()} onTab={value=>tab=value} onRefresh={noop} onLoadMore={noop} onPlay={noop} onOpenCard={c=>call('open',c)} onToggleLike={noop} onToggleSaved={noop} onCreatePlaylist={noop} onLogin={noop}/>
{:else if mode==='album'}<Album {album} isLoading={false} error={null} currentTrackId={null} isPlaying={false} loggedIn={false} onRetry={noop} onPlay={noop} onOpenArtist={noop} onOpenAlbum={noop} onOpenCatalog={noop} onToggleLibrary={async()=>{}}/>
{:else if mode==='artist'}<Artist {artist} isLoading={false} error={null} currentTrackId={null} isPlaying={false} loggedIn={false} onRetry={noop} onPlay={noop} onStartRadio={async()=>{}} onToggleSubscription={async()=>{}} onOpenArtist={noop} onOpenAlbum={noop} onOpenCatalog={noop}/>
{:else if mode.startsWith('related')}<div style="height:400px"><Related snapshot={{loading:false,error:null,data:related}} currentTrack={track} isPlaying={false} onRefresh={noop} onPlaySong={s=>call('play',s)} onOpenArtist={noop} onOpenAlbum={noop}/></div>
{:else}<div dir={mode==='rtl'?'rtl':'ltr'}><Navigation label="Mixed"><div class="mixed" data-horizontal-scroll>{#each [180,240,130,310,160,240,180] as width,i}<button style:width={width+'px'} onclick={()=>call('play',i)}>Item {i}</button>{/each}</div></Navigation></div>{/if}
</div>
<style>:global(body){margin:0;background:#1b1b1e;color:white;font-family:var(--sideb-font-family,Inter,sans-serif)}.content-column{height:780px;overflow-y:auto;overflow-x:hidden;min-width:0}.mixed{display:flex;gap:16px;overflow:auto;padding:12px 28px}.mixed button{height:160px;flex:none;background:#61419b;color:white;border:0}.content-column :global(.home){min-height:0}</style>`;
await writeFile(path.join(cache,'Fixture.svelte'),fixture);
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
 ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result)}else if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description??m.params.exceptionDetails.text)});
 const send=(method,params={})=>new Promise((resolve,reject)=>{const key=++id,timer=setTimeout(()=>reject(Error(method+' timeout')),20000);pending.set(key,{resolve:v=>{clearTimeout(timer);resolve(v)},reject:e=>{clearTimeout(timer);reject(e)}});ws.send(JSON.stringify({id:key,method,params}))});
 const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});assert.ok(!r.exceptionDetails,JSON.stringify(r.exceptionDetails));return r.result.value};
 const settle=()=>new Promise(r=>setTimeout(r,180));
 await send('Runtime.enable');await send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});
 await send('Emulation.setDeviceMetricsOverride',{width:1000,height:900,deviceScaleFactor:1,mobile:false});
 await send('Page.navigate',{url:server.resolvedUrls.local[0]});
 for(let i=0;i<300;i++){if(await evaluate('!!window.lab'))break;await settle()}
 assert.ok(await evaluate('!!window.lab'),errors.join('\n'));await evaluate('document.fonts.ready');await settle();
 for(const width of [1000,600]){
   await send('Emulation.setDeviceMetricsOverride',{width,height:900,deviceScaleFactor:width===600?1.5:1,mobile:false});
   for(const mode of ['home','shelf','compact','explore','search','library','album','artist','related','related-similar','related-artists','mixed','rtl']){
     await evaluate(`window.caseMode=${JSON.stringify(mode)};lab.show(${JSON.stringify(mode)})`);await settle();
     if(mode==='related-similar'||mode==='related-artists'){await evaluate(`document.querySelector('[data-rec-axis="y"]').scrollTop=${mode==='related-similar'?436:9999}`);await settle();}
     await evaluate(`window.caseHosts=()=>[...document.querySelectorAll('[data-horizontal-navigation]')].filter(e=>!e.classList.contains('bypass')&&(!['related-similar','related-artists'].includes(window.caseMode)||e.closest('[data-rec-shelf]')?.dataset.recShelf===(window.caseMode==='related-similar'?'similar':'relatedArtists')))`);
     const initial=await evaluate(`(()=>{const nodes=window.caseHosts();return {count:nodes.length,labels:nodes.map(e=>e.dataset.horizontalNavigation),overflow:document.documentElement.scrollWidth>innerWidth}})()`);
     assert.deepEqual(await evaluate(`window.caseHosts().map(host=>({before:getComputedStyle(host,'::before').content,after:getComputedStyle(host,'::after').content,mask:getComputedStyle(host).maskImage,blur:getComputedStyle(host.querySelector('.horizontal-arrow')).backdropFilter})).filter(style=>style.before!=='none'||style.after!=='none'||style.mask!=='none'||style.blur!=='none')`),[],mode+': arrows must not paint edge bands, masks or blur');
     assert.ok(initial.count>0,mode+': missing controls');assert.equal(initial.overflow,false,mode+': outer overflow');
     let moved=0;
     for(let index=0;index<initial.count;index++){
       const geometry=await evaluate(`(()=>{const host=window.caseHosts()[${index}],button=host?.querySelector('[data-horizontal-arrow="next"]');if(!button||button.getAttribute('aria-disabled')==='true')return null;button.scrollIntoView({block:'center'});const box=button.getBoundingClientRect(),target=document.elementFromPoint(box.x+box.width/2,box.y+box.height/2);window.arrowHost=host;window.beforeOffset=host.querySelector('[data-horizontal-scroll]')?.scrollLeft;return {x:box.x+box.width/2,y:box.y+box.height/2,hit:button===target||button.contains(target),width:box.width,height:box.height,calls:lab.calls.length,paged:!host.querySelector('[data-horizontal-scroll]')};})()`);
       if(!geometry)continue;assert.ok(geometry.hit,JSON.stringify({mode,index,geometry}));assert.ok(geometry.width>=40&&geometry.height>=40);
       await send('Input.dispatchMouseEvent',{type:'mousePressed',x:geometry.x,y:geometry.y,button:'left',clickCount:1});await send('Input.dispatchMouseEvent',{type:'mouseReleased',x:geometry.x,y:geometry.y,button:'left',clickCount:1});await settle();
       const after=await evaluate('({left:arrowHost.querySelector("[data-horizontal-scroll]")?.scrollLeft,before:beforeOffset,calls:lab.calls.length,prev:arrowHost.querySelector("[data-horizontal-arrow=previous]").getAttribute("aria-disabled")})');
       assert.equal(after.calls,geometry.calls,mode+': navigation triggered media');assert.equal(after.prev,'false',mode+': previous missing after advancing');if(!geometry.paged)assert.notEqual(after.left,after.before,mode+': did not scroll');moved++;
     }
     evidence.push({width,mode,...initial,moved});
     const shot=await send('Page.captureScreenshot',{format:'png'});await writeFile(path.join(cache,`${mode}-${width}.png`),Buffer.from(shot.data,'base64'));
     console.log(width,mode,'controls',initial.count,'moved',moved);
   }
 }
 // An end reached by keyboard retains its button; forced colors keeps it visible.
 await evaluate('lab.show("mixed")');await settle();await send('Emulation.setEmulatedMedia',{features:[{name:'forced-colors',value:'active'},{name:'prefers-reduced-motion',value:'reduce'}]});
 assert.notEqual(await evaluate('getComputedStyle(document.querySelector(".horizontal-arrow" )).color'), 'rgba(0, 0, 0, 0)');
 assert.deepEqual(errors,[]);await writeFile(path.join(cache,'results.json'),JSON.stringify({synthetic:true,host:process.platform,evidence,errors},null,2));console.log(JSON.stringify({ok:true,cases:evidence.length,errors}));
}finally{ws?.close();browser.kill();await server.close()}

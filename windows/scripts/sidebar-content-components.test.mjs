import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import fs from 'node:fs';
import {mountedSvelteEnvironment} from './helpers/mount-svelte.mjs';
if(!process.execArgv.includes('--conditions=browser')) {
 test('mounted metadata, up next and settings of the side player',()=>{const {NODE_TEST_CONTEXT,...env}=process.env;const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});assert.equal(result.status,0,result.stdout+result.stderr);});
}else{
 const {root,dom,moduleFor,mount,unmount,flushSync}=await mountedSvelteEnvironment('sidebar-content');
 dom.matchMedia=()=>({matches:false,addEventListener(){},removeEventListener(){}});
 dom.__TAURI_INTERNALS__={transformCallback:()=>1,invoke:()=>Promise.resolve(null)};
 const component=name=>moduleFor(path.join(root,'src/lib/components',name)).then(url=>import(url)).then(m=>m.default);
 const settle=async()=>{await new Promise(r=>setTimeout(r,5));flushSync();};
 const entry=(entryId,queueIndex,title)=>({entryId,queueIndex,videoId:'v-'+title,title,artists:'Artist '+title,thumbnail:null,duration:125});
 const track={videoId:'a',title:'Song title',artists:'Singer',artistRuns:[{text:'Singer',id:'UC1'}],artistId:'UC1',album:'The Album',albumId:'MPRE1',thumbnail:null,duration:100};
 const playback=(extra={})=>({isPlaying:true,isLoading:false,position:1,duration:100,generation:1,currentTrack:track,error:null,queue:{items:[entry('a',0,'A'),entry('b',1,'B'),entry('c',2,'C'),entry('d',3,'D')],currentIndex:0,totalCount:4,source:null,revision:1},...extra});

 test('metadata: credits link, optional dislike/like/+/menu buttons, signed-out disables account actions',async()=>{
  const Metadata=await component('playback-sidebar/SidebarTrackMetadata.svelte');const calls=[];
  const handlers={onToggleLike:()=>calls.push('like'),onDislike:()=>calls.push('dislike'),onAddToQueue:()=>calls.push('queue'),onOpenMenu:()=>calls.push('menu'),onOpenArtist:id=>calls.push('artist:'+id),onOpenAlbum:id=>calls.push('album:'+id)};
  const app=mount(Metadata,{target:document.body,props:{session:1,playback:playback(),loggedIn:true,liked:true,...handlers}});flushSync();await settle();
  assert.match(document.body.textContent,/Song title/);
  const buttons=[...document.querySelectorAll('.actions button')];assert.equal(buttons.length,4);
  assert.deepEqual(buttons.map(b=>['like','more'].find(name=>b.classList.contains(name))??'plain'),['plain','like','plain','more'],'order: dislike, like, +, menu');assert.ok(buttons[1].classList.contains('liked'));
  assert.equal(document.querySelector('.like').getAttribute('aria-pressed'),'true');
  for(const b of buttons)b.click();flushSync();assert.deepEqual(calls,['dislike','like','queue','menu']);
  [...document.querySelectorAll('.credit-link')].find(b=>b.textContent==='The Album').click();assert.ok(calls.includes('album:MPRE1'));
  assert.ok(document.querySelector('.title .scroll-title .title-parts'),'title uses the shared marquee viewport');
  assert.ok(document.querySelector('.credits .credit-viewport > .credit-content .album-name'),'artist • album line moves inside a clipped viewport and keeps its links');
  const barDislike=/name === 'dislike'\}[\s\S]*?\sd="([^"]+)"/.exec(fs.readFileSync(path.join(root,'src/lib/components/menu/MenuIcon.svelte'),'utf8'))[1];
  assert.equal(document.querySelector('.actions .dislike-icon path').getAttribute('d'),barDislike,'dislike glyph is the one in the bottom bar menu (FIX-339)');
  await unmount(app);
  const mac=mount(Metadata,{target:document.body,props:{session:1,playback:playback(),loggedIn:false,onToggleLike:handlers.onToggleLike,onOpenMenu:handlers.onOpenMenu}});flushSync();await settle();
  assert.equal(document.querySelectorAll('.actions button').length,2,'omitting callbacks gives the macOS heart + menu layout');
  assert.equal(document.querySelector('.like').disabled,true,'Like needs a signed-in account');
  await unmount(mac);
  const empty=mount(Metadata,{target:document.body,props:{session:1,playback:playback({currentTrack:null})}});flushSync();await settle();
  assert.match(document.body.textContent,/Sin reproducción|No playback|reproduc/i);await unmount(empty);
  const failing=mount(Metadata,{target:document.body,props:{session:1,playback:playback({error:'No se pudo reproducir'}),onRetryPlayback:()=>calls.push('retry')}});flushSync();await settle();
  document.querySelector('.retry').click();assert.ok(calls.includes('retry'));await unmount(failing);
 });

 test('up next: two next occurrences by identity, play by queue index, view queue, empty state',async()=>{
  const Up=await component('playback-sidebar/SidebarUpcomingQueue.svelte');const played=[];let opened=0;
  const app=mount(Up,{target:document.body,props:{session:1,playback:playback(),onSelectQueue:index=>played.push(index),onOpenQueue:()=>opened++}});flushSync();await settle();
  const rows=[...document.querySelectorAll('.row')];assert.deepEqual(rows.map(row=>row.querySelector('.name').textContent),['B','C']);
  assert.equal(rows[0].querySelector('.duration').textContent,'2:05');
  rows[1].click();assert.deepEqual(played,[2]);document.querySelector('.view-queue').click();assert.equal(opened,1);
  await unmount(app);
  const last=mount(Up,{target:document.body,props:{session:1,playback:playback({queue:{...playback().queue,currentIndex:3}}),onSelectQueue(){}}});flushSync();await settle();
  assert.equal(document.querySelectorAll('.row').length,0);assert.ok(document.querySelector('.empty'));assert.equal(document.querySelector('.view-queue'),null);await unmount(last);
 });

 test('settings: select persists the bottom content and reflects the preference',async()=>{
  const Settings=await component('settings/SidebarLyricsSettings.svelte');
  const {sidebarPreferences}=await import(await moduleFor(path.join(root,'src/lib/player/sidebarPreferences.ts')));
  const app=mount(Settings,{target:document.body});flushSync();await settle();
  const select=document.querySelector('select');assert.equal(select.value,'queue');assert.deepEqual([...select.options].map(o=>o.value),['queue','lyrics']);
  select.value='lyrics';select.dispatchEvent(new dom.Event('change',{bubbles:true}));flushSync();
  assert.equal(sidebarPreferences.currentBottomContent(),'lyrics');
  sidebarPreferences.setBottomContent('queue');flushSync();assert.equal(select.value,'queue');
  assert.match(document.body.textContent,/Panel inferior del reproductor/);await unmount(app);
 });
}

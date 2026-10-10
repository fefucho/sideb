import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const url = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
async function module(file, replacements={}) {
  const source=await readFile(new URL(`../src/lib/${file}.ts`,import.meta.url),'utf8');
  let code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
  for(const [path,replacement] of Object.entries(replacements))code=code.replaceAll(`'${path}'`,JSON.stringify(replacement));
  return url(code);
}
const { likedPlaylistTarget }=await import(await module('menu/sidebar'));
const { menuItems }=await import(await module('menu/policy'));
const metadata=await module('detail/metadata');
const { MenuExecutor }=await import(await module('menu/executor',{'../detail/metadata':metadata}));
const songMetadata=await module('home/songMetadata');
const hooks=await module('menu/hooks',{'svelte':url('export const getContext=()=>globalThis.__sidebSidebarMenuService;'),'./types':await module('menu/types',{'../home/songMetadata':songMetadata})});
const { createMenuHandlers }=await import(hooks);
const detail = {id:'LM',title:'Original provider title',subtitle:'Original subtitle',thumbnail:'original-image',description:null,items:[],continuation:null,owned:true,inLibrary:true,privacy:null,collaborative:false,sort:'default',sortEditable:true};
const facts={loggedIn:true,likedIds:new Set(),playlists:[]};

test('liked collection uses known LM identity and only matching cached metadata/capabilities',()=>{
  assert.equal(likedPlaylistTarget(false,'Tus Me gusta',[],detail),null);
  const fallback=likedPlaylistTarget(true,'Liked Songs',[]);
  assert.deepEqual(fallback,{kind:'playlist',card:{kind:'playlist',id:'LM',title:'Liked Songs',subtitle:null,thumbnail:null,duration:null}});
  assert.equal('detail' in fallback,false);
  const saved={kind:'playlist',id:'VLLM',title:'Saved original',subtitle:'Saved subtitle',thumbnail:'saved-image',duration:null};
  const cached=likedPlaylistTarget(true,'Liked Songs',[saved],detail);
  assert.equal(cached.card,saved);assert.equal(cached.detail,detail);
  assert.equal(likedPlaylistTarget(true,'Tus Me gusta',[],{...detail,id:'another'}).detail,undefined);
  assert.equal(likedPlaylistTarget(true,'Liked Songs',[],detail).card.title,'Original provider title');
});

test('common LM menu offers playback/queue while never exposing destructive or fabricated ownership actions',()=>{
  for(const target of [likedPlaylistTarget(true,'Tus Me gusta',[]),likedPlaylistTarget(true,'Liked Songs',[],detail)]){
    const items=menuItems(target,{playbackScope:'source'},facts,label=>`Localized ${label}`);
    const types=items.filter(item=>item.action).map(item=>item.action.type);
    for(const expected of ['play','shuffle','radio','enqueue-next','enqueue-end','open','share'])assert.ok(types.includes(expected));
    for(const forbidden of ['save-collection','edit-playlist','delete-playlist','sort-playlist'])assert.ok(!types.includes(forbidden));
    assert.ok(items.filter(item=>item.action).every(item=>item.label.startsWith('Localized ')));
    assert.ok(!menuItems(target,{view:'playlist_detail',currentId:'VLLM'},facts).some(item=>item.action?.type==='open'));
  }
});

test('standalone ContextMenu and Shift+F10 dispatch the live guarded target through the common menu service',()=>{
  const previousKeyboard=Object.getOwnPropertyDescriptor(globalThis,'KeyboardEvent');
  const previousService=Object.getOwnPropertyDescriptor(globalThis,'__sidebSidebarMenuService');
  class Keyboard extends Event { constructor(key,shiftKey=false){super('keydown',{cancelable:true});this.key=key;this.shiftKey=shiftKey;} }
  Object.defineProperty(globalThis,'KeyboardEvent',{configurable:true,value:Keyboard});
  const opens=[];let loggedIn=true;let label='Tus Me gusta';
  Object.defineProperty(globalThis,'__sidebSidebarMenuService',{configurable:true,value:{open:(event,target,origin)=>opens.push({event,target,origin})}});
  try {
    const handlers=createMenuHandlers()(()=>likedPlaylistTarget(loggedIn,label,[]),()=>({playbackScope:'source',view:'home'}));
    for(const event of [new Keyboard('ContextMenu'),new Keyboard('F10',true),new Event('contextmenu',{cancelable:true})]){
      handlers[event.type==='keydown'?'onKeyDown':'onContextMenu'](event);assert.equal(event.defaultPrevented,true);
    }
    assert.equal(opens.length,3);assert.ok(opens.every(open=>open.target.card.id==='LM'&&open.origin.playbackScope==='source'));
    for(const event of [new Keyboard('F10'),new Keyboard('Enter'),new Keyboard(' ')])handlers.onKeyDown(event);
    assert.equal(opens.length,3);
    label='Liked Songs';handlers.onKeyDown(new Keyboard('ContextMenu'));assert.equal(opens.at(-1).target.card.title,'Liked Songs');
    loggedIn=false;handlers.onKeyDown(new Keyboard('ContextMenu'));handlers.onContextMenu(new Event('contextmenu',{cancelable:true}));assert.equal(opens.length,4);
  } finally {
    if(previousKeyboard)Object.defineProperty(globalThis,'KeyboardEvent',previousKeyboard);else delete globalThis.KeyboardEvent;
    if(previousService)Object.defineProperty(globalThis,'__sidebSidebarMenuService',previousService);else delete globalThis.__sidebSidebarMenuService;
  }
});

test('LM menu actions reuse cached playlist playback and resolve full occurrence-preserving queue actions',async()=>{
  const songs=[{videoId:'same',setVideoId:'first'},{videoId:'same',setVideoId:'second'}];
  const cached={...detail,items:songs,continuation:'next'};const target=likedPlaylistTarget(true,'Liked Songs',[],cached);
  let played=null,queued=null,resolved=null;let requests=0;
  const executor=new MenuExecutor({begin:()=>()=>true,rpc:async()=>{requests++;throw new Error('unexpected fetch');},
    playPlaylist:async(playlist,valid)=>{assert.equal(valid(),true);played=playlist;},
    resolvePlaylist:async(id,valid,origin)=>{assert.equal(valid(),true);resolved={id,origin};return songs;},
    enqueue:async(items,position)=>queued={items,position}});
  await executor.execute({type:'play'},target,{playbackScope:'source'});
  assert.equal(played,cached);assert.equal(requests,0);
  await executor.execute({type:'enqueue-end'},target,{playbackScope:'source'});
  assert.deepEqual(resolved,{id:'LM',origin:{playbackScope:'source'}});
  assert.deepEqual(queued,{items:songs,position:'end'});assert.equal(queued.items[1].setVideoId,'second');
});

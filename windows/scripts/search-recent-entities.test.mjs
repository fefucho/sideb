import { resolveContentRatingImport } from './helpers/content-rating-module.mjs';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
async function module(file,replace=s=>s){const source=replace(await readFile(new URL(`../src/lib/search/${file}.ts`,import.meta.url),'utf8'));return `data:text/javascript;base64,${Buffer.from(resolveContentRatingImport(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText)).toString('base64')}`;}
const recentsUrl=await module('recents');
const rowsUrl=await module('provider-rows');
const songsUrl=await module('songs');
const categoriesUrl=await module('categories',s=>s.replace("from './provider-rows'",`from '${rowsUrl}'`).replace("from './songs'",`from '${songsUrl}'`));
const presentationUrl=await module('quickPresentation',s=>s.replace("from './categories'",`from '${categoriesUrl}'`).replace("from './provider-rows'",`from '${rowsUrl}'`));
const {SearchRecentStore}=await import(recentsUrl);
const {recordOpenedCard,startRecentSong,recentSuggestion}=await import(await module('recentActions',s=>s.replace("from './recents'",`from '${recentsUrl}'`).replace("from './quickPresentation'",`from '${presentationUrl}'`)));
const card=(kind,id,title=`T ${id}`)=>({kind,id,title,subtitle:`S ${id}`,thumbnail:'thumb',duration:null});
const song=id=>({videoId:id,title:id,artists:'Artist',album:null,duration:null,thumbnail:null,artistId:null,albumId:null,isVideo:false});
function make(storage=new Map()){let clock=1000;let published;const api={getItem:key=>storage.get(key)??null,setItem:(key,value)=>storage.set(key,value)};
 const store=new SearchRecentStore(api,(entries,canUndo)=>published={entries,canUndo},()=>clock++);store.setAccount('guest');return {store,storage,get entries(){return published.entries;},get canUndo(){return published.canUndo;},again:()=>{const next=new SearchRecentStore(api,(entries,canUndo)=>published={entries,canUndo},()=>clock++);next.setAccount('guest');return next;}};}

test('opened entities persist, deduplicate, reorder and reload with their card; songs and bad cards are not entities',()=>{
 const ctx=make();
 ctx.store.recordEntity(card('artist','a1'));ctx.store.recordEntity(card('album','b1'));ctx.store.recordEntity(card('artist','a1'));
 ctx.store.recordEntity(card('song','s1'));ctx.store.recordEntity(card('playlist',''));
 assert.deepEqual(ctx.entries.map(e=>e.key),['entity:artist:a1','entity:album:b1']);
 const reloaded=ctx.again();
 assert.equal(ctx.entries[0].card.title,'T a1');assert.equal(ctx.entries[0].card.thumbnail,'thumb');
 ctx.store.remove('entity:album:b1');assert.equal(ctx.entries.length,1);assert.ok(ctx.canUndo);
 ctx.store.undo();assert.equal(ctx.entries.length,2);
 ctx.store.clear();assert.equal(ctx.entries.length,0);
 void reloaded;
});

test('files without entities still load, malformed entities and unknown kinds are ignored',()=>{
 const storage=new Map([['sideb.searchRecents.v1:guest',JSON.stringify({version:1,entries:[
  {key:'q',kind:'query',query:'old',lastUsedAt:3},
  {key:'x',kind:'artist',lastUsedAt:2},
  {key:'y',kind:'planet',lastUsedAt:1,card:{kind:'planet',id:'p',title:'P'}},
  {key:'z',kind:'album',lastUsedAt:4,card:{kind:'album',id:'b',title:'B'}}]})]]);
 const ctx=make(storage);
 assert.deepEqual(ctx.entries.map(e=>e.key),['entity:album:b','query:old']);
});

test('recordOpenedCard records only artists, albums and playlists',()=>{
 const ctx=make();
 for(const kind of ['artist','album','playlist','song','video','mix'])recordOpenedCard(ctx.store,card(kind,kind));
 assert.deepEqual(ctx.entries.map(e=>e.kind).sort(),['album','artist','playlist']);
});

test('a song is recorded only after its accepted generation really plays; a failed start is not recorded',async()=>{
 const ctx=make();
 await startRecentSong(ctx.store,song('ok'),async(_,accepted)=>{accepted(7);});
 assert.equal(ctx.entries.length,0,'accepted is not played yet');
 ctx.store.confirmPlayback({generation:7,currentTrack:{videoId:'ok'},isPlaying:true,isLoading:false,error:null});
 assert.deepEqual(ctx.entries.map(e=>e.key),['track:youtube:ok']);
 await assert.rejects(startRecentSong(ctx.store,song('bad'),async()=>{throw new Error('no stream');}),/no stream/);
 assert.deepEqual(ctx.entries.map(e=>e.key),['track:youtube:ok'],'the failed song stays out');
 assert.equal(ctx.store.unavailableTrack.videoId,'bad');
});

test('local recents become suggestion entries the quick search can render and remove by key',()=>{
 const ctx=make();
 ctx.store.recordEntity(card('artist','a1'));ctx.store.recordQuery('adhd');
 ctx.store.beginTrack(song('s1'),3);ctx.store.confirmPlayback({generation:3,currentTrack:{videoId:'s1'},isPlaying:true,isLoading:false,error:null});
 const entries=ctx.entries.map(recentSuggestion);
 assert.deepEqual(entries.map(e=>e.id),['local:track:youtube:s1','local:query:adhd','local:entity:artist:a1']);
 assert.equal(entries[0].song.videoId,'s1');assert.equal(entries[2].card.kind,'artist');assert.equal(entries[1].query,'adhd');
 ctx.store.remove(entries[0].id.slice('local:'.length));
 assert.equal(ctx.entries.some(e=>e.key.includes('s1')),false);
});

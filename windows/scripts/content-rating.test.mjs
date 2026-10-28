import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import ts from 'typescript';
import {resolveContentRatingImport} from './helpers/content-rating-module.mjs';
async function load(file) {
 const source=await readFile(new URL(`../src/lib/${file}.ts`,import.meta.url),'utf8');
 const code=resolveContentRatingImport(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText);
 return import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
}
const {contentRating,ratingForIdentity}=await load('contentRating');
const {searchSectionRows}=await load('search/provider-rows');
const {songFromSearchCard,resolveSearchSong}=await load('search/songs');
const {SearchRecentStore}=await load('search/recents');
const {PlaybackController,emptyPlaybackData,prepareCollectionPlayback}=await load('player/controller');
const song=(id,rating)=>({videoId:id,title:'Same title',artists:'Artist',album:null,duration:'3:21',thumbnail:null,isVideo:false,contentRating:rating});

test('provider absence and legacy false never become clean; evidence merges only exact track identities',()=>{
 for(const item of [{},{explicit:false},{contentRating:null},{contentRating:'future'}])assert.equal(contentRating(item),'unknown');
 assert.equal(contentRating({explicit:true}),'explicit');
 assert.equal(contentRating({contentRating:'clean'}),'clean');
 assert.equal(ratingForIdentity(song('one','unknown'),song('two','explicit')),'unknown');
 assert.equal(ratingForIdentity(song('one','unknown'),song('one','explicit')),'explicit');
 assert.equal(ratingForIdentity(song('one','explicit'),song('one','unknown')),'explicit');
});

test('search occurrence pairing preserves each edition and cannot label neighboring songs from an album badge',()=>{
 const cards=[{kind:'album',id:'album',title:'Album',contentRating:'explicit'},
  {kind:'song',id:'clean-id',title:'Same title',contentRating:'clean'},
  {kind:'song',id:'explicit-id',title:'Same title',explicit:true}];
 const songs=[song('clean-id','unknown'),song('explicit-id','unknown'),song('untagged','unknown')];
 const rows=searchSectionRows({items:cards,songs});
 assert.equal(rows[0].song,null);
 assert.equal(rows[1].song.contentRating,'clean');assert.equal(rows[2].song.contentRating,'explicit');
 assert.equal(rows[3].song.contentRating,'unknown');
 assert.deepEqual(rows.slice(1).map(row=>row.song.videoId),['clean-id','explicit-id','untagged']);
 assert.equal(songFromSearchCard(cards[2]).contentRating,'explicit');
 assert.equal(resolveSearchSong(cards[1],{songs,topSongs:[]}).contentRating,'clean');
 assert.equal(songs[0].contentRating,'unknown','presentation must not mutate cached provider payload');
});

test('manual playback preserves clean selection, duplicate occurrences and rating in native command payload',async()=>{
 const calls=[];const selected=[song('same-id','explicit'),song('same-id','clean'),song('other','unknown')];
 const prepared=prepareCollectionPlayback(selected,1,{kind:'playlist',id:'PL-fixture',title:'Fixture'});
 assert.equal(prepared.song.contentRating,'clean');assert.equal(prepared.options.queueIndex,1);
 assert.notEqual(prepared.options.queueItems[0].entryId,prepared.options.queueItems[1].entryId);
 const player=new PlaybackController(async(command,args)=>{calls.push({command,args});return emptyPlaybackData();},async()=>()=>{},()=>{});
 await player.playSong(prepared.song,prepared.options);
 const payload=calls.find(call=>call.command==='play_song').args;
 assert.equal(payload.videoId,'same-id');assert.equal(payload.contentRating,'clean');
 assert.deepEqual(payload.queueItems.map(entry=>entry.contentRating),['explicit','clean','unknown']);
 assert.deepEqual(payload.queueItems.map(entry=>entry.videoId),['same-id','same-id','other']);
});

test('an enriched manual selection upgrades only its exact queue occurrence, preserving unknown duplicate neighbors',async()=>{
 const calls=[];const player=new PlaybackController(async(command,args)=>{calls.push({command,args});return emptyPlaybackData();},async()=>()=>{},()=>{});
 const items=[song('same-id','unknown'),song('same-id','unknown'),song('other','unknown')];
 await player.playSong(song('same-id','explicit'),{queueItems:items,queueIndex:1});
 assert.deepEqual(calls.at(-1).args.queueItems.map(entry=>entry.contentRating),['unknown','explicit','unknown']);
 assert.deepEqual(items.map(entry=>entry.contentRating),['unknown','unknown','unknown']);
 await player.playSong(song('same-id','explicit'),{queueItems:items,queueIndex:2});
 assert.deepEqual(calls.at(-1).args.queueItems.map(entry=>entry.contentRating),['unknown','unknown','unknown']);
});

test('player snapshots retain known evidence for the same ID and account, but cannot transfer it across edition or account',async()=>{
 let update;let native={...emptyPlaybackData(),authGeneration:1,generation:1,currentTrack:{...song('explicit-id','explicit'),duration:201}};
 const player=new PlaybackController(async()=>native,async(event,handler)=>{if(event==='playback-state-changed')update=handler;return()=>{};},()=>{});
 await player.connect();
 update({payload:{...native,currentTrack:{...native.currentTrack,contentRating:'unknown'}}});
 assert.equal(player.snapshot.state.currentTrack.contentRating,'explicit');
 update({payload:{...native,generation:2,currentTrack:{...song('clean-id','unknown'),duration:201}}});
 assert.equal(player.snapshot.state.currentTrack.contentRating,'unknown');
 update({payload:{...native,authGeneration:2,generation:3,currentTrack:{...native.currentTrack,contentRating:'unknown'}}});
 assert.equal(player.snapshot.state.currentTrack.contentRating,'unknown');
});

test('search recent persistence round-trips each rating and migrates unmarked legacy records to unknown',()=>{
 const storage=new Map();const api={getItem:key=>storage.get(key)??null,setItem:(key,value)=>storage.set(key,value)};
 let entries=[];const make=()=>new SearchRecentStore(api,data=>entries=data);
 const store=make();store.setAccount('fixture');
 for(const [i,rating]of ['explicit','clean','unknown'].entries()){
  store.beginTrack(song('id-'+i,rating),i);
  store.confirmPlayback({generation:i,currentTrack:{videoId:'id-'+i},isPlaying:true,isLoading:false,error:null});
 }
 const restored=make();restored.setAccount('fixture');
 assert.deepEqual(entries.map(entry=>entry.track.contentRating),['unknown','clean','explicit']);
 const key=[...storage.keys()][0],legacy=JSON.parse(storage.get(key));
 delete legacy.entries[0].track.contentRating;legacy.entries[0].track.explicit=false;
 delete legacy.entries[1].track.contentRating;legacy.entries[1].track.explicit=true;
 storage.set(key,JSON.stringify(legacy));make().setAccount('fixture');
 assert.deepEqual(entries.map(entry=>entry.track.contentRating),['unknown','explicit','explicit']);
});

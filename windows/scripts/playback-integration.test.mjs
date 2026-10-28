import { resolveContentRatingImport } from './helpers/content-rating-module.mjs';
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import ts from 'typescript';
const source=await readFile(new URL('../src/lib/player/controller.ts',import.meta.url),'utf8');
const output=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {PlaybackController,emptyPlaybackData}=await import(`data:text/javascript;base64,${Buffer.from(resolveContentRatingImport(output)).toString('base64')}`);
const upload={videoId:'upload',title:'Uploaded',artists:'Artist',thumbnail:null,duration:'2:00',isUpload:true};
test('uploaded collection occurrence survives play, enqueue and retry normalization',async()=>{
 const calls=[];
 const controller=new PlaybackController(async(command,args)=>{
  calls.push({command,args});
  return {...emptyPlaybackData(),generation:7,currentTrack:{...upload,duration:120},queue:{...emptyPlaybackData().queue,items:[{...upload,duration:120,entryId:'native-upload'}],currentIndex:0}};
 },async()=>()=>{},()=>{});
 await controller.playSong(upload); await controller.enqueue([upload],'next'); await controller.retry();
 assert.equal(calls[0].args.isUpload,true); assert.equal(calls[0].args.queueItems[0].isUpload,true);
 assert.equal(calls[1].args.items[0].isUpload,true); assert.equal(calls[2].args.isUpload,true);
 assert.equal(calls[2].args.queueEntryId,'native-upload');
});
test('source extension is bound to authoritative attempt and native retry preserves snapshot',async()=>{
 const calls=[];
 const native={...emptyPlaybackData(),generation:19,position:42,queue:{...emptyPlaybackData().queue,revision:8}};
 const controller=new PlaybackController(async(command,args)=>{calls.push({command,args});return native;},async()=>()=>{},()=>{});
 await controller.connect();
 await controller.beginProgressiveSource({kind:'playlist',id:'list',continuation:'private-token'});
 await controller.retrySource();
 assert.deepEqual(calls[1],{command:'begin_queue_source',args:{kind:'playlist',id:'list',continuation:'private-token',expectedGeneration:19}});
 assert.equal(calls[2].command,'retry_queue_source');
 assert.equal(controller.snapshot.state.position,42);
});
test('toggle during a deferred stream selection pauses the native pending attempt',async()=>{
 const calls=[];
 const controller=new PlaybackController(async(command,args)=>{calls.push(command);return {...emptyPlaybackData(),generation:3,isLoading:true};},async()=>()=>{},()=>{});
 await controller.connect(); await controller.toggle();
 assert.equal(calls.at(-1),'pause_playback');
 await controller.setMuted(false); assert.equal(calls.at(-1),'set_playback_muted');
});

test('dislike filtering carries the authoritative attempt to reject late account commands',async()=>{
 const calls=[];
 const controller=new PlaybackController(async(command,args)=>{calls.push({command,args});return {...emptyPlaybackData(),generation:29};},async()=>()=>{},()=>{});
 await controller.connect(); await controller.filterDislikedRecommendations('video');
 assert.deepEqual(calls.at(-1),{command:'filter_disliked_recommendations',args:{videoId:'video',expectedGeneration:29}});
});

test('provider next continuation carries authoritative native generation and source context',async()=>{
 const calls=[];const native={...emptyPlaybackData(),generation:31};
 const controller=new PlaybackController(async(command,args)=>{calls.push({command,args});return native;},async()=>()=>{},()=>{});
 await controller.connect();await controller.beginProgressiveSource({kind:'search-radio',id:'RD-provider',continuation:'private-next-token'});
 assert.deepEqual(calls.at(-1),{command:'begin_queue_source',args:{kind:'search-radio',id:'RD-provider',continuation:'private-next-token',expectedGeneration:31}});
});

test('native radio receives the explicit selected provider occurrence without reordering the page',async()=>{const calls=[];const controller=new PlaybackController(async(command,args)=>{calls.push({command,args});return emptyPlaybackData();},async()=>()=>{},()=>{});await controller.startSourceRadio([{videoId:'first',title:'First'},{videoId:'target',title:'Target'}],{kind:'search-radio',id:'RD-provider',title:'Radio'},'RD-provider',1);assert.equal(calls[0].command,'start_source_radio');assert.equal(calls[0].args.selectedIndex,1);assert.deepEqual(calls[0].args.items.map(item=>item.videoId),['first','target']);});

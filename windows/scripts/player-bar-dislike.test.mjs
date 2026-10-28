import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('../src/lib/player/dislike-current.ts',import.meta.url),'utf8');
const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {dislikeCurrentTrack}=await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
function fixture(overrides={}) {
 const calls=[];let session=1;
 const options={videoId:'captured-song',entryId:'captured-occurrence',session:1,currentSession:()=>session,
  rate:async song=>{calls.push(['rate',song]);return true},removeRecommendation:id=>calls.push(['recommendation',id]),
  filterRecommendations:async id=>{calls.push(['filter',id])},removeEntry:async id=>{calls.push(['entry',id])},...overrides};
 return {options,calls,session:value=>session=value};
}
test('dislike applies rating and recommendation policy before removing the captured occurrence',async()=>{
 const f=fixture();await dislikeCurrentTrack(f.options);
 assert.deepEqual(f.calls,[['rate',{videoId:'captured-song'}],['recommendation','captured-song'],['filter','captured-song'],['entry','captured-occurrence']]);
});
test('failed rating preserves recommendations and queue',async()=>{
 const f=fixture({rate:async()=>false});await dislikeCurrentTrack(f.options);assert.deepEqual(f.calls,[]);
 const error=Error('rating failed');f.options.rate=async()=>{throw error};await assert.rejects(dislikeCurrentTrack(f.options),error);assert.deepEqual(f.calls,[]);
});
test('session changed during rating discards post-rating changes',async()=>{
 const f=fixture();f.options.rate=async()=>{f.session(2);return true};await dislikeCurrentTrack(f.options);assert.deepEqual(f.calls,[]);
});
test('session changed during filtering cannot remove an occurrence in the new account',async()=>{
 const f=fixture();f.options.filterRecommendations=async()=>{f.session(2)};await dislikeCurrentTrack(f.options);
 assert.deepEqual(f.calls,[['rate',{videoId:'captured-song'}],['recommendation','captured-song']]);
});
test('filter failure never removes the queue occurrence, and missing occurrence still rates',async()=>{
 const error=Error('filter failed'),f=fixture({filterRecommendations:async()=>{throw error}});
 await assert.rejects(dislikeCurrentTrack(f.options),error);assert.equal(f.calls.some(call=>call[0]==='entry'),false);
 const noEntry=fixture({entryId:undefined});await dislikeCurrentTrack(noEntry.options);assert.equal(noEntry.calls.some(call=>call[0]==='entry'),false);assert.equal(noEntry.calls[0][0],'rate');
});

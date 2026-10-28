import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const shell=await readFile(new URL('../src/routes/+page.svelte',import.meta.url),'utf8');
const handler=shell.slice(shell.indexOf('  async function playProviderSearchAction'),shell.indexOf('  function playSearchPreviewSong'));
const code=ts.transpileModule(handler,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
function harness(next,play=async()=>{}){
 const calls=[];
 const make=Function('invoke','player','playCollection','extractErrorMessage','selectSearchCard','openCatalog',`let collectionPlayRevision=0,sessionRevision=1,shellError;${code};return {run:playProviderSearchAction,changeAccount:()=>++sessionRevision,changePlayback:()=>++collectionPlayRevision};`);
 const controller=make(async(command,args)=>{calls.push({command,args});return await next;},{startSourceRadio:async(...args)=>calls.push({command:'radio',args}),beginProgressiveSource:async(args)=>calls.push({command:'continue',args})},async(...args)=>{calls.push({command:'play',args});await play();},error=>String(error),card=>calls.push({command:'card',card}),(...args)=>calls.push({command:'browse',args}));
 return {...controller,calls};
}
const songs=[{videoId:'same',setVideoId:'one'},{videoId:'same',setVideoId:'two'}];
const section={id:'section',title:'Provider title'};
test('provider action retains exact endpoint params, occurrence payloads, radio context and next continuation',async()=>{
 const ctx=harness({items:songs,continuation:'next-token',automixPlaylistId:null});
 await ctx.run({videoId:null,playlistId:'RD-provider',params:'shuffle-server-params'},section);
 assert.deepEqual(ctx.calls[0],{command:'search_action',args:{videoId:null,playlistId:'RD-provider',params:'shuffle-server-params'}});
 assert.deepEqual(ctx.calls[1].args,[songs,0,{kind:'search-radio',id:'RD-provider',title:section.title}]);
 assert.deepEqual(ctx.calls[2],{command:'continue',args:{kind:'search-radio',id:'RD-provider',continuation:'next-token'}});
});
test('collection continuation uses next paging without inventing radio context',async()=>{
 const ctx=harness({items:songs,continuation:'collection-next',automixPlaylistId:null});await ctx.run({playlistId:'PL-provider',videoId:null,params:null},section);
 assert.equal(ctx.calls[1].args[2].kind,'search');assert.equal(ctx.calls[2].args.continuation,'collection-next');
});
test('a radio page without token retains its automix endpoint in native radio state',async()=>{
 const ctx=harness({items:songs,continuation:null,automixPlaylistId:'RD-automix'});await ctx.run({videoId:'seed',playlistId:null,params:null},section);
 assert.equal(ctx.calls[1].command,'radio');assert.equal(ctx.calls[1].args[2],'RD-automix');assert.equal(ctx.calls.length,2);
});
test('changing playback while initial page loads discards the stale source',async()=>{let resolve;const pending=new Promise(r=>resolve=r);const ctx=harness(pending);const run=ctx.run({playlistId:'PL-old'},section);ctx.changePlayback();resolve({items:songs,continuation:'stale'});await run;assert.equal(ctx.calls.length,1);});
test('account or playback change during load prevents attaching an old continuation to a new queue',async()=>{
 for(const change of ['changeAccount','changePlayback']){let resolve;const pending=new Promise(r=>resolve=r);const ctx=harness({items:songs,continuation:'stale'},()=>pending);const run=ctx.run({playlistId:'PL-old'},section);await Promise.resolve();await Promise.resolve();ctx[change]();resolve();await run;assert.ok(!ctx.calls.some(c=>c.command==='continue'));}
});

test('browse action with params retains them even when a matching card exists',async()=>{const card={id:'browse',kind:'artist'};const ctx=harness(null);await ctx.run({browseId:'browse',params:'provider-browse-params'},{...section,items:[card]});assert.deepEqual(ctx.calls,[{command:'browse',args:['browse','provider-browse-params',section.title]}]);const plain=harness(null);await plain.run({browseId:'browse',params:null},{...section,items:[card]});assert.deepEqual(plain.calls,[{command:'card',card}]);});
test('video endpoint selects its actual occurrence within the provider page and keeps its original queue order',async()=>{const items=[{videoId:'first'},{videoId:'target'},{videoId:'last'}];const ctx=harness({items,continuation:'token',automixPlaylistId:null});await ctx.run({videoId:'target',playlistId:'PL-provider'},section);assert.equal(ctx.calls[1].args[0],items);assert.equal(ctx.calls[1].args[1],1);});
test('radio without a token starts the explicit video index through the native radio command',async()=>{const items=[{videoId:'first'},{videoId:'target'}];const ctx=harness({items,continuation:null,automixPlaylistId:'RD-automix'});await ctx.run({videoId:'target',playlistId:null},section);assert.equal(ctx.calls[1].command,'radio');assert.equal(ctx.calls[1].args[0],items);assert.equal(ctx.calls[1].args[3],1);});

import { resolveContentRatingImport } from './helpers/content-rating-module.mjs';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
async function module(file){const source=await readFile(new URL(`../src/lib/search/${file}.ts`,import.meta.url),'utf8');return `data:text/javascript;base64,${Buffer.from(resolveContentRatingImport(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText)).toString('base64')}`;}
const {ProviderPreviewController}=await import(await module('provider-preview'));
const tick=()=>new Promise(resolve=>setTimeout(resolve,0));
// A scheduler that keeps every timer so a test can settle them in the order a real clock would.
function scheduler(){const timers=new Map();let next=1;return {timers,
 api:{setTimeout(callback,delay){const id=next++;timers.set(id,{callback,delay});return id;},clearTimeout(id){timers.delete(id);}},
 fire(delay){for(const [id,timer] of [...timers])if(timer.delay===delay){timers.delete(id);timer.callback();}}};}
const page=id=>({chips:[],correction:null,sections:[{id,title:'',layout:'top',items:[],songs:[],actions:[]}],continuation:null});

test('a full search runs once the query settles, without history, after the suggestions',async()=>{
 const calls=[];let data;const clock=scheduler();
 const preview=new ProviderPreviewController(async(command,args)=>{calls.push({command,args});return command==='search_page'?page('live'):{entries:[]};},next=>data=next,clock.api);
 preview.setQuery('kanye');
 assert.deepEqual(calls,[],'nothing is requested while typing');
 clock.fire(150);await tick();
 assert.deepEqual(calls.map(call=>call.command),['search_suggestions_page'],'the full search has its own delay');
 clock.fire(250);await tick();
 assert.deepEqual(calls.map(call=>call.command),['search_suggestions_page','search_page']);
 assert.deepEqual(calls[1].args,{query:'kanye',params:null,recordHistory:false,ignoreSpelling:false});
 assert.equal(data.pageQuery,'kanye');assert.equal(data.page.sections[0].id,'live');
});

test('typing again before the delay never sends the full search for the earlier text',async()=>{
 const calls=[];const clock=scheduler();
 const preview=new ProviderPreviewController(async command=>{calls.push(command);return command==='search_page'?page('x'):{entries:[]};},()=>{},clock.api);
 preview.setQuery('ka');clock.fire(150);await tick();
 preview.setQuery('kan');           // cancels the pending full search for «ka»
 clock.fire(250);await tick();
 assert.deepEqual(calls,['search_suggestions_page'],'«ka» never reached the full search');
});

test('a reply for an obsolete query or after a reset is dropped, and a repeated query uses the cache',async()=>{
 const calls=[];let data;const clock=scheduler();let release;
 const slow=new Promise(resolve=>release=resolve);
 const preview=new ProviderPreviewController(async(command,args)=>{calls.push(command);if(command==='search_page')return args.query==='old'?slow:page('fresh');return {entries:[]};},next=>data=next,clock.api);
 preview.setQuery('old');clock.fire(150);await tick();clock.fire(250);await tick();
 preview.reset();release(page('stale'));await tick();
 assert.equal(data.page,null,'a reply after a reset is not shown');
 preview.setQuery('new');clock.fire(150);await tick();clock.fire(250);await tick();
 assert.equal(data.page.sections[0].id,'fresh');
 const before=calls.length;
 preview.setQuery('');preview.setQuery('new');clock.fire(150);await tick();clock.fire(250);await tick();
 assert.equal(calls.filter(command=>command==='search_page').length,2,'«new» was not requested a second time within a minute');
 assert.ok(calls.length>=before);
});

test('a failing full search leaves the suggestions untouched',async()=>{
 let data;const clock=scheduler();
 const preview=new ProviderPreviewController(async command=>{if(command==='search_page')throw new Error('offline');return {entries:[{id:'e',kind:'text',query:'x',runs:[],feedbackToken:null,card:null,song:null}]};},next=>data=next,clock.api);
 preview.setQuery('x');clock.fire(150);await tick();clock.fire(250);await tick();
 assert.equal(data.entries.length,1);assert.equal(data.page,null);assert.equal(data.error,null);
});

import { resolveContentRatingImport } from './helpers/content-rating-module.mjs';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
async function module(file,replace=s=>s){const source=replace(await readFile(new URL(`../src/lib/search/${file}.ts`,import.meta.url),'utf8'));return `data:text/javascript;base64,${Buffer.from(resolveContentRatingImport(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText)).toString('base64')}`;}
const legacy=await module('controller');
const rowsUrl=await module('provider-rows');const songsUrl=await module('songs');
const categoriesUrl=await module('categories',s=>s.replace("from './provider-rows'",`from '${rowsUrl}'`).replace("from './songs'",`from '${songsUrl}'`));
const {ProviderSearchController}=await import(await module('provider',s=>s.replace("from './controller'",`from '${legacy}'`).replace("from './categories'",`from '${categoriesUrl}'`)));
const {projectSearchDocument,estimateSearchEntryHeight,searchEntryCanFocus}=await import(await module('document',s=>s.replace("from './provider-rows'",`from '${rowsUrl}'`).replace("from './categories'",`from '${categoriesUrl}'`)));
const {categoryPage,GRID_HEIGHT,LOADING_HEIGHT}=await import(categoriesUrl);
const tick=()=>new Promise(resolve=>setTimeout(resolve,0));
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {resolve,reject,promise};};
const card=(kind,id,title=`T ${id}`,subtitle=null)=>({kind,id,title,subtitle,thumbnail:null,duration:null});
const song=id=>({videoId:id,title:`T-${id}`,artists:'A',album:null,duration:'3:00',thumbnail:null,isVideo:false,artistId:null,albumId:null});
const section=(id,rest={})=>({id,title:'',layout:'list',items:[],songs:[],moreQuery:null,moreParams:null,moreBrowseId:null,actions:[],...rest});
const chips=titles=>titles.map(title=>({id:title,title,params:`params-${title}`,selected:false}));
const mainPage=(extra={})=>({chips:chips(['Songs','Artists','Videos','Albums','Community playlists','Featured playlists']),correction:null,continuation:null,sections:[section('mixed',{items:[card('artist','a','Artist','Artist')]})],...extra});
const pageFor=()=>({chips:[],correction:null,continuation:null,sections:[section('s',{items:[card('song','x')],songs:[song('x')]})]});

async function started(rpc){let data;const controller=new ProviderSearchController(rpc,next=>data=next);await controller.execute('kendrick');return {controller,get data(){return data;}};}

test('one chip request per category, at most three at once, without history, published as they arrive',async()=>{
 const calls=[];let active=0,peak=0;const gates=[];
 const rpc=async(command,args)=>{
  if(command==='search_page'&&args.params===null)return mainPage();
  calls.push({command,args});active++;peak=Math.max(peak,active);const gate=deferred();gates.push(gate);await gate.promise;active--;return pageFor();
 };
 const ctx=await started(rpc);
 ctx.controller.loadCategories(true);await tick();
 assert.equal(peak,3,'never more than three in flight');
 assert.deepEqual(ctx.data.categories.pending.length,6,'every wanted category is pending first');
 gates[0].resolve();await tick();
 assert.equal(ctx.data.categories.pending.length,5);assert.ok(ctx.data.categories.chipPages.songs,'the first reply is already published');
 for(let round=0;round<4;round++){for(const gate of gates)gate.resolve();await tick();await tick();}
 assert.equal(ctx.data.categories.pending.length,0);
 assert.ok(calls.every(call=>call.args.recordHistory===false&&call.args.query==='kendrick'));
 assert.deepEqual(calls.map(call=>call.args.params).sort(),['params-Artists','params-Community playlists','params-Featured playlists','params-Albums','params-Songs','params-Videos'].sort());
});

test('asking again for the same page, or for a filtered page, sends nothing more',async()=>{
 let extra=0;const rpc=async(command,args)=>{if(command==='search_page'&&args.params===null)return mainPage();extra++;return pageFor();};
 const ctx=await started(rpc);
 ctx.controller.loadCategories(true);await tick();await tick();const first=extra;
 ctx.controller.loadCategories(true);await tick();
 assert.equal(extra,first,'once per provider page');
 await ctx.controller.selectParams('params-Songs');extra=0;
 ctx.controller.loadCategories(true);await tick();
 assert.equal(extra,0,'a chip page is already one category');
});

test('a newer search drops the late replies of the previous one; a failing category does not stop the others',async()=>{
 const late=deferred();let calls=0;
 const rpc=async(command,args)=>{
  if(command==='search_page'&&args.params===null)return args.query==='kendrick'?mainPage():mainPage({sections:[section('m2',{items:[card('artist','b','Other','Artist')]})]});
  calls++;if(args.params==='params-Songs'&&args.query==='kendrick')return late.promise;if(args.params==='params-Artists')throw new Error('offline');return pageFor();
 };
 const ctx=await started(rpc);
 ctx.controller.loadCategories(true);await tick();
 assert.ok(ctx.data.categories.pending.includes('songs'));
 await ctx.controller.execute('other');                    // new search: a new provider page
 late.resolve(pageFor());await tick();
 assert.equal(ctx.data.categories.chipPages.songs,undefined,'the late «Songs» reply of «kendrick» is not shown for «other»');
 ctx.controller.loadCategories(true);await tick();await tick();await tick();
 assert.equal(ctx.data.categories.pending.length,0,'the failure did not leave a placeholder stuck');
 assert.equal(ctx.data.categories.chipPages.artists,undefined);assert.ok(ctx.data.categories.chipPages.albums);
});

test('the corrected query is used for the category requests when a correction was applied',async()=>{
 const queries=[];const rpc=async(command,args)=>{if(command==='search_page'&&args.params===null)return mainPage({correction:{query:'kanye west',applied:true,params:null,originalQuery:'kany west',originalParams:null}});queries.push(args.query);return pageFor();};
 const ctx=await started(rpc);ctx.controller.loadCategories(true);await tick();await tick();
 assert.ok(queries.length&&queries.every(query=>query==='kanye west'));
});

test('category sections become grid, carousel and placeholder entries with constant heights',()=>{
 const page=categoryPage({...mainPage(),sections:[section('m',{items:[card('artist','a','A','Artist'),card('song','s1')],songs:[song('s1')]})]},{chipPages:{},pending:['albums']},category=>category);
 const entries=projectSearchDocument(page);
 const kinds=entries.map(entry=>entry.kind);
 assert.ok(kinds.includes('grid')&&kinds.includes('carousel')&&kinds.includes('loading')&&kinds.includes('heading'));
 const grid=entries.find(entry=>entry.kind==='grid'),loading=entries.find(entry=>entry.kind==='loading');
 assert.equal(estimateSearchEntryHeight(grid,1000),GRID_HEIGHT);assert.equal(estimateSearchEntryHeight(loading,1000),LOADING_HEIGHT);
 assert.equal(searchEntryCanFocus(loading,false),false,'a placeholder is never a focus stop');
});

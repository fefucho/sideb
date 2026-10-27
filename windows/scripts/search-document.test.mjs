import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
async function module(file,replace=source=>source){const source=replace(await readFile(new URL(`../src/lib/search/${file}.ts`,import.meta.url),'utf8'));return `data:text/javascript;base64,${Buffer.from(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText).toString('base64')}`;}
const rowsUrl=await module('provider-rows');
const {projectSearchSection}=await import(rowsUrl);
const {projectSearchDocument}=await import(await module('document',source=>source.replace("from './provider-rows'",`from '${rowsUrl}'`)));
const {SearchViewportGeometry}=await import(await module('viewport'));
const {visibleSearchSuggestions}=await import(await module('suggestions'));

test('5000 mixed occurrences pair in linear work, including duplicate IDs and unmatched payloads',()=>{
 let reads=0;
 const songs=Array.from({length:5000},(_,index)=>({get videoId(){reads++;return `song-${index%77}`;},setVideoId:`occurrence-${index}`,library:{addToken:`token-${index}`},artistRuns:[{text:`Artist ${index}`,id:`artist-${index}`}]}));
 const section={id:'large',title:'',layout:'list',items:songs.slice(0,4900).map((song,index)=>({kind:index%2?'video':'song',id:song.videoId})),songs,actions:[]};
 section.items.push({kind:'song',id:'missing-payload'});
 reads=0;
 const projection=projectSearchSection(section);
 assert.equal(projection.remaining.length,5001);
 assert.equal(reads,5000,'one videoId read per payload; matching never scans the song array');
 for(let index=0;index<4900;index++)assert.equal(projection.remaining[index].song,songs[index]);
 assert.equal(projection.remaining[4900].song,null);
 assert.equal(projection.remaining[4901].song,songs[4900]);
 assert.equal(projectSearchSection(section),projection);assert.equal(reads,5000,'playback reuses the projection');
});

test('document omits empty and duplicate principal headings and append reuses old entries',()=>{
 const principal={id:'principal',title:'Same title',layout:'top',items:[{id:'artist',kind:'artist'}],songs:[],actions:[],primaryItemIndex:0,relatedItemIndices:[],moreParams:'opaque'};
 const list={id:'empty-title',title:' ',layout:'list',items:[],songs:[{videoId:'repeat',setVideoId:'a'},{videoId:'repeat',setVideoId:'b'}],actions:[]};
 const page={sections:[principal,list]};
 const first=projectSearchDocument(page);
 assert.deepEqual(first.map(entry=>entry.kind),['heading','principal','row','row']);
 assert.equal(first[0].showTitle,false);assert.equal(first[0].section.moreParams,'opaque');
 assert.notEqual(first[2].key,first[3].key);
 assert.equal(projectSearchDocument(page),first);
 const appended=projectSearchDocument({...page,sections:[...page.sections,{...list,id:'append'}]});
 assert.equal(appended.length,6);first.forEach((entry,index)=>assert.equal(appended[index],entry));
});

test('mismatched ordinals never consume an ambiguous duplicate payload and preserve unmatched songs',()=>{
 const songs=[{videoId:'X',setVideoId:'x0'},{videoId:'X',setVideoId:'x1'},{videoId:'A',setVideoId:'a'}];
 const section={id:'ambiguous',title:'',layout:'list',items:[{kind:'song',id:'X'},{kind:'song',id:'A'},{kind:'song',id:'X'}],songs,actions:[]};
 const rows=projectSearchSection(section).remaining;
 assert.deepEqual(rows.map(row=>row.song?.setVideoId??null),['x0','a',null,'x1']);
 assert.equal(rows[2].card.id,'X');assert.equal(rows[3].card,null);
 const unique={...section,items:[{kind:'song',id:'A'},{kind:'song',id:'A'}],songs:[songs[2]]};
 assert.deepEqual(projectSearchSection(unique).remaining.map(row=>row.song?.setVideoId??null),['a',null],'one payload is never attached to two card occurrences');
});

test('geometry retains row4500 through early height corrections, append and width changes',()=>{
 const items=Array.from({length:5000},(_,index)=>({key:`occurrence-${index}`}));
 const geometry=new SearchViewportGeometry();geometry.setItems(items,1000,'es',()=>58);
 const initialTop=4500*58+17,anchor=geometry.anchor(initialTop);
 const range=geometry.range(initialTop,680);
 assert.ok(range.end-range.start<=25);assert.ok(range.start<=4500&&range.end>4500);
 geometry.measure(new Map([['occurrence-0',112],['occurrence-1',210]]));
 assert.equal(geometry.position(anchor),initialTop+54+152);
 geometry.setItems([...items,{key:'appended'}],1000,'es',()=>58);
 assert.equal(geometry.position(anchor),initialTop+206);
 geometry.setItems([...items,{key:'appended'}],600,'es',()=>80);
 assert.equal(geometry.position(anchor),4500*80+17);
 geometry.setItems(items,1000,'es',()=>58);
 assert.equal(geometry.position(anchor),initialTop+206,'returning to measured width reuses cached heights');
 geometry.setItems([{key:items[0].key},...items.slice(1)],1000,'es',()=>58);
 assert.equal(geometry.position(anchor),initialTop+152,'replaced content with the same occurrence key invalidates its stale measurement');
 assert.equal(geometry.indexAt(0),0);assert.equal(geometry.range(0,0).start,0);
});

test('typed suggestions share a three-text policy and preserve every entity and deletion token',()=>{
 const texts=Array.from({length:6},(_,index)=>({id:`text-${index}`,kind:index%2?'history':'text',feedbackToken:`remove-${index}`}));
 const music=[{id:'same',kind:'media',song:{setVideoId:'first'}},{id:'same',kind:'media',song:{setVideoId:'second'}}];
 const entries=[...texts,...music];
 const visible=visibleSearchSuggestions(entries,' homecoming ');
 assert.deepEqual(visible,[...texts.slice(0,3),...music]);assert.equal(entries.length,8);
 assert.equal(visibleSearchSuggestions(entries,'  '),entries);
 const mixed=[music[0],texts[0],music[1],...texts.slice(1)];
 assert.deepEqual(visibleSearchSuggestions(mixed,'q'),[music[0],texts[0],music[1],texts[1],texts[2]]);
});

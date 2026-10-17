import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const source = await readFile(new URL('../src/lib/library/preferences.ts', import.meta.url),'utf8');
const settingsSource=await readFile(new URL('../src/lib/home/settings.ts',import.meta.url),'utf8');
const settingsOutput=ts.transpileModule(settingsSource,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const settingsUrl=`data:text/javascript;base64,${Buffer.from(settingsOutput).toString('base64')}`;
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText.replace("'../home/settings'",JSON.stringify(settingsUrl));
const {readLibraryPreferences,writeLibraryPreferences,libraryDefaults,orderedLibraryCards,libraryKey}=await import(`data:text/javascript;base64,${Buffer.from(compiled).toString('base64')}`);
const card=(id,title,kind='album',subtitle=null)=>({id,title,kind,subtitle,thumbnail:null});
const storage=()=>{const data=new Map();return {getItem:key=>data.get(key)??null,setItem:(key,value)=>data.set(key,value)};};
test('account partition preserves pinned order and preferences without sharing another account',()=>{
 const store=storage(); const first=card('same','Album'),second=card('same','Playlist','playlist');
 writeLibraryPreferences(store,'channel:a',{...libraryDefaults(),tab:'albums',layout:'list',order:'name',pins:[second,first]});
 assert.deepEqual(readLibraryPreferences(store,'channel:a').pins.map(libraryKey),['playlist:same','album:same']);
 assert.equal(readLibraryPreferences(store,'channel:a').tab,'albums');
 assert.deepEqual(readLibraryPreferences(store,'channel:b'),libraryDefaults());
});
test('corrupt/versioned records and invalid pins recover without losing usable settings',()=>{
 const store=storage(); store.setItem('sideb.library.v1:a','{broken');assert.deepEqual(readLibraryPreferences(store,'a'),libraryDefaults());
 store.setItem('sideb.library.v1:a',JSON.stringify({version:2,tab:'songs'}));assert.deepEqual(readLibraryPreferences(store,'a'),libraryDefaults());
 store.setItem('sideb.library.v1:a',JSON.stringify({...libraryDefaults(),tab:'albums',pins:[card('a','A'),card('a','duplicate'),null,{id:'bad'},card('a','P','playlist')]}));
 assert.deepEqual(readLibraryPreferences(store,'a').pins.map(libraryKey),['album:a','playlist:a']);
 assert.equal(readLibraryPreferences(store,'a').tab,'albums');
});
test('original provider order survives sorting and local matching without mutating source',()=>{
 const cards=[card('b','Beta','album','Zed'),card('a','Alpha','album','Ada'),card('c','ALPHA','album','Zed')];
 assert.deepEqual(orderedLibraryCards(cards,'','name').map(c=>c.id),['a','c','b']);
 assert.deepEqual(orderedLibraryCards(cards,'','original').map(c=>c.id),['b','a','c']);
 assert.deepEqual(orderedLibraryCards(cards,' zed ','artist').map(c=>c.id),['b','c']);
 assert.deepEqual(cards.map(c=>c.id),['b','a','c']);
});
test('persisted pins contain navigation metadata but no temporary action tokens or stream URLs',()=>{
 const store=storage(); const raw={...card('x','X'),streamUrl:'secret',token:'temporary'};
 writeLibraryPreferences(store,'a',{...libraryDefaults(),pins:[raw]});
 const saved=readLibraryPreferences(store,'a').pins[0];assert.equal(saved.streamUrl,undefined);assert.equal(saved.token,undefined);
});
const controllerSource=await readFile(new URL('../src/lib/account/controller.ts',import.meta.url),'utf8');
const controllerOutput=ts.transpileModule(controllerSource,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {AccountController}=await import(`data:text/javascript;base64,${Buffer.from(controllerOutput).toString('base64')}`);
test('All loads each collection once and changing loaded tabs does not request them again',async()=>{
 const calls=[];let data;
 const controller=new AccountController(async command=>{calls.push(command);return [card('b','Beta'),card('a','Alpha')];},next=>data=next);
 controller.reset(true);await controller.load('all');
 assert.deepEqual(calls.sort(),['get_library_albums','get_library_artists','get_library_playlists']);
 controller.setTab('albums');controller.setTab('artists');controller.setTab('all');await Promise.resolve();
 assert.equal(calls.length,3);assert.deepEqual(data.originalAlbums.map(c=>c.id),['b','a']);
});

test('playlist navigation prefixes and mix aliases share one local pin identity',()=>{
 const store=storage();writeLibraryPreferences(store,'a',{...libraryDefaults(),pins:[card('VLPL123','One','playlist'),card('PL123','Alias','mix'),card('PL123','Album','album')]});
 assert.deepEqual(readLibraryPreferences(store,'a').pins.map(libraryKey),['playlist:PL123','album:PL123']);
 assert.equal(libraryKey(card('VLPL123','One','playlist')),libraryKey(card(' PL123 ','Alias','mix')));
});

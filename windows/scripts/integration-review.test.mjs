import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import ts from 'typescript';
const load=async path=>{
  const source=await readFile(new URL(path,import.meta.url),'utf8');
  const js=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(js).toString('base64')}`);
};
const {AccountController}=await load('../src/lib/account/controller.ts');
const {projectTracks,projectedPlayback}=await load('../src/lib/detail/projection.ts');
const {collectionEntryId}=await load('../src/lib/player/controller.ts');
const presentationSource=await readFile(new URL('../src/lib/home/presentation.ts',import.meta.url),'utf8');
const presentationJs=ts.transpileModule(presentationSource,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const presentationUrl=`data:text/javascript;base64,${Buffer.from(presentationJs).toString('base64')}`;
const homeSource=(await readFile(new URL('../src/lib/home/controller.ts',import.meta.url),'utf8')).replace("'./presentation'",JSON.stringify(presentationUrl));
const homeJs=ts.transpileModule(homeSource,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {HomeController}=await import(`data:text/javascript;base64,${Buffer.from(homeJs).toString('base64')}`);
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return{promise,resolve};};
const song=(id,title=id)=>({videoId:id,title,artists:'Artist',album:null,albumId:null,artistId:null,thumbnail:null,duration:null,isVideo:false});
const playlist=(id,items)=>({id,title:id,items,continuation:null,owned:false,inLibrary:true});

test('sorted playlist header starts the first song in chosen order',async()=>{
  const source=[song('z','Z'),song('a','A')];
  const component=await readFile(new URL('../src/lib/components/detail/PlaylistDetailView.svelte',import.meta.url),'utf8');
  // Evaluate the actual header selection expression with the same view data.
  const expression=component.match(/class="play"[^\n]+onclick=\{\(\) => onPlay\(([^,]+), false, order\)/)?.[1];
  assert.ok(expression,'header Play expression must remain reviewable');
  const ordered=projectTracks(source,'','title'),projection=ordered;
  const index=Function('ordered','projection',`return ${expression}`)(ordered,projection);
  const queue=projectedPlayback(source,index,'title');
  assert.equal(queue.items[queue.index].videoId,'a');
});

test('restoring LM snapshot after unlike does not resurrect removed track',async()=>{
  let data;const original=song('removed');
  const account=new AccountController(async command=>command==='get_playlist'?playlist('LM',[original]):[],next=>data=next);
  account.reset(true);await account.openPlaylist('LM');await account.hydrateLikes();
  const snapshot=account.captureNavigation();await account.toggleLike(original);
  assert.equal(data.playlist.items.length,0);
  account.restoreNavigation(snapshot);
  assert.equal(data.playlist.items.length,0);
});

test('history record does not change identity of the occurrence already playing',async()=>{
  let data;const older=song('old'),other=song('other');
  const account=new AccountController(async command=>command==='get_history'?[{title:'Yesterday',items:[older,other]}]:[],next=>data=next);
  account.reset(true);await account.load('history');
  const before=data.history.flatMap(group=>group.items),chosen=before[1],source={kind:'history',id:'history',title:'History'};
  const entryId=collectionEntryId(source,chosen,1);
  account.recordPlayback(chosen);
  const after=data.history.flatMap(group=>group.items),originalIndex=after.indexOf(chosen,1);
  assert.ok(originalIndex>=0);
  assert.equal(collectionEntryId(source,after[originalIndex],originalIndex),entryId);
});

test('freshly reopened playlist cannot select a different occurrence from stale complete cache',async()=>{
  let data,version=0;const a={...song('a'),setVideoId:'set-a'},b={...song('b'),setVideoId:'set-b'};
  const account=new AccountController(async command=>command==='get_playlist'?playlist('P',version?[b,a]:[a,b]):[],next=>data=next);
  account.reset(true);await account.openPlaylist('P');await account.resolvePlaylistTracks('P');
  version++;await account.openPlaylist('P');
  assert.equal(data.playlist.items[0].setVideoId,'set-b');
  const complete=await account.resolvePlaylistTracks('P');
  const selection=projectedPlayback(complete,0,'title');
  assert.equal(selection.items[selection.index].setVideoId,'set-b');
});

test('an older playback continuation cannot repopulate the cache after a fresh playlist open',async()=>{
  const pending=deferred();let version=0;
  const a={...song('a'),setVideoId:'set-a'},b={...song('b'),setVideoId:'set-b'},c={...song('c'),setVideoId:'set-c'};
  const account=new AccountController(async command=>{
    if(command==='get_playlist')return version?playlist('P',[b,a]):{...playlist('P',[a]),continuation:'old-page'};
    if(command==='get_playlist_continuation')return pending.promise;
    return [];
  },()=>{});
  account.reset(true);await account.openPlaylist('P');
  const oldPlayback=account.resolvePlaylistTracks('P',()=>true,true);
  version++;await account.openPlaylist('P');
  pending.resolve({items:[c],continuation:null});
  assert.deepEqual((await oldPlayback).map(item=>item.setVideoId),['set-a','set-c'],'valid playback keeps its own captured source');
  const current=await account.resolvePlaylistTracks('P');
  assert.deepEqual(current.map(item=>item.setVideoId),['set-b','set-a']);
});

test('history reply requested before playback cannot discard the accepted new listen',async()=>{
  const pending=deferred();let data;
  const account=new AccountController(async()=>pending.promise,next=>data=next);
  account.reset(true);const request=account.load('history');account.recordPlayback(song('new-listen'));
  pending.resolve([{title:'Yesterday',items:[song('older')]}]);await request;
  assert.ok(data.history.flatMap(group=>group.items).some(item=>item.videoId==='new-listen'));
});

test('pending history retains separate repeated listens with their original occurrence IDs',async()=>{
  const pending=deferred();let data;const account=new AccountController(async()=>pending.promise,next=>data=next);
  account.reset(true);const request=account.load('history');account.recordPlayback(song('repeat'));account.recordPlayback(song('repeat'));
  const identities=data.history[0].items.map(item=>item.historyOccurrenceId);
  pending.resolve([{title:'Today',items:[song('repeat')]}]);await request;
  assert.equal(data.history[0].items.length,3);assert.deepEqual(data.history[0].items.slice(0,2).map(item=>item.historyOccurrenceId),identities);
  assert.equal(new Set(data.history[0].items.map(item=>item.historyOccurrenceId)).size,3);
});

test('failed newest chip returns the last accepted Home after an intervening pending selection',async()=>{
  const pending=deferred();let data;
  const page=id=>({chips:[],sections:[{title:id,items:[],format:'largeCards',moreBrowseId:null,moreParams:null}],continuation:null});
  const home=new HomeController(async(_,args)=>args.chipParams==='A'?page('A'):args.chipParams==='B'?pending.promise:Promise.reject(Error('offline')),next=>data=next);
  await home.load('A');const old=home.load('B');await home.load('C');pending.resolve(page('B'));await old;
  assert.equal(data.chipParams,'A');assert.equal(data.page.sections[0].title,'A');assert.equal(data.loading,false);
});

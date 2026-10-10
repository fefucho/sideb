import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const source=await readFile(new URL('../src/lib/detail/projection.ts',import.meta.url),'utf8');
const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {projectTracks,projectedPlayback,canReorderPlaylist,captureTrackOccurrence,findTrackOccurrence}=await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
const song=(title,setVideoId=null,videoId=title,duration='3:00')=>({title,setVideoId,videoId,duration,artists:'Artista',album:'Álbum',thumbnail:null,isVideo:false,artistId:null,albumId:null});
test('normalized filter retains distinct occurrences and original identity',()=>{
  const tracks=[song('Árbol','first','same'),song('Other','middle'),song('Árbol','last','same')];
  const visible=projectTracks(tracks,'arbol');
  assert.deepEqual(visible.map(item=>item.sourceIndex),[0,2]);
  assert.equal(new Set(visible.map(item=>item.key)).size,2);
  assert.equal(visible[1].key,projectTracks(tracks)[2].key);
});
test('playback uses the full chosen order, never the filtered subset',()=>{
  const tracks=[song('Zulu'),song('Árbol'),song('Beta')];
  const selected=projectTracks(tracks,'zulu','title')[0];
  const playback=projectedPlayback(tracks,selected.sourceIndex,'title');
  assert.deepEqual(playback.items.map(track=>track.title),['Árbol','Beta','Zulu']);
  assert.equal(playback.index,2);
  assert.deepEqual(tracks.map(track=>track.title),['Zulu','Árbol','Beta']);
});
test('duration order is numeric and stable, unknown durations last',()=>{
  const tracks=[song('A',null,'a','10:00'),song('B',null,'b','2:00'),song('C',null,'c',null),song('D',null,'d','2:00')];
  assert.deepEqual(projectTracks(tracks,'','duration').map(row=>row.track.title),['B','D','A','C']);
});
test('reorder refuses partial catalog, repeated occurrence IDs, filter and mutation',()=>{
  const tracks=[song('A','a'),song('B','b')];
  assert.equal(canReorderPlaylist(tracks,null,true,'custom','',false),true);
  for(const args of [[tracks,'next',true,'custom','',false],[tracks,null,false,'custom','',false],[tracks,null,true,'title','',false],[tracks,null,true,'custom','A',false],[tracks,null,true,'custom','',true],[[tracks[0],tracks[0]],null,true,'custom','',false]])assert.equal(canReorderPlaylist(...args),false);
});


test('selection is resolved by occurrence after completing a reordered source, not stale index',()=>{
 const a=song('A','set-a','same'),b=song('B','set-b','same');const selection=captureTrackOccurrence([a,b],1);
 assert.equal(findTrackOccurrence([b,a],selection),0);assert.equal(findTrackOccurrence([a],selection),-1);
 const duplicate=song('A',null,'same');const ordinal=captureTrackOccurrence([duplicate,duplicate],1);
 assert.equal(findTrackOccurrence([song('new'),duplicate,duplicate],ordinal),2);
});

import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import ts from 'typescript';
const source=await readFile(new URL('../src/lib/search/projection.ts',import.meta.url),'utf8');
const output=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {searchProjection}=await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const song=(videoId,artists='',artistRuns=[])=>({videoId,title:videoId,artists,artistRuns,artistId:null,album:null,albumId:null,duration:'3:44',thumbnail:'cover',setVideoId:`occurrence-${videoId}`,isVideo:false,isUpload:false,library:{addToken:'keep'}});
const results=(topSongs,songs=[],kind='artist')=>({top:[{kind,id:'UCkanye',title:'Kanye West',subtitle:null,thumbnail:null,duration:null}],topSongs,songs,albums:[],artists:[],playlists:[]});
test('artist shelf restores omitted credits in order and preserves occurrence metadata',()=>{
 const tracks=[song('All Falls Down'),song('ALL THE LOVE','  '),song('Stronger')];const original=structuredClone(tracks);
 const projected=searchProjection(results(tracks),8);
 assert.deepEqual(projected.topSongs.map(track=>track.videoId),tracks.map(track=>track.videoId));
 for(const [index,track] of projected.topSongs.entries()){
  assert.equal(track.artists,'Kanye West');assert.equal(track.artistId,'UCkanye');assert.deepEqual(track.artistRuns,[{text:'Kanye West',id:'UCkanye'}]);
  assert.equal(track.setVideoId,tracks[index].setVideoId);assert.equal(track.library,tracks[index].library);assert.equal(track.duration,'3:44');assert.equal(track.thumbnail,'cover');
 }
 assert.deepEqual(tracks,original);assert.deepEqual(searchProjection(projected),projected);
});
test('explicit collaborators and matching song credits precede artist shelf context',()=>{
 const runs=[{text:'Kanye West',id:'UCkanye'},{text:' & ',id:null},{text:'Syleena Johnson',id:'UCsyleena'}];
 const explicit=song('All Falls Down','Kanye West & Syleena Johnson',runs);const missing=song('All Falls Down');
 const projected=searchProjection(results([missing],[explicit]));
 assert.deepEqual(projected.topSongs[0].artistRuns,runs);assert.equal(projected.topSongs[0].artists,explicit.artists);assert.equal(projected.topSongs[0].setVideoId,missing.setVideoId);assert.deepEqual(projected.songs,[]);
 assert.equal(searchProjection(results([explicit])).topSongs[0],explicit);
 assert.equal(searchProjection(results([song('runs','',runs)])).topSongs[0].artists,'Kanye West & Syleena Johnson');
});
test('unrelated artist identities and collection titles are never used as song credits',()=>{
 for(const kind of ['album','playlist','song'])assert.equal(searchProjection(results([song('Stronger')],[],kind)).topSongs[0].artists,'');
 const conflicting={...song('other'),artistId:'UCother'};assert.equal(searchProjection(results([conflicting])).topSongs[0],conflicting);
});

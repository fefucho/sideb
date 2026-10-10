import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
async function module(file) {
  const source = await readFile(new URL(`../src/lib/${file}.ts`, import.meta.url), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
}
const { albumCollectionType, metadataFor } = await module('home/collectionMetadata');
const { albumTrackWithCredit } = await module('detail/metadata');
const { projectTracks } = await module('detail/projection');
const card = subtitle => ({ kind:'album',id:'MPRErelease',title:'Release',subtitle,artists:null,artistId:null,artistRuns:[],album:null,albumId:null,thumbnail:null,duration:null,explicit:false });
const song = (artists, extra={}) => ({videoId:'video',setVideoId:'occurrence',title:'Song',artists,artistId:null,album:null,albumId:null,thumbnail:null,duration:'3:00',isVideo:false,...extra});
const album = {artist:'Beyoncé',artistId:'UCheader'};

test('release labels classify the original leading provider component and never the song count', () => {
  for (const [subtitle,type,label] of [['Sencillo • 2024 • Artista','single','Sencillo'],[' Single · 2024 · Artista ','single','Sencillo'],['EP • Artist','ep','EP'],['ÁLBUM • 2024','album','Álbum']]) {
    const original = card(subtitle); const before=structuredClone(original);
    assert.equal(albumCollectionType(original),type);
    assert.ok(metadataFor(original).summary.startsWith(label));
    assert.deepEqual(original,before);
  }
  for(const subtitle of ['Single Mind • 2024','Artist • Single',null])assert.equal(albumCollectionType(card(subtitle)),'album');
  assert.ok(metadataFor(card(null),{items:[song('Artist')]}).summary.startsWith('Álbum • 1 canción'));
  assert.ok(metadataFor(card('Single • 2024'),{items:Array.from({length:20},()=>song('Artist'))}).summary.startsWith('Sencillo • 2024 • 20 canciones'));
  assert.equal(albumCollectionType(card(null),{subtitle:'EP • 2024'}),'ep');
});

test('single and EP metadata prefixes do not become artist credits while names retain their spelling', () => {
  for(const prefix of ['Single','Sencillo','EP']) {
    assert.equal(metadataFor({...card(`${prefix} • 2024 • Artist`),artists:`${prefix} • Artist`}).artists,'Artist');
    assert.equal(metadataFor(card(`${prefix} • 2024 • Artist`)).artists,'Artist');
  }
  for(const name of ['Single Mind','EP Artist','The 1975'])assert.equal(metadataFor({...card(null),artists:name}).artists,name);
});

test('album row destination fallback requires the exact normalized header credit or an empty credit', () => {
  for(const credit of ['Beyoncé',' BEYONCE ','beyonce\u0301','','  ',undefined,null]) {
    const original=song(credit);const projected=albumTrackWithCredit(original,album);
    assert.equal(projected.artistId,'UCheader');assert.equal(projected.artists,(credit??'').trim()?credit:'Beyoncé');
    assert.equal(original.artistId,null);assert.equal(projected.videoId,original.videoId);assert.equal(projected.setVideoId,original.setVideoId);
  }
  for(const credit of ['Guest','Beyoncé & Guest','Beyoncé, Guest','Beyoncé Remix']) {
    const original=song(credit);assert.equal(albumTrackWithCredit(original,album),original);
  }
  const spaced=song('Artist  Name');assert.equal(albumTrackWithCredit(spaced,{artist:'Artist Name',artistId:'UCname'}).artistId,'UCname');
  const absent=song('Beyoncé');assert.equal(albumTrackWithCredit(absent,{artist:'Beyoncé',artistId:null}),absent);
});

test('existing provider links/runs and filtered occurrence/menu identities are preserved', () => {
  for(const extra of [{artistId:'UCown'},{artistRuns:[{text:'Guest',id:'UCguest'}]},{artistRuns:[{text:'Beyoncé',id:null}]}]) {
    const original=song('Beyoncé',extra);assert.equal(albumTrackWithCredit(original,album),original);
  }
  const rows=[song('Beyoncé'),song('Guest',{title:'Hidden',setVideoId:'other'}),song('Beyoncé',{setVideoId:'repeat'})];
  const originalKeys=projectTracks(rows,'Song').map(row=>row.key);
  const projected=projectTracks(rows.map(row=>albumTrackWithCredit(row,album)),'Song');
  assert.deepEqual(projected.map(row=>row.key),originalKeys);assert.deepEqual(projected.map(row=>row.sourceIndex),[0,2]);
  assert.equal(projected[0].track.artistId,'UCheader');assert.equal(rows[0].artistId,null);
});

test('artist-page playback preserves guest credits and supplied links while keeping source identity', async () => {
  const route = await readFile(new URL('../src/routes/+page.svelte', import.meta.url), 'utf8');
  const script = route.split('<script lang="ts">')[1].split('</script>')[0];
  const ast = ts.createSourceFile('route.ts', script, ts.ScriptTarget.ES2022, true, ts.ScriptKind.TS);
  const declaration = ast.statements.find(node => ts.isFunctionDeclaration(node) && node.name?.text === 'playArtist');
  assert.ok(declaration);
  const harness = `let selectedArtist, collectionPlayRevision=0, recorded, albumTrackWithCredit;
    const playCollection=(...args)=>{recorded=args;return Promise.resolve();};
    ${declaration.getText(ast)}
    export function run(artist,index,shuffle,credit){selectedArtist=artist;recorded=null;albumTrackWithCredit=credit;playArtist(index,shuffle);return recorded;}`;
  const code = ts.transpileModule(harness, {compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
  const { run } = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
  const tracks = [song('BEYONCE'),song('Guest'),song('Beyoncé & Guest'),song('Beyoncé',{artistId:'UCoriginal'}),song('Beyoncé',{artistRuns:[{text:'Beyoncé',id:'UCrun'}]}),song('')];
  const artist = {channelId:'UCheader',name:'Beyoncé',thumbnail:'original-art',topSongs:tracks};
  const before=structuredClone(artist);
  const [items,index,source,shuffle,thumbnail] = run(artist,1,true,albumTrackWithCredit);
  assert.deepEqual(items.map(item=>item.artistId),['UCheader',null,null,'UCoriginal',null,'UCheader']);
  assert.deepEqual(items[4].artistRuns,tracks[4].artistRuns);
  assert.equal(index,1);assert.equal(shuffle,true);assert.equal(thumbnail,'original-art');
  assert.deepEqual(source,{kind:'artist',id:'UCheader',title:'Beyoncé'});assert.deepEqual(artist,before);
  assert.equal(run(null,0,false,albumTrackWithCredit),null);
});

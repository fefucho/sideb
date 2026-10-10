import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const source = await readFile(new URL('../src/lib/home/songMetadata.ts', import.meta.url), 'utf8');
const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { normalizeHomeSongCard, isProviderStatistic } = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
const card = extra => ({ kind:'song',id:'video',title:'Pink + White',subtitle:'Frank Ocean • 337M plays',artists:null,album:null,albumId:null,artistId:'UCartist',artistRuns:[],thumbnail:'art',duration:'3:04',explicit:true,...extra });

test('quick playback separates provider plays from artists and never manufactures an album', () => {
  for (const extra of [{}, {artists:'Frank Ocean • 337M plays'}, {artists:'Frank Ocean',album:'337M plays'}]) {
    const original=card(extra), before=structuredClone(original), result=normalizeHomeSongCard(original);
    assert.equal(result.artists,'Frank Ocean'); assert.equal(result.album,null);
    assert.equal(result.subtitle,before.subtitle); assert.deepEqual(original,before);
  }
});

test('canonical album and artist navigation survives a statistical Home subtitle', () => {
  const original=card({album:'Blonde',albumId:'MPREblonde',artists:'Frank Ocean',artistRuns:[{text:'Frank Ocean',id:'UCfrank'}],setVideoId:'occurrence',isUpload:true,library:{inLibrary:true,addToken:null,removeToken:'private-token'}});
  const result=normalizeHomeSongCard(original);
  assert.equal(result.album,'Blonde'); assert.equal(result.albumId,'MPREblonde');
  assert.equal(result.artistId,'UCartist'); assert.equal(result.artistRuns,original.artistRuns);
  for(const key of ['id','title','setVideoId','thumbnail','duration','explicit','isUpload','library'])assert.equal(result[key],original[key]);
});

test('subtitle album recovery requires a real album link and skips counts, years and duration', () => {
  const subtitle='Song • Frank Ocean • 337M plays • Blonde • 2016 • 3:04';
  assert.equal(normalizeHomeSongCard(card({subtitle})).album,null);
  const linked=normalizeHomeSongCard(card({subtitle,albumId:'MPREblonde'}));
  assert.equal(linked.artists,'Frank Ocean'); assert.equal(linked.album,'Blonde'); assert.equal(linked.albumId,'MPREblonde');
  const noAlbum=normalizeHomeSongCard(card({subtitle:'Frank Ocean • 337M plays • 2016 • 3:04',albumId:'MPREknown'}));
  assert.equal(noAlbum.album,null); assert.equal(noAlbum.albumId,'MPREknown');
});

test('Spanish and English counters are descriptors while similar release names remain intact', () => {
  for(const value of ['337M plays','1.7B views','1,2 M reproducciones','25 mil visualizaciones','3.000 vistas','2M streams','4 million listeners','1,234 subscribers']) {
    assert.equal(isProviderStatistic(value),true,value);
    assert.equal(normalizeHomeSongCard(card({album:value})).album,null,value);
  }
  for(const name of ['Views','Plays','1989','The 1975','1 More Time','3:15 (Breathe)']) {
    assert.equal(isProviderStatistic(name),false,name);
    assert.equal(normalizeHomeSongCard(card({album:name,albumId:'MPREreal'})).album,name);
  }
  // Home remains ambiguous even with a valid navigation target. A canonical
  // album named 100 Plays is restored by verified album detail, not this subtitle.
  assert.equal(normalizeHomeSongCard(card({album:'100 Plays',albumId:'MPREreal'})).album,null);
});

test('Home counters with a real album destination remain unknown labels until canonical hydration', () => {
  for (const album of ['337M plays', '1.7B views', '25 mil visualizaciones', '1,2 millones de vistas', '337 M de reproducciones', '3:04']) {
    const original = card({ album, albumId:'MPREreal', subtitle:`Frank Ocean • ${album}` });
    const result = normalizeHomeSongCard(original);
    assert.equal(result.album, null); assert.equal(result.albumId, 'MPREreal');
    assert.equal(result.id, original.id); assert.equal(result.artists, 'Frank Ocean');
    assert.equal(original.album, album);
  }
});

test('empty descriptors prefer linked collaborators and type/duration-only subtitles stay unknown', () => {
  const artistRuns=[{text:'Frank Ocean',id:'UCfrank'},{text:' & ',id:null},{text:'Guest',id:'UCguest'}];
  const linked=normalizeHomeSongCard(card({artists:'',artistRuns,subtitle:'337M plays'}));
  assert.equal(linked.artists,'Frank Ocean & Guest'); assert.equal(linked.artistRuns,artistRuns);
  assert.equal(normalizeHomeSongCard(card({artists:'Wrong • 337M plays',artistRuns})).artists,'Frank Ocean & Guest');
  for(const subtitle of ['Song • 3:04','Canción • 2024','337M plays',null])assert.equal(normalizeHomeSongCard(card({subtitle})).artists,'');
  for(const artists of ['The 1975','Single Mind','EP Artist'])assert.equal(normalizeHomeSongCard(card({artists})).artists,artists);
});

test('videos use the same safe credit contract; album and playlist presentation is untouched', () => {
  assert.equal(normalizeHomeSongCard(card({kind:'video'})).artists,'Frank Ocean');
  for(const kind of ['album','playlist','artist']) { const original=card({kind}); assert.equal(normalizeHomeSongCard(original),original); }
});

test('unlinked structured counters cannot bypass sanitization in ArtistCredits', () => {
  for(const metricRuns of [[{text:'337M plays',id:null}],[{text:'337M',id:null},{text:' plays',id:null}]]) {
    const artistRuns=[{text:'Song',id:null},{text:' • ',id:null},{text:'Frank Ocean',id:'UCfrank'},{text:' • ',id:null},...metricRuns];
    const result=normalizeHomeSongCard(card({artistRuns}));
    assert.equal(result.artists,'Frank Ocean');
    assert.deepEqual(result.artistRuns,[{text:'Frank Ocean',id:'UCfrank'}]);
    assert.equal(artistRuns[0].text,'Song');
  }
  const linkedNames=[{text:'Song',id:'UCsong'},{text:' • ',id:null},{text:'Views',id:'UCviews'}];
  const result=normalizeHomeSongCard(card({artistRuns:linkedNames}));
  assert.equal(result.artists,'Song • Views');assert.equal(result.artistRuns,linkedNames);
  assert.equal(normalizeHomeSongCard(card({artists:'Artist A • Artist B'})).artists,'Artist A • Artist B');
});

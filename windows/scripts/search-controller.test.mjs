import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/search/controller.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { SearchController } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const song = id => ({ videoId: id, title: id, artists: 'Artist', album: null, duration: null, thumbnail: null, isVideo: false, artistId: null, albumId: null });
const card = id => ({ kind: 'artist', id, title: id, subtitle: null, thumbnail: null, duration: null });
const result = id => ({correction:null,results:{ top: [card(`top-${id}`)], songs: [song(`global-${id}`)], albums: [], artists: [card(`global-${id}`)], playlists: [] }});
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; }
function controller(rpc) { let data; const search = new SearchController(rpc, next => data = next); return { search, get data() { return data; } }; }
const tick = () => new Promise(resolve => setTimeout(resolve, 0));

test('top songs survive publication, mode cache and navigation snapshot with original library metadata', async () => {
  const original={...song('related'),setVideoId:'occurrence',library:{addToken:'fixture-token'},artistRuns:[{text:'Guest',browseId:'guest'}]};
  const ctx=controller(async command=>command==='search_catalog'?{...result('top'),results:{...result('top').results,topSongs:[original]}}:[]);
  await ctx.search.execute('top');
  assert.equal(ctx.data.topSongs[0],original);
  const snapshot=ctx.data;
  ctx.search.setQuery('other');ctx.search.restore(snapshot);
  assert.equal(ctx.data.topSongs[0].setVideoId,'occurrence');
  assert.equal(ctx.data.mixedResults.topSongs[0].library.addToken,'fixture-token');
  ctx.search.setQuery('top');await ctx.search.execute('top');
  assert.equal(ctx.data.topSongs[0].artistRuns[0].browseId,'guest');
});

test('submit records history once with a single primary request and no speculative filters', async () => {
  const calls = []; const ctx = controller(async (command, args) => {
    calls.push({ command, args });
    if (command === 'search_catalog') return result(args.query);
    if (command === 'search_songs') throw new Error('filtered songs unavailable');
    if (command === 'search_videos') return [song('video')];
  });
  await ctx.search.execute(' radiohead ');
  const data = ctx.data;
  assert.equal(data.mode, 'all');
  assert.deepEqual(calls.filter(c => c.command === 'search_catalog').map(c => c.args), [{ query: 'radiohead', recordHistory: true, ignoreSpelling:false }]);
  assert.equal(calls.some(c => c.command === 'search_songs'),false);
  assert.equal(data.songs[0].videoId, 'global-radiohead');
  assert.deepEqual(data.videos,[]);
  assert.equal(data.partialErrors.songs,undefined);
  assert.equal(data.partialErrors.global, undefined);
  assert.equal(data.isLoading, false);
});

test('A to B to A responses cannot replace the newest search', async () => {
  const pending = [deferred(), deferred(), deferred()]; const calls = []; const { search } = controller(async (command, args) => {
    const index = calls.filter(c => c.command === 'search_catalog').length;
    calls.push({ command, args });
    if (command === 'search_catalog') return pending[index].promise;
    if (command === 'search_songs') return [song(`s-${args.query}-${index}`)];
    return [];
  });
  const a1 = search.execute('A'); await tick();
  search.setQuery('B'); const b = search.execute('B'); await tick();
  search.setQuery('A'); const a2 = search.execute('A'); await tick();
  pending[2].resolve(result('new-A')); await a2;
  pending[0].resolve(result('old-A')); await a1;
  pending[1].resolve(result('old-B')); await b;
  assert.equal(search['data'].top[0].id, 'top-new-A');
  assert.equal(search['data'].songs[0].videoId, 'global-new-A');
});

test('anonymous preview in flight cannot suppress an authenticated submit for the same query', async () => {
  const preview = deferred(); const calls = []; const ctx = controller(async (command, args) => {
    calls.push({ command, args });
    if (command === 'search_catalog' && !args.recordHistory) return preview.promise;
    if (command === 'search_catalog') return result('submitted');
    if (command === 'search_songs') return [song('submitted-song')];
    if (command === 'search_videos') return [];
  });
  const previewRequest = ctx.search.execute('same', 'all', false);
  await tick();
  await ctx.search.execute('same', 'all', true);
  preview.resolve(result('preview')); await previewRequest;
  assert.equal(ctx.data.top[0].id, 'top-submitted');
  assert.equal(calls.filter(c => c.command === 'search_catalog' && c.args.recordHistory).length, 1);
});

test('changing mode during an active request reloads without history and ignores old results', async () => {
  const oldGlobal = deferred(); const calls = []; const ctx = controller(async (command, args) => {
    calls.push({ command, args });
    if (command === 'search_catalog' && args.recordHistory) return oldGlobal.promise;
    if (command === 'search_catalog') return result('preview');
    if (command === 'search_songs') return [song('song')];
    if (command === 'search_videos') return [];
    if (command === 'search_cards') return [card('filtered-album')];
  });
  const old = ctx.search.execute('query'); await tick();
  ctx.search.setMode('albums'); await tick();
  oldGlobal.resolve(result('old')); await old;
  assert.equal(ctx.data.albums[0].id, 'filtered-album');
  assert.equal(ctx.data.isLoading, false);
  assert.equal(calls.filter(c => c.command === 'search_catalog' && c.args.recordHistory).length, 1);
  assert.equal(calls.filter(c => c.command === 'search_catalog' && !c.args.recordHistory).length, 1);
});

test('reset invalidates pending work and account scoped caches', async () => {
  const pending = deferred(); let calls = 0; const { search } = controller(async command => {
    calls++;
    if (calls === 1) return pending.promise;
    if (command === 'search_catalog') return result('fresh');
    if (command === 'search_songs') return [song('fresh-song')];
    return [];
  });
  const old = search.execute('private'); await tick();
  search.reset(); pending.resolve(result('old')); await old;
  await search.execute('private');
  assert.equal(search['data'].top[0].id, 'top-fresh');
});

test('a failed new query cannot restore a previous mixed bundle on a later mode change', async () => {
  const { search } = controller(async (command, args) => {
    if (command === 'search_catalog') {
      if (args.query === 'A') return result('A');
      if (args.query === 'B' && args.recordHistory) throw new Error('global failed');
      return result('B-preview');
    }
    if (command === 'search_songs') { if (args.query === 'B') throw new Error('songs failed'); return []; }
    if (command === 'search_videos') return [];
  });
  await search.execute('A');
  await search.execute('B', 'songs');
  assert.equal(search['data'].mixedResults, null);
  search.setMode('all'); await tick();
  assert.equal(search['data'].top[0].id, 'top-B-preview');
  assert.notEqual(search['data'].top[0].id, 'top-A');
});

test('explicit Enter always records once; technical repetitions reuse only successful cache', async () => {
  const calls=[];const ctx=controller(async(command,args)=>{calls.push({command,args});return result('cached');});
  await ctx.search.execute('same');await ctx.search.execute('same');await ctx.search.execute('same','all','refresh');
  assert.equal(calls.length,2);assert.ok(calls.every(call=>call.args.recordHistory));
  ctx.search.reset();await ctx.search.execute('same','all','refresh');assert.equal(calls.length,3);assert.equal(calls.at(-1).args.recordHistory,false);
});

test('category mode requests its filter without writing another history entry', async () => {
  const calls = []; const { search } = controller(async (command, args) => {
    calls.push({ command, args });
    if (command === 'search_catalog') return result('artist');
    if (command === 'search_songs') return [song('song')];
    if (command === 'search_videos') return [];
    if (command === 'search_cards') return [card(args.category)];
  });
  search.setQuery('artist'); await search.execute('artist');
  search.setMode('artists'); await tick();
  assert.equal(search['data'].artists[0].id, 'artists');
  assert.equal(calls.filter(c => c.command === 'search_catalog').length, 1);
  assert.deepEqual(calls.find(c => c.command === 'search_cards').args, { query: 'artist', category: 'artists' });
  search.setMode('all'); search.setMode('artists'); await tick();
  assert.equal(calls.filter(c => c.command === 'search_cards').length, 1);
  search.setMode('all');
  assert.equal(search['data'].artists[0].id, 'global-artist');
});

test('restore from a category snapshot keeps the original mixed results for All', async () => {
  const { search } = controller(async (command, args) => {
    if (command === 'search_cards') return [card('filtered-artist')];
    return [];
  });
  const mixed = result('original').results;
  const snapshot = { ...search['data'], query: 'q', mode: 'artists', lastSearchedQuery: 'q', hasSearched: true,
    artists: [card('filtered-artist')], mixedResults: mixed };
  search.restore(snapshot);
  search.setMode('all');
  assert.equal(search['data'].artists[0].id, 'global-original');
});

test('restore retries an interrupted search anonymously and setMode does not add history', async () => {
  const calls = []; const { search } = controller(async (command, args) => {
    calls.push({ command, args });
    if (command === 'search_catalog') return result('restore');
    if (command === 'search_songs') return [];
    if (command === 'search_videos') return [];
    if (command === 'search_cards') return [];
  });
  const snapshot = { ...search['data'], query: 'restore', lastSearchedQuery: 'restore', isLoading: true };
  search.restore(snapshot); await tick();
  assert.equal(calls.find(c => c.command === 'search_catalog').args.recordHistory, false);
  const historyCount = calls.filter(c => c.command === 'search_catalog' && c.args.recordHistory).length;
  search.setMode('albums'); await tick();
  assert.equal(calls.filter(c => c.command === 'search_catalog' && c.args.recordHistory).length, historyCount);
});

test('selected category publishes after primary mixed without launching unrelated filters', async () => {
 const filtered=deferred(),calls=[];const ctx=controller(async(command,args)=>{calls.push({command,args});return command==='search_catalog'?result('primary'):filtered.promise;});
 const request=ctx.search.execute('query','songs','artistResolution');await tick();
 assert.equal(ctx.data.top[0].id,'top-primary');assert.ok(ctx.data.isLoading);assert.deepEqual(calls.map(item=>item.command),['search_catalog','search_songs']);assert.equal(calls[0].args.recordHistory,false);
 filtered.resolve([song('filtered')]);await request;assert.equal(ctx.data.songs[0].videoId,'filtered');assert.equal(ctx.data.isLoading,false);
});

test('retrying one failed block keeps other blocks and never records another search',async()=>{
  const calls=[];let fail=true;const ctx=controller(async(command,args)=>{calls.push({command,args});if(command==='search_catalog')return result('retry');if(command==='search_videos'&&fail)throw new Error('video fail');return [song(command)];});
  await ctx.search.execute('retry','videos');const hero=ctx.data.top[0];const tracks=ctx.data.songs;fail=false;calls.length=0;await ctx.search.retryBlock('videos');
  assert.deepEqual(calls,[{command:'search_videos',args:{query:'retry'}}]);assert.equal(ctx.data.top[0],hero);assert.deepEqual(ctx.data.songs,tracks);assert.equal(ctx.data.partialErrors.videos,undefined);
});

test('provider correction survives snapshot and drives selected category; original spelling has a separate cache',async()=>{
 const calls=[];const ctx=controller(async(command,args)=>{calls.push({command,args});return command==='search_catalog'?{...result(args.ignoreSpelling?'original':'corrected'),correction:args.ignoreSpelling?null:{query:'corrected query',applied:true}}:[song('filtered')];});
 await ctx.search.execute('typo','songs');assert.equal(calls[1].args.query,'corrected query');assert.deepEqual(ctx.data.correction,{query:'corrected query',applied:true});
 const snapshot=ctx.data;ctx.search.restore(snapshot);assert.equal(ctx.data.correction.query,'corrected query');
 await ctx.search.execute('typo','songs','refresh',true);assert.equal(calls[2].args.ignoreSpelling,true);assert.equal(calls[2].args.recordHistory,false);assert.equal(calls.length,3);assert.equal(ctx.data.mode,'songs');assert.equal(ctx.data.correction,null);
});

test('catalog and filter cache expire and evict oldest queries, reset discards account data',async()=>{
 const originalNow=Date.now;let now=10_000,calls=[];Date.now=()=>now;
 try {
  const ctx=controller(async(command,args)=>{calls.push({command,args});return command==='search_catalog'?result(args.query):[song(args.query)];});
  await ctx.search.execute('first','songs','refresh');await ctx.search.execute('first','songs','refresh');assert.equal(calls.length,2);
  now+=60_001;await ctx.search.execute('first','songs','refresh');assert.equal(calls.length,4);
  for(let i=0;i<33;i++)await ctx.search.execute(`query-${i}`,'songs','refresh');
  assert.equal(ctx.search['cache'].size,32);assert.equal(ctx.search['categories'].size,32);
  const before=calls.length;await ctx.search.execute('first','songs','refresh');assert.equal(calls.length,before+2);
  ctx.search.reset();await ctx.search.execute('first','songs','refresh');assert.equal(calls.length,before+4);
 }finally{Date.now=originalNow;}
});

test('original spelling filters and restored snapshots project the exact mixed response without corrective RPCs',async()=>{
 const calls=[];const mixed={...result('original'),results:{...result('original').results,topSongs:[song('associated')],albums:[{...card('record'),kind:'album'}]}};
 const ctx=controller(async(command,args)=>{calls.push({command,args});return mixed;});
 await ctx.search.execute('original','all','refresh',true);ctx.search.setMode('songs');await tick();
 assert.deepEqual(ctx.data.songs.map(track=>track.videoId),['associated','global-original']);
 const snapshot=ctx.data;ctx.search.setMode('albums');await tick();assert.equal(ctx.data.albums[0].id,'record');
 ctx.search.restore(snapshot);ctx.search.setMode('artists');await tick();assert.equal(ctx.data.artists[0].id,'top-original');assert.equal(calls.length,1);
 const interrupted={...ctx.data,isLoading:true};ctx.search.restore(interrupted);await tick();assert.equal(ctx.data.ignoreSpelling,true);assert.equal(ctx.data.mode,'artists');assert.equal(calls.length,1);
});

test('mixed provider videos keep their typed identity in the All video section',async()=>{
 const audio=song('audio'),video={...song('video'),isVideo:true};
 const ctx=controller(async command=>command==='search_catalog'?{...result('mixed'),results:{...result('mixed').results,songs:[video,audio]}}:[audio]);
 await ctx.search.execute('mixed');assert.deepEqual(ctx.data.songs.map(track=>track.videoId),['audio']);assert.deepEqual(ctx.data.videos.map(track=>track.videoId),['video']);
 assert.equal(ctx.data.mixedResults.songs[0],video);ctx.search.setMode('songs');await tick();ctx.search.setMode('all');assert.deepEqual(ctx.data.videos.map(track=>track.videoId),['video']);
});

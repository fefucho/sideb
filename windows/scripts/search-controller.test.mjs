import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/search/controller.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { SearchController } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const song = id => ({ videoId: id, title: id, artists: 'Artist', album: null, duration: null, thumbnail: null, isVideo: false, artistId: null, albumId: null });
const card = id => ({ kind: 'artist', id, title: id, subtitle: null, thumbnail: null, duration: null });
const result = id => ({ top: [card(`top-${id}`)], songs: [song(`global-${id}`)], albums: [], artists: [card(`global-${id}`)], playlists: [] });
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; }
function controller(rpc) { let data; const search = new SearchController(rpc, next => data = next); return { search, get data() { return data; } }; }
const tick = () => new Promise(resolve => setTimeout(resolve, 0));

test('submit records history once and keeps independent section failures partial', async () => {
  const calls = []; const ctx = controller(async (command, args) => {
    calls.push({ command, args });
    if (command === 'search_all') return result(args.query);
    if (command === 'search_songs') throw new Error('filtered songs unavailable');
    if (command === 'search_videos') return [song('video')];
  });
  await ctx.search.execute(' radiohead ');
  const data = ctx.data;
  assert.equal(data.mode, 'all');
  assert.deepEqual(calls.filter(c => c.command === 'search_all').map(c => c.args), [{ query: 'radiohead', recordHistory: true }]);
  assert.equal(calls.find(c => c.command === 'search_songs').args.query, 'radiohead');
  assert.equal(data.songs[0].videoId, 'global-radiohead');
  assert.equal(data.videos[0].videoId, 'video');
  assert.ok(data.partialErrors.songs);
  assert.equal(data.partialErrors.global, undefined);
  assert.equal(data.isLoading, false);
});

test('A to B to A responses cannot replace the newest search', async () => {
  const pending = [deferred(), deferred(), deferred()]; const calls = []; const { search } = controller(async (command, args) => {
    const index = calls.filter(c => c.command === 'search_all').length;
    calls.push({ command, args });
    if (command === 'search_all') return pending[index].promise;
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
  assert.equal(search['data'].songs[0].videoId, 's-A-3');
});

test('anonymous preview in flight cannot suppress an authenticated submit for the same query', async () => {
  const preview = deferred(); const calls = []; const ctx = controller(async (command, args) => {
    calls.push({ command, args });
    if (command === 'search_all' && !args.recordHistory) return preview.promise;
    if (command === 'search_all') return result('submitted');
    if (command === 'search_songs') return [song('submitted-song')];
    if (command === 'search_videos') return [];
  });
  const previewRequest = ctx.search.execute('same', 'all', false);
  await tick();
  await ctx.search.execute('same', 'all', true);
  preview.resolve(result('preview')); await previewRequest;
  assert.equal(ctx.data.top[0].id, 'top-submitted');
  assert.equal(calls.filter(c => c.command === 'search_all' && c.args.recordHistory).length, 1);
});

test('changing mode during an active request reloads without history and ignores old results', async () => {
  const oldGlobal = deferred(); const calls = []; const ctx = controller(async (command, args) => {
    calls.push({ command, args });
    if (command === 'search_all' && args.recordHistory) return oldGlobal.promise;
    if (command === 'search_all') return result('preview');
    if (command === 'search_songs') return [song('song')];
    if (command === 'search_videos') return [];
    if (command === 'search_cards') return [card('filtered-album')];
  });
  const old = ctx.search.execute('query'); await tick();
  ctx.search.setMode('albums'); await tick();
  oldGlobal.resolve(result('old')); await old;
  assert.equal(ctx.data.albums[0].id, 'filtered-album');
  assert.equal(ctx.data.isLoading, false);
  assert.equal(calls.filter(c => c.command === 'search_all' && c.args.recordHistory).length, 1);
  assert.equal(calls.filter(c => c.command === 'search_all' && !c.args.recordHistory).length, 1);
});

test('reset invalidates pending work and account scoped caches', async () => {
  const pending = deferred(); let calls = 0; const { search } = controller(async command => {
    calls++;
    if (calls === 1) return pending.promise;
    if (command === 'search_all') return result('fresh');
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
    if (command === 'search_all') {
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

test('only complete successful responses enter the mode and context cache', async () => {
  let attempts = 0; let historyCalls = 0; const { search } = controller(async (command, args) => {
    if (command === 'search_all') { if (args.recordHistory) historyCalls++; return result('cached'); }
    if (command === 'search_songs' && ++attempts === 1) throw new Error('retry me');
    if (command === 'search_songs') return [song(`filtered-${attempts}`)];
    return [];
  });
  await search.execute('same');
  await search.execute('same');
  await search.execute('same');
  assert.equal(attempts, 2);
  assert.equal(historyCalls, 2);
  await search.execute('same', 'all', false);
  assert.equal(historyCalls, 2);
  assert.equal(attempts, 3);
});

test('category mode requests its filter without writing another history entry', async () => {
  const calls = []; const { search } = controller(async (command, args) => {
    calls.push({ command, args });
    if (command === 'search_all') return result('artist');
    if (command === 'search_songs') return [song('song')];
    if (command === 'search_videos') return [];
    if (command === 'search_cards') return [card(args.category)];
  });
  search.setQuery('artist'); await search.execute('artist');
  search.setMode('artists'); await tick();
  assert.equal(search['data'].artists[0].id, 'artists');
  assert.equal(calls.filter(c => c.command === 'search_all').length, 1);
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
  const mixed = result('original');
  const snapshot = { ...search['data'], query: 'q', mode: 'artists', lastSearchedQuery: 'q', hasSearched: true,
    artists: [card('filtered-artist')], mixedResults: mixed };
  search.restore(snapshot);
  search.setMode('all');
  assert.equal(search['data'].artists[0].id, 'global-original');
});

test('restore retries an interrupted search anonymously and setMode does not add history', async () => {
  const calls = []; const { search } = controller(async (command, args) => {
    calls.push({ command, args });
    if (command === 'search_all') return result('restore');
    if (command === 'search_songs') return [];
    if (command === 'search_videos') return [];
    if (command === 'search_cards') return [];
  });
  const snapshot = { ...search['data'], query: 'restore', lastSearchedQuery: 'restore', isLoading: true };
  search.restore(snapshot); await tick();
  assert.equal(calls.find(c => c.command === 'search_all').args.recordHistory, false);
  const historyCount = calls.filter(c => c.command === 'search_all' && c.args.recordHistory).length;
  search.setMode('albums'); await tick();
  assert.equal(calls.filter(c => c.command === 'search_all' && c.args.recordHistory).length, historyCount);
});

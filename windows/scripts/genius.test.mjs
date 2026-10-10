import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const transpile = source => ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const typesCode = transpile(await readFile(new URL('../src/lib/genius/types.ts', import.meta.url), 'utf8'));
const typesUrl = `data:text/javascript;base64,${Buffer.from(typesCode).toString('base64')}`;
const code = transpile(await readFile(new URL('../src/lib/genius/controller.ts', import.meta.url), 'utf8')).replace("'./types'", JSON.stringify(typesUrl));
const { GeniusController } = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
const { externalUrl, lyricSpans } = await import(typesUrl);
const track = id => ({ videoId: id, title: id, artists: 'Artist', thumbnail: null, duration: 120 });
const song = id => ({ id, title: 'Song', artist: 'Artist', url: `https://genius.com/${id}`, description: null, releaseDate: null, annotationCount: 0, producers: [], writers: [], performances: [] });
const matched = id => ({ status: 'matched', song: song(id), candidates: [], chosenByUser: false });
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };
const flush = () => new Promise(resolve => setImmediate(resolve));
test('cache is read before network, automatic requests remain opt-in and opening advances lookup', async () => {
  const calls = []; const rpc = async (command, args) => { calls.push(command); if (command === 'genius_cached') return null; if (command === 'genius_resolve') return matched(1); if (command === 'genius_annotations') return { items: [], nextPage: null }; return { lines: [] }; };
  const controller = new GeniusController(rpc, () => {});
  controller.setTrack(track('A'), 1, 1); controller.playbackStarted(); await flush();
  assert.deepEqual(calls, ['genius_cached']); await controller.ensureNow();
  assert.deepEqual(calls, ['genius_cached', 'genius_resolve', 'genius_annotations', 'genius_lyrics']);
  assert.equal(controller.snapshot.phase, 'matched'); controller.dispose();
});
test('late cache success and late lookup error cannot publish across track/session identity', async () => {
  const a = deferred(); const b = deferred(); let calls = 0;
  const controller = new GeniusController(async command => command === 'genius_cached' ? (calls++ === 0 ? a.promise : null) : b.promise, () => {});
  controller.setTrack(track('A'), 1, 1); controller.setTrack(track('B'), 2, 1); a.resolve(matched(99)); await flush();
  assert.equal(controller.snapshot.resolution, null); const lookup = controller.ensureNow(); await flush();
  controller.setTrack(track('B'), 2, 2); b.reject(new Error('old failure')); await lookup;
  assert.equal(controller.snapshot.phase, 'idle'); assert.equal(controller.snapshot.error, null); controller.dispose();
});
test('search replacement, retained match on failed choice, and report identity/dedupe', async () => {
  const searches = [deferred(), deferred()]; const report = deferred(); let index = 0; let reports = 0;
  const controller = new GeniusController(async command => {
    if (command === 'genius_cached') return { status: 'ambiguous', song: null, candidates: [], chosenByUser: false };
    if (command === 'genius_search') return searches[index++].promise;
    if (command === 'genius_choose') throw new Error('cannot choose');
    if (command === 'genius_report_miss') { reports++; return report.promise; }
  }, () => {});
  controller.setTrack(track('A'), 1); await flush();
  const first = controller.search('first'); const second = controller.search('second'); searches[1].resolve([{ id: 2 }]); await second; searches[0].resolve([{ id: 1 }]); await first;
  assert.equal(controller.snapshot.searchResults[0].id, 2);
  await controller.choose({ id: 2 }); assert.equal(controller.snapshot.phase, 'ambiguous');
  const pending = controller.reportCurrentMiss(); await controller.reportCurrentMiss(); assert.equal(reports, 1);
  controller.setTrack(track('B'), 2); report.resolve(null); await pending; assert.equal(controller.snapshot.reportSaved, false); controller.dispose();
});
test('annotation pagination dedupes within/across pages and retry preserves previous pages', async () => {
  let page2 = 0;
  const annotation = id => ({ id, referentId: id, fragment: 'fragment', body: 'body', bodySpans: [], imageUrls: [] });
  const controller = new GeniusController(async (command, args) => {
    if (command === 'genius_cached') return null;
    if (command === 'genius_resolve') return matched(1);
    if (command === 'genius_lyrics') return { lines: [] };
    if (command === 'genius_annotations') {
      if (args.page === 1) return { items: [annotation(1), annotation(1)], nextPage: 2 };
      if (page2++ === 0) throw new Error('network');
      return { items: [annotation(1), annotation(2), annotation(2)], nextPage: null };
    }
  }, () => {});
  controller.setTrack(track('A'), 1); await controller.ensureNow();
  assert.deepEqual(controller.snapshot.annotations.map(a => a.id), [1]); await controller.loadMoreAnnotations();
  assert.equal(controller.snapshot.nextPage, 2); assert.deepEqual(controller.snapshot.annotations.map(a => a.id), [1]);
  await controller.retryContents(); assert.deepEqual(controller.snapshot.annotations.map(a => a.id), [1, 2]); controller.dispose();
});
test('same-track match replacement rejects old content and resets content loading flags', async () => {
  const oldLyrics = deferred(); let chosen = false;
  const controller = new GeniusController(async (command, args) => {
    if (command === 'genius_cached') return null;
    if (command === 'genius_resolve') return matched(1);
    if (command === 'genius_choose') { chosen = true; return matched(2); }
    if (command === 'genius_annotations') return { items: [], nextPage: null };
    if (command === 'genius_lyrics') return args.songId === 1 ? oldLyrics.promise : { lines: [{ text: 'new', spans: [] }] };
  }, () => {});
  controller.setTrack(track('A'), 1); const opening = controller.ensureNow(); await flush(); await controller.choose({ id: 2 });
  oldLyrics.resolve({ lines: [{ text: 'old', spans: [] }] }); await opening;
  assert.equal(controller.snapshot.lyrics[0].text, 'new'); assert.equal(controller.snapshot.loadingLyrics, false); controller.dispose();
});
test('lyric spans preserve whitespace/adjacent fragments and external links reject executable schemes', () => {
  const line = { text: 'a bc', referentId: null, spans: [{ text: 'a ', referentId: 1 }, { text: 'b', referentId: 2 }, { text: 'c', referentId: null }] };
  assert.deepEqual(lyricSpans(line), line.spans); assert.equal(lyricSpans(line).map(x => x.text).join(''), line.text);
  assert.equal(externalUrl('javascript:alert(1)'), null); assert.equal(externalUrl('file:///secret'), null); assert.equal(externalUrl('https://genius.com/path'), 'https://genius.com/path');
});
test('opening an annotation walks pages until its referent is available and stops at that page', async () => {
  const pages=[]; const firstPage=deferred();
  const controller=new GeniusController(async(command,args)=>{
    if(command==='genius_cached')return null;
    if(command==='genius_resolve')return matched(1);
    if(command==='genius_lyrics')return {lines:[]};
    if(command==='genius_annotations'){
      pages.push(args.page);
      if(args.page===1)await firstPage.promise;
      return {items:[{id:args.page,referentId:args.page*10,fragment:'fragment',body:'body',bodySpans:[],imageUrls:[]}],nextPage:args.page+1};
    }
  },()=>{});
  controller.setTrack(track('A'),1);const opening=controller.ensureNow();await flush();
  const annotation=controller.ensureAnnotation(30);firstPage.resolve(null);await opening;await annotation;
  assert.deepEqual(pages,[1,2,3]);assert.equal(controller.snapshot.annotations.at(-1).referentId,30);
  await controller.ensureAnnotation(10);assert.deepEqual(pages,[1,2,3]);controller.dispose();
});
test('Genius preferences persist independently of changing track/account and tolerate unavailable storage', async () => {
  const values=new Map();const preferences={getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value)};
  const rpc=async()=>null;const controller=new GeniusController(rpc,()=>{},preferences);
  controller.setAutomaticFetch(true);controller.setDiagnostics(true);controller.setTrack(track('A'),1,1);controller.setTrack(track('B'),2,2);
  assert.equal(controller.snapshot.automaticFetch,true);assert.equal(controller.snapshot.diagnostics,true);controller.dispose();
  const reopened=new GeniusController(rpc,()=>{},preferences);assert.equal(reopened.snapshot.automaticFetch,true);assert.equal(reopened.snapshot.diagnostics,true);reopened.dispose();
  const unavailable=new GeniusController(rpc,()=>{},{getItem:()=>{throw new Error('disabled');},setItem:()=>{throw new Error('disabled');}});
  unavailable.setAutomaticFetch(true);assert.equal(unavailable.snapshot.automaticFetch,true);unavailable.dispose();
});

test('empty accepted contents are not fetched on repeated playback ticks; explicit retry and new track reset attempts', async () => {
  const calls=[];
  const controller=new GeniusController(async(command,args)=>{
    calls.push({command,args});
    if(command==='genius_cached')return null;
    if(command==='genius_resolve')return matched(1);
    if(command==='genius_annotations')return {items:[],nextPage:null};
    if(command==='genius_lyrics')return {lines:[]};
  },()=>{});
  const count=command=>calls.filter(call=>call.command===command).length;
  controller.setTrack(track('A'),1);
  for(let i=0;i<5;i++)await controller.ensureNow();
  assert.equal(count('genius_resolve'),1);assert.equal(count('genius_annotations'),1);assert.equal(count('genius_lyrics'),1);
  await controller.retryContents();
  assert.equal(count('genius_resolve'),1);assert.equal(count('genius_annotations'),2);assert.equal(count('genius_lyrics'),2);
  await controller.ensureNow();assert.equal(count('genius_lyrics'),2);
  controller.setTrack(track('B'),2);await controller.ensureNow();await controller.ensureNow();
  assert.equal(count('genius_resolve'),2);assert.equal(count('genius_annotations'),3);assert.equal(count('genius_lyrics'),3);
  await controller.refresh();assert.equal(count('genius_resolve'),3);assert.equal(count('genius_annotations'),4);assert.equal(count('genius_lyrics'),4);
  assert.equal(calls.filter(call=>call.command==='genius_lyrics').at(-1).args.force,true);controller.dispose();
});

test('failed contents retain an error without tick retries and explicit retry reloads each failed resource once', async () => {
  let annotationCalls=0,lyricCalls=0;
  const controller=new GeniusController(async(command)=>{
    if(command==='genius_cached')return null;
    if(command==='genius_resolve')return matched(1);
    if(command==='genius_annotations'){if(++annotationCalls===1)throw Error('annotations unavailable');return {items:[],nextPage:null};}
    if(command==='genius_lyrics'){if(++lyricCalls===1)throw Error('lyrics unavailable');return {lines:[]};}
  },()=>{});
  controller.setTrack(track('A'),1);
  for(let i=0;i<5;i++)await controller.ensureNow();
  assert.equal(annotationCalls,1);assert.equal(lyricCalls,1);assert.ok(controller.snapshot.error);
  await controller.retryContents();for(let i=0;i<3;i++)await controller.ensureNow();
  assert.equal(annotationCalls,2);assert.equal(lyricCalls,2);assert.equal(controller.snapshot.error,null);controller.dispose();
});

test('nullable network content is terminal too and does not behave like a cache miss', async () => {
  let contents=0;
  const controller=new GeniusController(async(command)=>{
    if(command==='genius_cached')return null;
    if(command==='genius_resolve')return matched(1);
    contents++;return null;
  },()=>{});
  controller.setTrack(track('A'),1);
  for(let i=0;i<4;i++)await controller.ensureNow();
  assert.equal(contents,2);assert.equal(controller.snapshot.error,null);
  await controller.retryContents();assert.equal(contents,4);controller.dispose();
});

test('failed resolution is not retried on progress; refresh and a new session explicitly permit another attempt', async () => {
  let resolutions=0,contents=0;
  const controller=new GeniusController(async(command)=>{
    if(command==='genius_cached')return null;
    if(command==='genius_resolve'){if(++resolutions===1)throw Error('lookup unavailable');return matched(1);}
    contents++;return command==='genius_lyrics'?{lines:[]}:{items:[],nextPage:null};
  },()=>{});
  controller.setTrack(track('A'),1,'session1');
  for(let i=0;i<5;i++)await controller.ensureNow();
  assert.equal(resolutions,1);assert.equal(contents,0);assert.equal(controller.snapshot.phase,'error');
  await controller.refresh();await controller.ensureNow();assert.equal(resolutions,2);assert.equal(contents,2);
  controller.setTrack(track('A'),1,'session2');await controller.ensureNow();assert.equal(resolutions,3);assert.equal(contents,4);controller.dispose();
});

test('cached content miss remains lazy until opening, while valid empty cache is an accepted result', async () => {
  for(const cacheHit of [false,true]){
    const calls=[];
    const controller=new GeniusController(async(command,args)=>{
      calls.push({command,args});
      if(command==='genius_cached')return matched(1);
      if(args.cached&&!cacheHit)return null;
      return command==='genius_lyrics'?{lines:[]}:{items:[],nextPage:null};
    },()=>{});
    controller.setTrack(track('A'),1);await flush();
    assert.equal(calls.filter(call=>call.args?.cached===false).length,0);
    for(let i=0;i<3;i++)await controller.ensureNow();
    assert.equal(calls.filter(call=>call.command==='genius_annotations').length,cacheHit?1:2);
    assert.equal(calls.filter(call=>call.command==='genius_lyrics').length,cacheHit?1:2);
    assert.equal(calls.some(call=>call.command==='genius_resolve'),false);controller.dispose();
  }
});

test('concurrent opening and stale failed content cannot duplicate requests or poison the next track', async () => {
  const firstLyrics=deferred(),firstAnnotations=deferred();let lyricCalls=0,annotationCalls=0;
  const controller=new GeniusController(async(command)=>{
    if(command==='genius_cached')return null;
    if(command==='genius_resolve')return matched(1);
    if(command==='genius_annotations')return ++annotationCalls===1?firstAnnotations.promise:{items:[],nextPage:null};
    if(command==='genius_lyrics')return ++lyricCalls===1?firstLyrics.promise:{lines:[]};
  },()=>{});
  controller.setTrack(track('A'),1);const first=controller.ensureNow();await flush();
  const tick=controller.ensureNow();await flush();assert.equal(lyricCalls,1);assert.equal(annotationCalls,1);
  controller.setTrack(track('B'),2);await controller.ensureNow();
  firstLyrics.reject(Error('old lyrics'));firstAnnotations.reject(Error('old annotations'));await Promise.all([first,tick]);
  await controller.ensureNow();assert.equal(controller.snapshot.error,null);assert.equal(lyricCalls,2);assert.equal(annotationCalls,2);controller.dispose();
});

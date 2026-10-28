import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { compile } from 'svelte/compiler';
import ts from 'typescript';
import { render } from 'svelte/server';

// Render the real components, including their conditional controls and shared variants.
const root = fileURLToPath(new URL('../', import.meta.url));
const cache = path.join(root, '.cache/search-primary-test');
await mkdir(cache, { recursive: true });
const modules = new Map();
async function compiledModule(filename) {
  if (modules.has(filename)) return modules.get(filename);
  const outputPath = path.join(cache, `${createHash('sha256').update(filename).digest('hex')}.mjs`);
  const outputUrl = pathToFileURL(outputPath).href;
  modules.set(filename, outputUrl);
  const source = await readFile(filename, 'utf8');
  let code = filename.endsWith('.svelte') ? compile(source, { filename, generate: 'server' }).js.code
    : filename.endsWith('.json') ? `export default ${source};`
    : ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
  code=code.replace(/import\s+['"][^'"]+\.css['"];?/g,'');
  for (const match of [...code.matchAll(/\bfrom\s+(['"])([^'"]+)\1/g)]) {
    const specifier = match[2];
    if (!specifier.startsWith('.') && !specifier.startsWith('$lib/')) continue;
    const base = specifier.startsWith('$lib/') ? path.join(root, 'src/lib', specifier.slice(5)) : path.resolve(path.dirname(filename), specifier);
    let resolved;
    for (const candidate of [base, `${base}.ts`, path.join(base, 'index.ts')]) {
      try { await access(candidate); if (path.extname(candidate)) { resolved = candidate; break; } } catch { /* next extension */ }
    }
    assert.ok(resolved, `Resolve ${specifier} from ${filename}`);
    code = code.replace(match[0], `from '${await compiledModule(resolved)}'`);
  }
  await writeFile(outputPath, code);
  return outputUrl;
}
async function component(relative) { return (await import(await compiledModule(path.join(root, relative)))).default; }
const Spotlight = await component('src/lib/components/search/SpotlightSearch.svelte');
const noop = () => {};
const song = {videoId:'track',title:'Song (feat. Guest)',artists:'Main Artist',artistId:'main',artistRuns:[{text:'Main Artist',id:'main'}],album:'Album',albumId:'album',thumbnail:null,duration:60};
const card = {kind:'artist',id:'artist',title:'Artist',subtitle:null,thumbnail:null,duration:null};
function modal(preview, recents=[], canUndo=false) {
  const result=preview.results;
  preview={...preview,associatedQuery:preview.associatedQuery??preview.query,entries:[
    ...recents.map(recent=>recent.kind==='query'?{kind:'history',id:recent.key,query:recent.query,runs:[{text:recent.query,bold:false}],feedbackToken:recent.key}:{kind:'media',id:recent.key,song:recent.track,runs:[]}),
    ...(preview.queries??[]).map((query,index)=>({id:`query-${index}`,kind:'text',query,runs:[{text:query,bold:false}]})),
    ...(result?.top??[]).map(card=>({id:card.id,kind:'media',card,song:result.topSongs?.find(song=>song.videoId===card.id),runs:[]})),
    ...(result?.songs??[]).map(song=>({id:song.videoId,kind:'media',song,runs:[]})),
    ...(result?.artists??[]).map(card=>({id:card.id,kind:'media',card,runs:[]})),
  ]};
  return render(Spotlight,{props:{preview,recents,canUndo,backendReady:true,onQueryChange:noop,onCommit:noop,onDismiss:noop,onSelectCard:noop,onPlaySong:noop,onRemoveSuggestion:noop}}).body;
}
function buttons(html) { return [...html.matchAll(/<button\b[^>]*>/g)].map(match=>match[0]); }
function primaries(html) { return buttons(html).filter(tag=>tag.includes('data-search-primary')); }
function assertSecondaryKeyboardAccess(html) {
  const secondary=buttons(html).filter(tag=>/class="(?:recent-remove|more|compact-menu|credit-link|featured-link)/.test(tag));
  assert.ok(secondary.length>0);
  assert.ok(secondary.every(tag=>!tag.includes('data-search-primary')&&!tag.includes('tabindex="-1"')&&!tag.includes('disabled')));
}
test('recent HTML marks query and song playback only; heading, delete and credits remain secondary',()=>{
  const html=modal({query:'',results:null},[{kind:'query',key:'query:hello',query:'hello',lastUsedAt:2},{kind:'track',key:'track:youtube:track',track:song,lastUsedAt:1}],true);
  assert.deepEqual(primaries(html).map(tag=>tag.match(/class="([^"]+)"/)[1].split(/\s+/)[0]),['query-suggestion','play']);
  assert.ok(html.includes('Quitar del historial de YouTube Music'));
  assertSecondaryKeyboardAccess(html);
});
test('QuickResults HTML marks song playback and MediaCard open in provider section order',()=>{
  const html=modal({query:'hello',associatedQuery:'hello',results:{top:[],topSongs:[],songs:[song],artists:[card],albums:[],playlists:[]},error:null});
  assert.deepEqual(primaries(html).map(tag=>tag.match(/class="([^"]+)"/)[1].split(/\s+/)[0]),['play','primary']);
  assertSecondaryKeyboardAccess(html);
});
test('Arrow navigation reads primary buttons while the Tab trap preserves secondary controls',async()=>{
  const source=await readFile(path.join(root,'src/lib/components/search/SpotlightSearch.svelte'),'utf8');
  const arrow=source.slice(source.indexOf("if ((event.key === 'ArrowDown'"),source.indexOf("if (event.key !== 'Tab'"));
  assert.ok(arrow.includes("'.results-scroll button[data-search-primary]:not(:disabled)'"));
  assert.ok(!arrow.includes("'.results-scroll button:not(:disabled)'"));
  assert.ok(source.includes("'button:not(:disabled), input:not(:disabled), [tabindex=\"0\"]'"));
});

test('provider media credits retain direct artist and album navigation',async()=>{
 const source=await readFile(path.join(root,'src/lib/components/search/QuickResults.svelte'),'utf8');
 assert.ok(source.includes("onOpenArtist={id=>open('artist',id)}"));
 assert.ok(source.includes("onOpenAlbum={id=>open('album',id)}"));
 const spotlight=await readFile(path.join(root,'src/lib/components/search/SpotlightSearch.svelte'),'utf8');
 assert.ok(spotlight.includes('function selectCard(card: BrowseCardDto) { dismissForNavigation(); onSelectCard(card); }'));
});

test('text-only provider suggestions remain separate primary rows with no invented native result',()=>{
 const html=modal({query:'typed',associatedQuery:'typed',queries:['provider second','provider first'],results:{top:[],topSongs:[],songs:[],artists:[],albums:[],playlists:[]},error:null});
 assert.equal(primaries(html).length,2);assert.ok(html.indexOf('provider second')<html.indexOf('provider first'));
 assert.ok(!html.includes('media-card'));assert.ok(!html.includes('song-row'));assert.ok(html.includes('query-suggestions'));
});

test('inline preview arrow navigation skips secondary artist and menu buttons',async()=>{
 const source=await readFile(path.join(root,'src/lib/components/search/SearchView.svelte'),'utf8');
 const arrow=source.slice(source.indexOf("if (showPreview &&"),source.indexOf("if (event.key === 'Escape')"));
 assert.ok(arrow.includes("'.preview-content button[data-search-primary]:not(:disabled)'"));assert.ok(arrow.includes('searchInput.focus()'));assert.ok(source.includes("document.querySelector('[role=\"menu\"]')"));
});

test('full search renders provider correction and an explicit principal with three related rows initially',async()=>{
 const SearchView=await component('src/lib/components/search/SearchView.svelte');
 const related=Array.from({length:5},(_,index)=>({...card,id:`related-${index}`,title:`Related ${index+1}`}));
 const data={query:'typo',lastSearchedQuery:'typo',mode:'all',top:[card],topSongs:[],songs:[],videos:[],albums:[],artists:[],playlists:[],hasSearched:true,isLoading:false,error:null,partialErrors:{},page:{chips:[],continuation:null,correction:{query:'provider corrected',applied:true},sections:[{id:'top',title:'Top',layout:'top',items:[card,...related],songs:[],primaryItemIndex:0,relatedItemIndices:[1,2,3,4,5],actions:[]}]}};
 const html=render(SearchView,{props:{data,backendReady:true,currentTrackId:null,isPlaying:false,draftQuery:'typo',preview:{query:'',results:null},onAction:noop,onSelectParams:noop,onLoadMore:noop,onMore:noop,onSearchOriginal:noop,onSubmit:noop,onRetry:noop,onModeChange:noop,onPlaySong:noop,onOpenAlbum:noop,onDraftChange:noop,onPreviewFocus:noop,onPreviewDismiss:noop}}).body;
 assert.equal(html.split('provider corrected').length-1,1);assert.ok(!html.includes('%@'));assert.match(html,/class="[^"]*principal/);assert.match(html,/class="[^"]*artist/);assert.ok(html.includes('Related 1'));assert.ok(html.includes('Related 3'));assert.ok(!html.includes('Related 4'));assert.ok(html.includes('data-size="utility"'));assert.ok(html.includes('Buscar el texto original'));
});

test('autocomplete caps active-query text at three while preserving heterogeneous music order and metadata',()=>{
 const topSong={kind:'song',id:song.videoId,title:song.title,subtitle:song.artists,thumbnail:null,duration:60};
 const album={kind:'album',id:'record',title:'Provider Album',subtitle:'Main Artist',thumbnail:null,duration:null};
 const html=modal({query:'typed',associatedQuery:'typed',queries:['query one','query two','query three','query four'],results:{top:[topSong,card,album],topSongs:[song],songs:[],artists:[],albums:[],playlists:[]},error:null});
 assert.deepEqual(primaries(html).map(tag=>tag.match(/class="([^"]+)"/)?.[1].split(/\s+/)[0]??'query'),['query-suggestion','query-suggestion','query-suggestion','play','primary','primary']);
 assert.ok(html.indexOf('query one')<html.indexOf('Song (feat.'));assert.ok(!html.includes('query four'));
 assert.equal((html.match(/class="song-row/g)??[]).length,1);assert.ok(html.includes('featured-link'));assert.ok(html.indexOf('Artist</h3>')<html.indexOf('Provider Album'));
});

test('quick typed video shows its video label and remains a playable primary result',()=>{
 const video={...song,videoId:'video',title:'Provider Video',isVideo:true};
 const html=modal({query:'video',associatedQuery:'video',queries:[],results:{top:[{...card,kind:'video',id:'video',title:video.title}],topSongs:[video],songs:[],artists:[],albums:[],playlists:[]},error:null});
 assert.equal(primaries(html).length,1);assert.ok(html.includes('VIDEO'));assert.ok(html.includes('Provider Video'));
});

test('provider section exposes show-all for a query-only endpoint',async()=>{
 const SearchView=await component('src/lib/components/search/SearchView.svelte');
 const data={query:'q',lastSearchedQuery:'q',mode:'all',hasSearched:true,isLoading:false,error:null,page:{chips:[],correction:null,continuation:null,sections:[{id:'query-only',title:'Provider section',layout:'list',items:[],songs:[],actions:[],moreQuery:'provider-expanded-query',moreParams:null,moreBrowseId:null}]}};
 const html=render(SearchView,{props:{data,backendReady:true,currentTrackId:null,isPlaying:false,draftQuery:'q',preview:{query:'',results:null},onAction:noop,onSelectParams:noop,onLoadMore:noop,onMore:noop,onSubmit:noop,onRetry:noop,onModeChange:noop,onPlaySong:noop,onOpenAlbum:noop,onDraftChange:noop,onPreviewFocus:noop,onPreviewDismiss:noop}}).body;
 assert.ok(html.includes('Mostrar todo'));
});

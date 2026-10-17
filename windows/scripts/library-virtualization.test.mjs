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
const cache = path.join(root, '.cache/library-virtualization-test');
await mkdir(cache, { recursive: true });
const modules = new Map();
async function compiledModule(filename, layout = 'grid') {
  const moduleKey = `${filename}:${layout}`;
  if (modules.has(moduleKey)) return modules.get(moduleKey);
  const outputPath = path.join(cache, `${createHash('sha256').update(moduleKey).digest('hex')}.mjs`);
  const outputUrl = pathToFileURL(outputPath).href;
  modules.set(moduleKey, outputUrl);
  let source = await readFile(filename, 'utf8');
  // SSR skips account onMount. Seed the existing local layout preference for each fixture.
  if (filename.endsWith('/library/LibraryView.svelte')) {
    const initial = 'libraryDefaults());';
    assert.ok(source.includes(initial));
    source = source.replace(initial, `{...libraryDefaults(),layout:'${layout}'});`);
  }
  let code = filename.endsWith('.svelte') ? compile(source, { filename, generate: 'server' }).js.code
    : filename.endsWith('.json') ? `export default ${source};`
    : ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
  // Presentation-only CSS is bundled by Vite, not imported by Node SSR tests.
  code = code.replace(/import\s+['"][^'"]+\.css['"];?/g, '');
  for (const match of [...code.matchAll(/\bfrom\s+(['"])([^'"]+)\1/g)]) {
    const specifier = match[2];
    if (!specifier.startsWith('.') && !specifier.startsWith('$lib/')) continue;
    const base = specifier.startsWith('$lib/') ? path.join(root, 'src/lib', specifier.slice(5)) : path.resolve(path.dirname(filename), specifier);
    let resolved;
    for (const candidate of [base, `${base}.ts`, path.join(base, 'index.ts')]) {
      try { await access(candidate); if (path.extname(candidate)) { resolved = candidate; break; } } catch { /* next extension */ }
    }
    assert.ok(resolved, `Resolve ${specifier} from ${filename}`);
    code = code.replace(match[0], `from '${await compiledModule(resolved, layout)}'`);
  }
  await writeFile(outputPath, code);
  return outputUrl;
}
async function component(relative, layout) { return (await import(await compiledModule(path.join(root, relative), layout))).default; }
const Grid = await component('src/lib/components/library/LibraryView.svelte', 'grid');
const List = await component('src/lib/components/library/LibraryView.svelte', 'list');
const noop = () => {};
const collection = (kind, count) => Array.from({length:count}, (_, index) => ({kind, id:`${kind}-${index}`, title:`${kind} ${index}`, subtitle:'A subtitle with enough words to wrap at card width', thumbnail:null}));
function library(component, tab, count=2000) {
  return render(component, {props:{loggedIn:true, tab, songs:[], playlists:collection('playlist',count), albums:collection('album',count), artists:collection('artist',count),
    loading:false,loadingMore:false,error:null,continuation:null,currentTrackId:null,isPlaying:false,likedIds:new Set(),pendingIds:new Set(),
    onTab:noop,onRefresh:noop,onLoadMore:noop,onPlay:noop,onOpenCard:noop,onToggleLike:noop,onToggleSaved:noop,onCreatePlaylist:noop,onLogin:noop}}).body;
}
function cards(html) { return [...html.matchAll(/<article\b[^>]*class="media-card[^"]*"/g)]; }
for (const tab of ['playlists','albums','artists']) {
  test(`${tab} grid mounts a viewport of cards rather than the entire collection`, () => {
    const html = library(Grid,tab);
    assert.ok(cards(html).length>0 && cards(html).length<40);
    assert.ok(!html.includes(`${tab==='playlists'?'playlist':tab==='albums'?'album':'artist'} 1999`));
    assert.equal((html.match(/class="pin-actions/g)??[]).length,cards(html).length);
    assert.ok(!cards(html).some(match=>match[0].includes('compact')));
  });
  test(`${tab} list keeps compact actions while mounting a bounded viewport`, () => {
    const html = library(List,tab);
    assert.ok(cards(html).length>0 && cards(html).length<24);
    assert.ok(cards(html).every(match=>match[0].includes('compact')));
    assert.equal((html.match(/class="pin-actions/g)??[]).length,cards(html).length);
    assert.equal((html.match(/class="compact-menu/g)??[]).length,cards(html).length);
    assert.ok(html.includes('height:92px'));
  });
}
test('a small collection renders all its cards in either presentation', () => {
  for (const component of [Grid,List]) assert.equal(cards(library(component,'albums',3)).length,3);
});

const VirtualCatalog = await component('src/lib/components/explore/VirtualCatalog.svelte', 'grid');
test('Library card pitch reserves the extra pin row without changing the default catalog pitch', () => {
  const items=collection('album',20), children=()=>{};
  // Initial width800 gives4 columns and186.5px artwork. Height includes every row, not just mounted cells.
  const standard=render(VirtualCatalog,{props:{items,children}}).body;
  const library=render(VirtualCatalog,{props:{items,children,rowExtra:132}}).body;
  assert.ok(standard.includes('height: 1322.5px'));
  assert.ok(library.includes('height: 1592.5px'));
});

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
const cache = path.join(root, '.cache/queue-presentation-test');
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
const QueuePanel = await component('src/lib/components/fullscreen/QueuePanel.svelte');
const TrackArtwork = await component('src/lib/components/common/TrackArtwork.svelte');
const TrackActivity = await component('src/lib/components/common/TrackActivity.svelte');

const entry = (entryId, title = 'Canción repetida') => ({
  entryId, videoId: 'same-video', title, artists: 'Artista', artistId: 'artist', artistRuns: [],
  album: 'Álbum', albumId: 'album', thumbnail: null, duration: 255,
});
function playback(items = [entry('first'), entry('duplicate')]) {
  return { queue: { items, currentIndex: 0, source: { kind: 'album', id: 'album', title: 'Álbum' }, radio: null },
    currentTrack: items[0] ?? null, isPlaying: true, isLoading: false, position: 0, duration: 255 };
}
const noop = () => {};
function panel(overrides = {}) {
  return render(QueuePanel, { props: { playback: playback(), loggedIn: true,
    onSelectQueue: noop, onMoveQueue: noop, onToggleLike: noop, onDislike: noop,
    onQueueContextMenu: noop, onOpenArtist: noop, onOpenAlbum: noop, ...overrides } }).body;
}
function buttonClasses(html) {
  return [...html.matchAll(/<button\b[^>]*class="([^"]+)"/g)].map(match => match[1].split(/\s+/)[0]);
}

test('queue renders controls in visual and keyboard DOM order for distinct duplicate occurrences', () => {
  const html = panel();
  assert.deepEqual(buttonClasses(html), [
    'queue-select', 'track-artwork', 'credit-link', 'credit-link', 'queue-action', 'queue-action', 'reorder-handle',
    'queue-select', 'track-artwork', 'credit-link', 'credit-link', 'queue-action', 'queue-action', 'reorder-handle',
  ]);
  const first = html.slice(html.indexOf('data-entry-id="first"'), html.indexOf('data-entry-id="duplicate"'));
  assert.ok(!html.includes('row-menu'));
  assert.ok(first.indexOf('dislike-action') < first.indexOf('like-action'));
  assert.ok(first.indexOf('like-action') < first.indexOf('queue-timing'));
  assert.ok(first.includes('aria-current="true"'));
  assert.ok(!html.includes('play-control'));
  assert.ok(html.includes('speaker'));
  assert.ok(html.includes('4:15'));
});

test('guest and optional callbacks preserve the available controls without inventing votes', () => {
  const html = panel({ loggedIn: false });
  assert.ok(!html.includes(' like-action'));
  assert.ok(html.includes('dislike-action'));
  assert.ok(!html.includes('row-menu'));
  const minimal = panel({ loggedIn: false, onDislike: undefined, onQueueContextMenu: undefined });
  assert.ok(!minimal.includes('dislike-action'));
  assert.ok(!minimal.includes('row-menu'));
  assert.equal(buttonClasses(minimal).filter(name => name === 'reorder-handle').length, 2);
});

test('empty panel omits redundant context but retains source and radio errors and retry controls', () => {
  const empty = playback([]);
  const html = panel({ playback: empty });
  assert.ok(html.includes('empty-panel'));
  assert.ok(!html.includes('queue-heading'));
  empty.sourceLoad = { error: 'Error fuente', loading: false, hasMore: true, loadedCount: 0, canRetry: true };
  empty.queue.radio = { error: 'Error radio', loading: false, canRetry: true };
  const errors = panel({ playback: empty, onRetrySource: noop, onRetryRadio: noop });
  assert.ok(errors.includes('Error fuente') && errors.includes('Error radio'));
  assert.equal((errors.match(/role="alert"/g) ?? []).length, 2);
  assert.equal((errors.match(/>Reintentar<\/button>/g) ?? []).length, 2);
  assert.ok(errors.includes('empty-panel'));
});

test('pending playback and likes retain disabled controls and accessible loading without overlay', () => {
  const state = playback(); state.isLoading = true;
  const html = panel({ playback: state, pendingIds: new Set(['same-video']) });
  const buttons = [...html.matchAll(/<button\b[^>]*>/g)].map(match => match[0]);
  assert.ok(buttons.find(button => button.includes('track-artwork')).includes('aria-busy="true"'));
  assert.ok(buttons.filter(button => button.includes('like-action')).every(button => button.includes('disabled')));
  assert.ok(buttons.filter(button => button.includes('dislike-action')).every(button => button.includes('disabled')));
  assert.ok(!html.includes('play-control'));
});

test('queue variants are opt-in and preserve the default shared artwork and activity presentation', () => {
  const props = { title: 'Título', thumbnail: null, active: true, playing: true, onPlay: noop };
  assert.ok(render(TrackArtwork, { props }).body.includes('play-control'));
  assert.ok(!render(TrackArtwork, { props: { ...props, showPlayOverlay: false } }).body.includes('play-control'));
  assert.ok(render(TrackActivity, { props: { active: true, playing: true } }).body.includes('bars'));
  const queue = render(TrackActivity, { props: { active: true, playing: false, presentation: 'queue' } }).body;
  assert.ok(queue.includes('speaker'));
  assert.ok(!queue.includes('bars'));
});

test('context heading keeps independent loading messages, partial count and localized origin title', () => {
  const state = playback();
  state.sourceLoad = { loading: true, hasMore: true, loadedCount: 2 };
  state.queue.radio = { loading: true };
  const html = panel({ playback: state });
  assert.ok(html.includes('context-loading'));
  assert.equal((html.match(/role="status"/g) ?? []).length, 2);
  assert.ok(html.includes('Álbum: Álbum'));
  assert.ok(html.includes('2 canciones'));
});

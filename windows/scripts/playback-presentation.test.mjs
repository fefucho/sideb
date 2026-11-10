import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import ts from 'typescript';

// The presentation module re-exports the shared footer geometry, so both are compiled side by side.
const root = fileURLToPath(new URL('../', import.meta.url)), cache = path.join(root, '.cache/playback-presentation-test');
await mkdir(cache, { recursive: true });
const compile = async name => ts.transpileModule(await readFile(path.join(root, 'src/lib/player', name + '.ts'), 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
await writeFile(path.join(cache, 'sidebarLayout.mjs'), await compile('sidebarLayout'));
await writeFile(path.join(cache, 'playbackPresentation.mjs'), (await compile('playbackPresentation')).replace("'./sidebarLayout'", "'./sidebarLayout.mjs'"));
const P = await import(pathToFileURL(path.join(cache, 'playbackPresentation.mjs')).href);

const fresh = () => P.initialPresentation();

test('repeated open/close converges and never leaves two presentations active', () => {
  let state = fresh();
  for (let i = 0; i < 25; i++) {
    state = P.toggleSidebar(state);
    assert.equal(state.mode, i % 2 === 0 ? 'sidebar' : 'bar');
    const live = P.interactiveSurfaces(state.mode);
    assert.equal(live.sidebar, state.mode === 'sidebar');
    assert.equal(live.bar && live.sidebar, false, 'duplicated controls have a single interactive destination');
  }
  assert.equal(P.closeSidebar(P.closeSidebar(state)).mode, 'bar', 'closing is idempotent');
  assert.equal(P.presentSidebar(P.presentSidebar(fresh())).mode, 'sidebar', 'opening is idempotent');
});

test('trigger toggles; a different section retargets instead of closing', () => {
  let state = P.toggleSidebar(fresh(), 'queue');
  assert.deepEqual([state.mode, state.sidebarPanel], ['sidebar', 'queue']);
  state = P.toggleSidebar(state, 'lyrics');
  assert.deepEqual([state.mode, state.sidebarPanel], ['sidebar', 'lyrics']);
  state = P.toggleSidebar(state, 'lyrics');
  assert.equal(state.mode, 'bar');
  assert.equal(state.sidebarPanel, 'lyrics', 'the last section is remembered within the session');
  assert.equal(P.toggleSidebar(state).sidebarPanel, 'lyrics');
});

test('bar visibility and the single interactive surface cover every mode', () => {
  assert.deepEqual(P.interactiveSurfaces('bar'), { bar: true, sidebar: false });
  assert.deepEqual(P.interactiveSurfaces('sidebar'), { bar: false, sidebar: true });
  assert.deepEqual(P.interactiveSurfaces('fullscreen'), { bar: true, sidebar: false });
});

test('fullscreen returns to its origin: bar -> bar, sidebar -> sidebar keeping the section read there', () => {
  let state = P.setFullscreen(fresh(), true, 'lyrics');
  assert.deepEqual([state.mode, state.origin], ['fullscreen', 'bar']);
  assert.equal(P.setFullscreen(state, true).origin, 'bar', 'a second request does not rewrite the origin');
  assert.equal(P.setFullscreen(state, false, 'lyrics').mode, 'bar');

  state = P.presentSidebar(fresh(), 'artwork');
  state = P.setFullscreen(state, true, 'queue');
  assert.deepEqual([state.mode, state.origin], ['fullscreen', 'sidebar']);
  const back = P.setFullscreen(state, false, 'lyrics');
  assert.deepEqual([back.mode, back.sidebarPanel], ['sidebar', 'lyrics']);
  assert.equal(P.setFullscreen(P.setFullscreen(fresh(), true), false, 'related').mode, 'bar');
  assert.equal(P.setFullscreen(P.setFullscreen(P.presentSidebar(fresh()), true), false, 'related').sidebarPanel, 'artwork', 'related maps to Now Playing');
  assert.equal(P.setFullscreen(fresh(), false).mode, 'bar', 'collapsing while not fullscreen is a no-op');
});

test('opening the sidebar from fullscreen replaces it and the next fullscreen records the new origin', () => {
  let state = P.setFullscreen(fresh(), true);
  state = P.toggleSidebar(state);
  assert.equal(state.mode, 'sidebar');
  state = P.setFullscreen(state, true);
  assert.equal(state.origin, 'sidebar');
});

test('section mapping between fullscreen and lateral panels', () => {
  assert.equal(P.fullscreenPanelFor('lyrics', 'queue'), 'lyrics');
  assert.equal(P.fullscreenPanelFor('queue', 'lyrics'), 'queue');
  assert.equal(P.fullscreenPanelFor('artwork', 'related'), 'related', 'Now Playing leaves the fullscreen section as it was');
  assert.equal(P.selectSidebarPanel(fresh(), 'queue').sidebarPanel, 'queue');
  const same = fresh();
  assert.equal(P.selectSidebarPanel(same, 'artwork'), same);
});

test('content reserve versus overlay at the real thresholds', () => {
  const reserve = P.sidebarReserve();
  assert.equal(reserve, 392);
  // Mac contract: reserve only while at least 480 px of page remain.
  assert.equal(P.contentReserve({ windowWidth: 253 + 392 + 480, leftReserve: 253, presented: true }), 392);
  assert.equal(P.contentReserve({ windowWidth: 253 + 392 + 479, leftReserve: 253, presented: true }), 0);
  assert.equal(P.contentReserve({ windowWidth: 4000, leftReserve: 253, presented: false }), 0);
  // Minimum window with expanded or collapsed navigation (tauri minWidth 960): overlay vs reserve.
  assert.equal(P.contentReserve({ windowWidth: 960, leftReserve: 253, presented: true }), 0);
  assert.equal(P.contentReserve({ windowWidth: 960, leftReserve: 60, presented: true }), 392, 'collapsed navigation leaves 508 px: reserve');
  assert.equal(P.contentReserve({ windowWidth: Number.NaN, leftReserve: 0, presented: true }), 0);
});

test('width is clamped to 350-420 and the reserve follows the real width', () => {
  assert.deepEqual([300, 350, 380, 420, 600, NaN].map(P.sidebarWidth), [350, 350, 380, 420, 420, 380]);
  assert.deepEqual([350, 380, 420].map(width => P.sidebarReserve(width)), [362, 392, 432]);
  assert.equal(P.contentReserve({ windowWidth: 253 + 432 + 480, leftReserve: 253, presented: true, width: 420 }), 432);
  assert.equal(P.contentReserve({ windowWidth: 253 + 432 + 479, leftReserve: 253, presented: true, width: 420 }), 0);
  assert.equal(P.contentReserve({ windowWidth: 253 + 362 + 480, leftReserve: 253, presented: true, width: 350 }), 362);
});

test('panel leaves the Windows titlebar clear and the footer keeps controls visible at short heights', () => {
  assert.equal(P.panelHeight(640, 32), 640 - 32 - 12);
  for (const height of [596, 700, 800, 1000]) {
    const footer = P.footerHeight(height, 'lyrics');
    assert.ok(footer < height - P.SIDEBAR.headerHeight, `${height}: header and footer fit together`);
    assert.ok(footer >= 200 + 68 + 16);
  }
  assert.equal(P.showsUpcoming(839, 'artwork'), false);
  assert.equal(P.showsUpcoming(840, 'artwork'), true);
  assert.equal(P.showsUpcoming(900, 'queue'), false);
  assert.equal(P.showsUpcoming(900, 'artwork', true), false, 'portrait never shows the up-next block');
  assert.equal(P.footerHeight(1000, 'artwork', true), 240, 'portrait footer is just the controls');
  assert.ok(P.progressToTransportSpacing(1000) >= 10);
});

test('bottom bar keeps symmetric room for the outer trigger', () => {
  assert.equal(P.barWidth(2000), 820);
  assert.equal(P.barWidth(707), 547);
  assert.equal(P.barWidth(100), 0);
});

test('shared transition: endpoints exact, no overshoot, reversal starts from the current position', () => {
  assert.equal(P.dampedEase(0), 0);
  assert.equal(P.dampedEase(1), 1);
  let last = 0;
  for (let i = 1; i <= 100; i++) {
    const value = P.dampedEase(i / 100);
    assert.ok(value >= last && value <= 1, 'monotonic and never above 1');
    last = value;
  }
  assert.equal(P.retargetDuration(0, 1, false), 380);
  assert.equal(P.retargetDuration(1, 0, true), 160);
  const half = P.retargetDuration(0.5, 0, false);
  assert.equal(half, 190, 'a reversal from halfway only takes the remaining distance');
  assert.ok(P.retargetDuration(0.3, 0.3, false) >= 1);
});

test('bar and panel surfaces: start, middle and end of the same progress', () => {
  const bar0 = P.barSurface(0, false), bar1 = P.barSurface(1, false);
  assert.deepEqual(bar0, { opacity: 1, x: 0, y: 0, scale: 1 });
  assert.equal(bar1.opacity, 0);
  assert.equal(bar1.y, 20);
  assert.ok(Math.abs(bar1.scale - 0.97) < 1e-9);
  const panel0 = P.panelSurface(0, false), panel1 = P.panelSurface(1, false);
  assert.equal(panel0.opacity, 0);
  assert.equal(panel0.x, 32);
  assert.deepEqual(panel1, { opacity: 1, x: 0, y: 0, scale: 1 });
  const middle = P.panelSurface(0.5, false), barMiddle = P.barSurface(0.5, false);
  assert.ok(middle.opacity > 0 && barMiddle.opacity < 1, 'both movements overlap');
  assert.equal(P.surfaceTransform(panel1), 'none');
  assert.match(P.surfaceTransform(middle), /^translate3d\(/);
  // The functions are pure in progress, so reversal retraces the same states.
  assert.deepEqual(P.panelSurface(0.37, false), P.panelSurface(0.37, false));
});

test('Reduce Motion is a plain cross-fade: no translation or scale', () => {
  for (const p of [0, 0.25, 0.5, 0.9, 1]) {
    for (const style of [P.barSurface(p, true), P.panelSurface(p, true)]) {
      assert.equal(style.x, 0); assert.equal(style.y, 0); assert.equal(style.scale, 1);
      assert.equal(P.surfaceTransform(style), 'none');
    }
    assert.ok(Math.abs(P.barSurface(p, true).opacity + P.panelSurface(p, true).opacity - 1) < 1e-9);
  }
  assert.equal(P.barSurface(Number.NaN, false).opacity, 1, 'bad progress cannot hide the bar');
});

test('syncProgress retargets once per destination and reverses from the animated position', () => {
  const calls = [];
  const tween = { current: 0, target: 0, set(value, options) { calls.push([value, options.duration]); this.target = value; if (options.duration === 0) this.current = value; return Promise.resolve(); } };
  P.syncProgress(tween, 'bar', false);
  assert.deepEqual(calls, [], 'already at the bar: nothing to do');
  P.syncProgress(tween, 'sidebar', false);
  assert.deepEqual(calls, [[1, 380]]);
  P.syncProgress(tween, 'sidebar', false);
  P.syncProgress(tween, 'fullscreen', false); // fullscreen retires the lateral panel's progress too
  assert.equal(calls.length, 3, 'a repeated destination is ignored; leaving the sidebar retargets');
  tween.current = 0; tween.target = 1; calls.length = 0;
  tween.current = 0.4;
  P.syncProgress(tween, 'bar', false);
  assert.deepEqual(calls, [[0.4, 0], [0, 152]], 'freezes at 0.4 and travels only the remaining 40 percent');
  calls.length = 0; tween.current = 1; tween.target = 1;
  P.syncProgress(tween, 'bar', true);
  assert.deepEqual(calls, [[0, 160]], 'Reduce Motion uses the short fade');
});

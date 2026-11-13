import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';

const read = path => readFile(new URL(`../src/${path}`, import.meta.url), 'utf8');
const [page, dock, sidebar, bar, model, fullscreen] = await Promise.all([
  read('routes/+page.svelte'), read('lib/components/playback-sidebar/PlaybackDock.svelte'), read('lib/components/playback-sidebar/PlaybackSidebar.svelte'),
  read('lib/components/player/PlayerBar.svelte'), read('lib/player/playbackPresentation.ts'), read('lib/components/fullscreen/FullscreenNowPlaying.svelte'),
]);
const body = (source, signature) => {
  const start = source.indexOf(signature); assert.notEqual(start, -1, signature);
  let depth = 0, i = source.indexOf('{', start);
  for (const from = i; i < source.length; i++) { if (source[i] === '{') depth++; if (source[i] === '}' && --depth === 0) return source.slice(from, i + 1); }
  throw new Error('unbalanced ' + signature);
};

test('the page has a single authoritative presentation; fullscreen and the sidebar derive from it', () => {
  assert.match(page, /let presentation = \$state\(initialPresentation\(\)\)/);
  assert.match(page, /const isFullscreenOpen = \$derived\(presentation\.mode === 'fullscreen'\)/);
  assert.match(page, /const sidebarOpen = \$derived\(presentation\.mode === 'sidebar'\)/);
  assert.doesNotMatch(page, /isFullscreenOpen = (true|false|open)\b/, 'no second writable source of truth for fullscreen');
  assert.doesNotMatch(page, /let (isSidebarOpen|sidebarVisible|sidebarClosing|sidebarOpening)\b/, 'no independent booleans for the lateral panel');
});

test('the shared transition is one retargeted progress: no timers or chained callbacks', () => {
  for (const [name, source] of [['PlaybackDock', dock], ['PlaybackSidebar', sidebar], ['playbackPresentation', model]]) {
    assert.doesNotMatch(source, /setTimeout|setInterval|requestAnimationFrame|transitionend|animationend/, `${name} must not chain timers`);
  }
  assert.match(page, /new Tween\(0, \{ easing: dampedEase \}\)/);
  assert.match(page, /syncProgress\(presentationProgress, mode, reduced\)/);
  assert.match(dock, /inert=\{!interactive\}/, 'the retiring bar is inert immediately');
  assert.match(sidebar, /inert=\{!interactive\}/, 'the retiring panel is inert immediately');
  assert.match(page, /interactive=\{sidebarOpen && !spotlightOpen\}/);
});

test('Escape closes fullscreen first and then the lateral panel, after popovers and dialogs', () => {
  const handler = body(page, 'async function handleWindowKeydown');
  const dialog = handler.indexOf('[role="dialog"], [role="menu"]'), popover = handler.indexOf("[data-volume-popover]");
  const fullscreenEscape = handler.indexOf('Escape" && isFullscreenOpen') >= 0 ? handler.indexOf('Escape" && isFullscreenOpen') : handler.indexOf("Escape' && isFullscreenOpen");
  const sidebarEscape = handler.indexOf("event.key === 'Escape' && sidebarOpen");
  assert.ok(dialog >= 0 && popover >= 0 && fullscreenEscape > popover && sidebarEscape > fullscreenEscape, [dialog, popover, fullscreenEscape, sidebarEscape].join());
});

test('bar shortcuts open only fullscreen sections; the outer trigger is the only way to open the panel from the bar', () => {
  const shortcut = body(page, 'function openPlayerPanel');
  assert.doesNotMatch(shortcut, /toggleSidebar|presentSidebar|closePlaybackSidebar/);
  assert.match(shortcut, /setPlayerFullscreen\(/);
  assert.match(page, /onToggleSidebar=\{\(\) => toggleSidebar\(\)\}/);
  assert.doesNotMatch(bar, /playbackSidebar\.open|toggleSidebar/, 'the in-bar duplicate of the trigger stays removed');
  assert.match(dock, /aria-label=\{\$t\('playbackSidebar\.open'\)\}/);
});

test('fullscreen collapses to its origin and the lateral panel is not a covered page', () => {
  assert.match(page, /presentation = setFullscreen\(presentation, open, presentablePanel\(selectedPanel\)\)/, 'the Jam tab has no lateral twin and collapses onto the artwork');
  assert.match(page, /covered=\{isFullscreenOpen\|\|spotlightOpen\}/, 'pages are covered by fullscreen and Spotlight, never by the panel');
  assert.match(page, /inert=\{isFullscreenOpen \|\| spotlightOpen\}/);
  assert.doesNotMatch(fullscreen, /presentation|toggleSidebar/, 'FullscreenNowPlaying stays a pure host: origin lives in the presentation state');
});

test('content reserve is applied to the page column only when the panel fits', () => {
  // The left reserve is the real width of the navigation column in each mode (expanded 253, icons 60, hidden 0, floating +12).
  assert.match(page, /navLeftReserve = \$derived\(navPresentation\.sidebar === 'hidden' \? 0 : \(navPresentation\.sidebar === 'icons' \? 60 : 253\) \+ \(\$appearance\.sidebarStyle === 'floating' \? 12 : 0\)\)/);
  assert.match(page, /contentReserve\(\{ windowWidth: viewportWidth, leftReserve: navLeftReserve, presented: sidebarOpen \}\)/);
  assert.match(page, /style:margin-right=\{playbackReserve \? `\$\{playbackReserve\}px` : undefined\}/);
  assert.match(page, /<svelte:window bind:innerWidth=\{viewportWidth\} \/>/);
});

test('sidebar footer reuses the bar actions and offers no AirPlay surface', () => {
  assert.match(bar, /variant\?: 'bar' \| 'sidebar'/);
  assert.match(bar, /name=\{sidebar && playback\.isRepeat \? 'repeat-one' : 'repeat'\}/);
  assert.doesNotMatch(bar + sidebar + dock, /airplay|AirPlay/i, 'AirPlay is a macOS integration; Windows has no equivalent selector yet');
  assert.match(sidebar, /<SidebarArtwork /);
  assert.match(sidebar, /<SidebarRecommendations /);
  assert.match(sidebar, /<SidebarUpcomingQueue /);
  assert.match(sidebar, /<SidebarLyricsPreview /);
});

test('the recommendations sheet paints over the hero metadata and the page scrollbar no longer leaves a strip beside the panel', async () => {
  const artwork = await read('lib/components/playback-sidebar/SidebarArtwork.svelte');
  // FIX-318: metadata is fixed *behind* the rising feed (macOS FIX-282). A z-index on it lifted the title and the
  // like/dislike buttons above the sheet, on top of its rows; the feed is a later sibling, so DOM order must decide.
  const metadataRule = /\n\s*\.metadata \{([^}]*)\}/.exec(artwork)?.[1] ?? '';
  assert.ok(metadataRule, 'the .metadata rule exists');
  assert.doesNotMatch(metadataRule, /z-index/, 'metadata must not out-stack the feed sheet');
  assert.match(artwork, /inert=\{metadataCovered\}/, 'a covered metadata block stops receiving focus and clicks');
  assert.match(artwork, /\.metadata\.covered \{ pointer-events:none; \}/);
  assert.ok(sidebar.indexOf('<SidebarArtwork ') < sidebar.indexOf('<SidebarRecommendations '), 'the feed follows the hero in the DOM');
  // FIX-319: with the reserve active, the content column's classic scrollbar would reintroduce a ~15 px gutter.
  assert.match(page, /class:playback-reserved=\{playbackReserve > 0\}/);
  assert.match(page, /\.content-column\.playback-reserved \{ scrollbar-width: none; \}/);
  assert.match(page, /\.content-column\.playback-reserved::-webkit-scrollbar \{ display: none;/);
});

test('titlebar does not cover the playback sidebar header when top navigation is active', async () => {
  const titlebar = await read('lib/components/shell/TitleBar.svelte');
  const titlebarRule = /\.titlebar\s*\{([^}]*)\}/.exec(titlebar)?.[1] ?? '';
  assert.match(titlebarRule, /pointer-events:\s*none/, 'the 78px titlebar box itself must not swallow clicks below the 32px window controls');
  assert.match(titlebar, /class:topnav-drag=\{!showHistory\}/);
  assert.match(titlebar, /\.drag-region\s*\{\s*height:\s*min\(100%,\s*var\(--playback-top,\s*var\(--titlebar-height,\s*32px\)\)\);\s*align-self:\s*flex-start;/);
  assert.match(titlebar, /\.drag-region\.topnav-drag::before\s*\{\s*content:\s*'';\s*position:\s*absolute;\s*inset:\s*0\s+var\(--topnav-right,\s*154px\)\s+0\s+0;/);
});

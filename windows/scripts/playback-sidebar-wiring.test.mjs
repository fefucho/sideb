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
  assert.match(page, /presentation = setFullscreen\(presentation, open, selectedPanel\)/);
  assert.match(page, /covered=\{isFullscreenOpen\|\|spotlightOpen\}/, 'pages are covered by fullscreen and Spotlight, never by the panel');
  assert.match(page, /inert=\{isFullscreenOpen \|\| spotlightOpen\}/);
  assert.doesNotMatch(fullscreen, /presentation|toggleSidebar/, 'FullscreenNowPlaying stays a pure host: origin lives in the presentation state');
});

test('content reserve is applied to the page column only when the panel fits', () => {
  assert.match(page, /contentReserve\(\{ windowWidth: viewportWidth, leftReserve: sidebarCollapsed \? 60 : 253, presented: sidebarOpen \}\)/);
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

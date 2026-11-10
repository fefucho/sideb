import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// PLAN-023 W5: observable regressions of the playback sidebar recommendations feed.
// The mounted tests need the browser export conditions of Svelte, so the file re-runs itself with them.
if (!process.execArgv.includes('--conditions=browser')) {
  test('sidebar recommendations: deferral, caps, actions, stale responses and account switch (mounted)', () => {
    const { NODE_TEST_CONTEXT, ...env } = process.env;
    const result = spawnSync(process.execPath, ['--conditions=browser', '--test', fileURLToPath(import.meta.url)], { encoding: 'utf8', env });
    assert.equal(result.status, 0, result.stdout + result.stderr);
  });
} else {
  const { mountedSvelteEnvironment } = await import('./helpers/mount-svelte.mjs');
  const { root, dom, moduleFor, mount, unmount, flushSync, tick } = await mountedSvelteEnvironment('sidebar-recommendations');
  const lib = await import(await moduleFor(path.join(root, 'src/lib/player/sidebarRecommendations.ts')));

  const song = (index, videoId = `song-${index}`) => ({
    videoId, setVideoId: `occurrence-${index}`, title: `Song ${index}`, artists: 'Artist', artistRuns: [{ text: 'Artist', id: 'artist' }],
    artistId: 'artist', album: 'Album', albumId: 'album', thumbnail: null, duration: '3:20', isVideo: false,
  });
  const many = (prefix, count) => Array.from({ length: count }, (_, i) => song(i, `${prefix}-${i}`));
  const data = (overrides = {}) => ({
    loadedVideoId: 'seed', requestIdentity: JSON.stringify(['seed', 'artist', 'album']), contextKey: 'ctx-1',
    artistName: 'Artist', artistBrowseId: 'artist', artistSongs: many('a', 5000), albumTitle: 'Album', albumBrowseId: 'album',
    albumSongs: many('b', 5000), similarSongs: many('s', 5000),
    relatedArtists: Array.from({ length: 5000 }, (_, i) => ({ kind: 'artist', id: `artist-${i}`, title: `Artist ${i}`, thumbnail: null, subtitle: null, duration: null })),
    ...overrides,
  });

  test('pure projection defers everything before activation and caps each shelf at ten', () => {
    const idle = lib.projectSidebarRecommendations({ data: data(), activated: false, loading: false, error: null });
    assert.deepEqual(idle.map(row => row.kind), ['hero', 'status']);
    assert.equal(idle[1].state, 'idle');
    const rows = lib.projectSidebarRecommendations({ data: data(), activated: true, loading: false, error: null });
    assert.deepEqual(rows.filter(row => row.kind === 'heading').map(row => row.id), ['heading:artists', 'heading:similar', 'heading:artist', 'heading:album']);
    assert.equal(rows.find(row => row.kind === 'artists').cards.length, 10);
    for (const shelf of ['similar', 'artist', 'album']) assert.equal(rows.filter(row => row.kind === 'track' && row.shelf === shelf).length, 10);
    // Section order of the Mac renderer: fans also like, similar, more by artist, from album.
    assert.deepEqual(rows.map(row => row.kind).filter((kind, i, all) => kind !== all[i - 1]), ['hero', 'refresh', 'heading', 'artists', 'heading', 'track', 'heading', 'track', 'heading', 'track']);
  });

  test('duplicate provider occurrences keep distinct row ids', () => {
    const duplicate = Array.from({ length: 4 }, (_, i) => song(i, 'same'));
    const rows = lib.projectSidebarRecommendations({ data: data({ similarSongs: duplicate, artistSongs: [], albumSongs: [], relatedArtists: [] }), activated: true, loading: false, error: null });
    const ids = rows.filter(row => row.kind === 'track').map(row => row.id);
    assert.equal(new Set(ids).size, 4);
    assert.deepEqual(ids, ['similar-0-same', 'similar-1-same', 'similar-2-same', 'similar-3-same']);
  });

  test('empty, loading and error states; partial failures keep shelves and offer retry', () => {
    const status = input => lib.projectSidebarRecommendations({ activated: true, data: null, ...input }).at(-1);
    assert.equal(status({ loading: true, error: null }).state, 'loading');
    assert.equal(status({ loading: false, error: null }).state, 'empty');
    assert.equal(status({ loading: false, error: 'boom' }).state, 'error');
    assert.equal(status({ data: data({ similarSongs: [], artistSongs: [], albumSongs: [], relatedArtists: [] }) }).state, 'empty');
    const partial = lib.projectSidebarRecommendations({ data: data(), activated: true, loading: false, error: 'partial' });
    assert.equal(partial.at(-1).state, 'error');
    assert.ok(partial.some(row => row.kind === 'track'));
  });

  test('gate: strictly positive threshold, latch per occurrence, reset on new key', () => {
    const gate = new lib.SidebarRecommendationsGate();
    assert.equal(gate.sync('a'), true);
    assert.equal(gate.sync('a'), false);
    assert.equal(gate.update(0, true), false);
    assert.equal(gate.update(23, true), false);
    assert.equal(gate.update(24, false), false, 'no song, no activation');
    assert.equal(gate.update(24, true), true);
    assert.equal(gate.update(0, true), true, 'returning to the hero does not unmount again');
    assert.equal(gate.sync('b'), true);
    assert.equal(gate.activated, false);
    assert.ok(lib.SIDEBAR_RECOMMENDATION_ACTIVATION_OFFSET > 0);
  });

  test('request policy never loops and stale data is rejected by song and account context', () => {
    const base = { activated: true, hasTrack: true, loading: false, hasData: false, error: null };
    assert.equal(lib.shouldRequestSidebarRecommendations(base), true);
    assert.equal(lib.shouldRequestSidebarRecommendations({ ...base, activated: false }), false);
    assert.equal(lib.shouldRequestSidebarRecommendations({ ...base, loading: true }), false);
    assert.equal(lib.shouldRequestSidebarRecommendations({ ...base, hasData: true }), false);
    assert.equal(lib.shouldRequestSidebarRecommendations({ ...base, error: 'x' }), false);
    const track = { videoId: 'seed', artistId: 'artist', albumId: 'album' };
    assert.ok(lib.currentSidebarData(data(), track, new Set()));
    assert.equal(lib.currentSidebarData(data(), { ...track, videoId: 'other' }, new Set()), null);
    assert.equal(lib.currentSidebarData(data(), { ...track, albumId: 'other' }, new Set()), null);
    assert.equal(lib.currentSidebarData(data(), track, new Set(['ctx-1'])), null);
  });

  // ---- mounted component ----
  const observers = new Set();
  Object.defineProperty(globalThis, 'ResizeObserver', { configurable: true, value: class { constructor(cb) { this.cb = cb; this.nodes = new Set(); observers.add(this); } observe(n) { this.nodes.add(n); } unobserve(n) { this.nodes.delete(n); } disconnect() { this.nodes.clear(); observers.delete(this); } } });
  globalThis.IntersectionObserver = class { constructor(cb) { this.cb = cb; } observe(target) { this.cb([{ target, isIntersecting: true }]); } disconnect() {} };
  Object.defineProperty(dom.HTMLElement.prototype, 'clientWidth', { configurable: true, get() { return 340; } });
  Object.defineProperty(dom.HTMLElement.prototype, 'clientHeight', { configurable: true, get() { return 600; } });
  dom.HTMLElement.prototype.getBoundingClientRect = function () { return { x: 0, y: 0, left: 0, top: 0, right: 340, bottom: 54, width: 340, height: 54, toJSON() {} }; };

  const calls = [];
  const trackOf = (videoId, albumId = 'album') => ({ videoId, title: videoId, artists: 'Artist', artistId: 'artist', albumId });
  globalThis.__sidebarProps = {
    session: 1, heroHeight: 600, loggedIn: true, likedIds: new Set(['s-1']), pendingIds: new Set(),
    playback: { currentTrack: trackOf('seed'), isPlaying: true },
    snapshot: { loading: false, error: null, data: null },
    onRequestLoad: () => calls.push(['load']), onRefresh: () => calls.push(['refresh']), onSuspend: () => calls.push(['suspend']),
    onScrollOffset: offset => calls.push(['offset', offset]),
    onPlaySong: s => calls.push(['play', s.videoId]), onTogglePlayback: () => calls.push(['toggle']),
    onAddToQueue: s => calls.push(['queue', s.videoId]), onToggleLike: s => calls.push(['like', s.videoId]), onDislike: s => calls.push(['dislike', s.videoId]),
    onOpenArtist: id => calls.push(['artist', id]), onOpenAlbum: id => calls.push(['album', id]),
  };
  const harness = `<script>import {setContext} from 'svelte';import Feed from './SidebarRecommendations.svelte';import {MEDIA_CONTEXT} from '$lib/player/media';import {MENU_CONTEXT} from '$lib/menu/types';let props=$state(globalThis.__sidebarProps);globalThis.__setSidebarProps=next=>Object.assign(props,next);setContext(MEDIA_CONTEXT,{state:()=>props.playback,pending:()=>null,toggle:()=>{},activate:()=>{},rowActive:()=>false});setContext(MENU_CONTEXT,{open:()=>{}});</script><div class="area"><Feed {...props}/></div>`;
  const Harness = (await import(await moduleFor(path.join(root, 'src/lib/components/playback-sidebar/SidebarRecommendationsHarness.svelte'), harness))).default;
  const settle = async () => { flushSync(); await tick(); await new Promise(resolve => setTimeout(resolve, 35)); flushSync(); await tick(); };
  const scrollTo = async (scroller, top) => { scroller.scrollTop = top; scroller.dispatchEvent(new Event('scroll')); await settle(); };
  const set = async next => { globalThis.__setSidebarProps(next); await settle(); };

  test('mounted: nothing is built or requested before the first scroll; activation loads once and mounts a bounded window', async () => {
    const host = document.createElement('div'); document.body.append(host);
    let app; flushSync(() => app = mount(Harness, { target: host })); await settle();
    const feed = host.querySelector('[data-sidebar-recommendations]'), scroller = host.querySelector('.scroller');
    assert.equal(feed.dataset.activated, 'false');
    assert.equal(host.querySelector('[data-sidebar-track]'), null);
    assert.equal(host.querySelector('[data-sidebar-artist-shelf]'), null);
    assert.equal(calls.filter(call => call[0] === 'load').length, 0, 'opening must not request recommendations');
    await scrollTo(scroller, 10);
    assert.equal(feed.dataset.activated, 'false', 'below the positive threshold nothing activates');
    assert.equal(calls.filter(call => call[0] === 'load').length, 0);
    await scrollTo(scroller, 30);
    assert.equal(feed.dataset.activated, 'true');
    assert.equal(calls.filter(call => call[0] === 'load').length, 1);
    assert.ok(calls.some(call => call[0] === 'offset' && call[1] === 30));
    // The controller answers: shelves appear (max 10 each), the DOM stays bounded.
    await set({ snapshot: { loading: false, error: null, data: data() } });
    await scrollTo(scroller, 600);
    assert.ok(host.querySelector('[data-sidebar-artist-shelf]'), 'artist shelf mounts only after activation');
    assert.ok(host.querySelectorAll('[data-sidebar-artist]').length <= 7);
    assert.equal(calls.filter(call => call[0] === 'load').length, 1, 'no repeated request while data is present');
    await scrollTo(scroller, 1400);
    const mountedTracks = host.querySelectorAll('[data-sidebar-track]').length;
    assert.ok(mountedTracks > 0 && mountedTracks <= Math.ceil((600 + 2 * 240) / 54) + 2, `bounded window (viewport + overscan), got ${mountedTracks}`);
    const total = Number(host.querySelector('.content').style.height.replace('px', ''));
    assert.equal(total, 600 + 44 + 40 + 140 + 3 * (40 + 10 * 54), 'cap of ten per shelf even with 5000 songs');
    await unmount(app); host.remove();
    assert.equal(calls.at(-1)[0], 'suspend');
    assert.equal(observers.size, 0, 'observers released');
  });

  test('mounted: row click, current toggle, ordered actions and queue add use the callbacks without touching playback', async () => {
    calls.length = 0;
    await set({ session: 1, snapshot: { loading: false, error: null, data: null }, playback: { currentTrack: trackOf('seed'), isPlaying: true } });
    const host = document.createElement('div'); document.body.append(host);
    let app; flushSync(() => app = mount(Harness, { target: host })); await settle();
    const scroller = host.querySelector('.scroller');
    await scrollTo(scroller, 30);
    await set({ snapshot: { loading: false, error: null, data: data({ similarSongs: [song(0, 'seed'), ...many('s', 3)], relatedArtists: [{ kind: 'artist', id: 'artist-x', title: 'Ex', thumbnail: null, subtitle: null, duration: null }] }) } });
    await scrollTo(scroller, 700);
    const row = host.querySelector('[data-sidebar-track="1"]');
    assert.ok(row);
    // dislike, like, + in that order, all inside the row.
    assert.deepEqual([...row.querySelectorAll('[data-sidebar-action]')].map(button => button.dataset.sidebarAction), ['dislike', 'like', 'add']);
    row.querySelector('.primary').click();
    assert.deepEqual(calls.at(-1), ['play', 's-0']);
    row.querySelector('[data-sidebar-action="add"]').click();
    assert.deepEqual(calls.at(-1), ['queue', 's-0']);
    assert.equal(calls.filter(call => call[0] === 'play').length, 1, '+ must not also activate the row');
    row.querySelector('[data-sidebar-action="like"]').click();
    assert.deepEqual(calls.at(-1), ['like', 's-0']);
    row.querySelector('[data-sidebar-action="dislike"]').click();
    assert.deepEqual(calls.at(-1), ['dislike', 's-0']);
    const current = host.querySelector('[data-sidebar-track="0"]');
    current.querySelector('.primary').click();
    assert.deepEqual(calls.at(-1), ['toggle'], 'clicking the current song toggles playback');
    assert.ok(host.querySelector('[data-sidebar-track="2"] .like.liked'), 'liked ids render a persistent heart');
    assert.equal(host.querySelector('[data-sidebar-track="1"] .like.liked'), null);
    // Header actions and the artist card.
    await scrollTo(scroller, 640);
    const guest = host.querySelector('[data-sidebar-artist="artist-x"] .primary');
    assert.ok(guest); guest.click(); assert.deepEqual(calls.at(-1), ['artist', 'artist-x']);
    await unmount(app); host.remove();
  });

  test('mounted: account switch and song change discard stale responses and return to the hero', async () => {
    calls.length = 0;
    await set({ session: 1, snapshot: { loading: false, error: null, data: null }, playback: { currentTrack: trackOf('seed'), isPlaying: false } });
    const host = document.createElement('div'); document.body.append(host);
    let app; flushSync(() => app = mount(Harness, { target: host })); await settle();
    const scroller = host.querySelector('.scroller'), feed = host.querySelector('[data-sidebar-recommendations]');
    await scrollTo(scroller, 30);
    await set({ snapshot: { loading: false, error: null, data: data() } });
    await scrollTo(scroller, 700);
    assert.ok(host.querySelector('[data-sidebar-track]'));
    const loads = calls.filter(call => call[0] === 'load').length;
    // Account changes while the snapshot still holds the previous account's response.
    await set({ session: 2 });
    assert.equal(scroller.scrollTop, 0);
    assert.equal(feed.dataset.activated, 'false');
    assert.equal(host.querySelector('[data-sidebar-track]'), null, 'previous account data must not render');
    assert.equal(calls.filter(call => call[0] === 'load').length, loads, 'switching account alone does not request until the user scrolls again');
    await scrollTo(scroller, 30);
    assert.equal(host.querySelector('[data-sidebar-track]'), null, 'the stale response stays rejected after activation');
    assert.equal(calls.filter(call => call[0] === 'load').length, loads + 1, 'the new context asks the controller for fresh data');
    await set({ snapshot: { loading: false, error: null, data: data({ contextKey: 'ctx-2' }) } });
    await scrollTo(scroller, 700);
    assert.ok(host.querySelector('[data-sidebar-track]'), 'fresh response of the new account renders');
    // Song changes: old shelves vanish and the feed is back at the hero until scrolled again.
    await set({ playback: { currentTrack: trackOf('other'), isPlaying: false } });
    assert.equal(scroller.scrollTop, 0);
    assert.equal(host.querySelector('[data-sidebar-track]'), null, 'responses of the previous song never render');
    assert.equal(feed.dataset.activated, 'false');
    await unmount(app); host.remove();
  });

  test('mounted: errors keep a retry, loading and empty states are announced, wheel over the hero scrolls the feed', async () => {
    calls.length = 0;
    await set({ session: 3, snapshot: { loading: false, error: null, data: null }, playback: { currentTrack: trackOf('seed'), isPlaying: false } });
    const host = document.createElement('div'); document.body.append(host);
    let app; flushSync(() => app = mount(Harness, { target: host })); await settle();
    const scroller = host.querySelector('.scroller');
    // Wheel that starts over the hero (outside any row) is forwarded and activates the feed.
    const area = host.querySelector('.area');
    area.dispatchEvent(new dom.WheelEvent('wheel', { deltaY: 80, deltaMode: 0, bubbles: true }));
    await settle();
    assert.equal(scroller.scrollTop, 80);
    assert.equal(host.querySelector('[data-sidebar-recommendations]').dataset.activated, 'true');
    await set({ snapshot: { loading: true, error: null, data: null } });
    await scrollTo(scroller, 700);
    assert.equal(host.querySelector('[data-sidebar-status]').dataset.sidebarStatus, 'loading');
    assert.equal(host.querySelector('[data-sidebar-status] button'), null, 'no retry while loading');
    await set({ snapshot: { loading: false, error: 'No se pudieron cargar todas las recomendaciones. Podés reintentar.', data: null } });
    await scrollTo(scroller, 700);
    const failed = host.querySelector('[data-sidebar-status]');
    assert.equal(failed.dataset.sidebarStatus, 'error');
    const before = calls.filter(call => call[0] === 'load').length;
    failed.querySelector('button').click();
    assert.deepEqual(calls.at(-1), ['refresh']);
    assert.equal(calls.filter(call => call[0] === 'load').length, before, 'an error is retried explicitly, never automatically');
    await set({ snapshot: { loading: false, error: null, data: data({ similarSongs: [], artistSongs: [], albumSongs: [], relatedArtists: [] }) } });
    await scrollTo(scroller, 700);
    assert.equal(host.querySelector('[data-sidebar-status]').dataset.sidebarStatus, 'empty');
    await unmount(app); host.remove();
  });
}

import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if (!process.execArgv.includes('--conditions=browser')) {
  test('hidden sidebar collapse mode: presentation table, persistence and top navigation components', () => {
    const {NODE_TEST_CONTEXT, ...env} = process.env;
    const run = spawnSync(process.execPath, ['--conditions=browser', '--test', fileURLToPath(import.meta.url)], {encoding: 'utf8', env});
    assert.equal(run.status, 0, run.stdout + run.stderr);
    assert.match(run.stdout, /anchored search/);
  });
} else {
  const {mountedSvelteEnvironment} = await import('./helpers/mount-svelte.mjs');
  const {root, dom, moduleFor, mount, unmount, flushSync, tick} = await mountedSvelteEnvironment('top-navigation-dom');
  const {get} = await import('svelte/store');
  const {deriveNavigationPresentation} = await import(await moduleFor(path.join(root, 'src/lib/navigation/presentation.ts')));
  const {createAppearancePreferences, appearanceKey, decodeAppearance} = await import(await moduleFor(path.join(root, 'src/lib/appearance/preferences.ts')));
  const {setLanguage} = await import(await moduleFor(path.join(root, 'src/lib/i18n/index.ts')));
  setLanguage('en');
  const {default: TopNavigation} = await import(await moduleFor(path.join(root, 'src/lib/components/shell/TopNavigation.svelte')));
  const {default: Sidebar} = await import(await moduleFor(path.join(root, 'src/lib/components/sidebar/Sidebar.svelte')));
  const {default: SpotlightSearch} = await import(await moduleFor(path.join(root, 'src/lib/components/search/SpotlightSearch.svelte')));
  const {default: HomeSettings} = await import(await moduleFor(path.join(root, 'src/lib/components/home/HomeSettings.svelte')));
  const {appearance} = await import(await moduleFor(path.join(root, 'src/lib/appearance/preferences.ts')));
  const {defaults} = await import(await moduleFor(path.join(root, 'src/lib/home/settings.ts')));
  document.hasFocus = () => false;
  const settle = async () => { await tick(); flushSync(); await tick(); };
  const click = async node => { assert.ok(node); node.click(); await settle(); };
  const host = () => { const node = document.createElement('div'); document.body.append(node); return node; };
  const ready = {state: 'ready', name: 'Demo', handle: '@demo', email: 'demo@example.test', thumbnail: null, message: null};
  const guest = {state: 'guest', name: null, handle: null, email: null, thumbnail: null, message: null};
  const memoryStorage = () => { const values = new Map(); return {values, getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, value)}; };

  test('presentation derives one effective state from preference, collapsed and fullscreen', () => {
    const expected = (sidebar, showTopNav, showReopen, titlebarHeight) => ({sidebar, showTopNav, showReopen, titlebarHeight});
    for (const collapseMode of ['icons', 'hidden']) for (const fullscreen of [false, true]) {
      assert.deepEqual(deriveNavigationPresentation({collapseMode, collapsed: false, fullscreen}), expected('expanded', false, false, 32), `${collapseMode} open fullscreen=${fullscreen}`);
    }
    for (const fullscreen of [false, true]) assert.deepEqual(deriveNavigationPresentation({collapseMode: 'icons', collapsed: true, fullscreen}), expected('icons', false, false, 32));
    assert.deepEqual(deriveNavigationPresentation({collapseMode: 'hidden', collapsed: true, fullscreen: false}), expected('hidden', true, true, 78));
    // Player fullscreen hides destinations/search but keeps the reopen control and the native 32 px strip.
    assert.deepEqual(deriveNavigationPresentation({collapseMode: 'hidden', collapsed: true, fullscreen: true}), expected('hidden', false, true, 32));
  });

  test('collapse mode and collapsed state persist with defaults, tolerate invalid values and keep other fields', () => {
    const storage = memoryStorage();
    let store = createAppearancePreferences(storage);
    assert.equal(get(store).sidebarCollapseMode, 'icons');
    assert.equal(get(store).sidebarCollapsed, false);
    store.setHomeBackground('solid'); store.toggleSidebarLayout(); store.setSidebarStyle('floating');
    store.setSidebarCollapseMode('hidden'); store.setSidebarCollapsed(true);
    store = createAppearancePreferences(storage);
    assert.deepEqual(get(store), {version: 1, homeBackground: 'solid', sidebarLayout: 'grid', animatedArtwork: true, albumCardStyle: 'tinted', sidebarStyle: 'floating', sidebarCollapseMode: 'hidden', sidebarCollapsed: true});
    store.toggleSidebarCollapsed(); assert.equal(get(createAppearancePreferences(storage)).sidebarCollapsed, false);
    store.setSidebarCollapseMode('icons'); assert.equal(get(createAppearancePreferences(storage)).sidebarCollapseMode, 'icons');
    for (const bad of ['Hidden', 'none', null, 7, {}]) {
      assert.equal(decodeAppearance({version: 1, sidebarCollapseMode: bad}).sidebarCollapseMode, 'icons');
    }
    for (const bad of ['true', 1, null, undefined, 'yes']) assert.equal(decodeAppearance({version: 1, sidebarCollapsed: bad}).sidebarCollapsed, false);
    // JSON written before these fields existed keeps its other values and gains the defaults.
    storage.values.set(appearanceKey, JSON.stringify({version: 1, homeBackground: 'solid', sidebarLayout: 'grid', animatedArtwork: false, albumCardStyle: 'white', sidebarStyle: 'floating'}));
    assert.deepEqual(get(createAppearancePreferences(storage)), {version: 1, homeBackground: 'solid', sidebarLayout: 'grid', animatedArtwork: false, albumCardStyle: 'white', sidebarStyle: 'floating', sidebarCollapseMode: 'icons', sidebarCollapsed: false});
    storage.values.set(appearanceKey, 'not json');
    assert.deepEqual(get(createAppearancePreferences(storage)), decodeAppearance(null));
    // Blocked storage still works in memory.
    const blocked = createAppearancePreferences({getItem() { throw Error('blocked'); }, setItem() { throw Error('blocked'); }});
    blocked.setSidebarCollapseMode('hidden'); blocked.setSidebarCollapsed(true);
    assert.equal(get(blocked).sidebarCollapseMode, 'hidden'); assert.equal(get(blocked).sidebarCollapsed, true);
  });

  function navProps(calls, extra = {}) {
    return {activeDestination: 'home', auth: ready, canBack: true, canForward: false,
      onReopen: () => calls.push('reopen'), onHome: () => calls.push('home'), onExplore: () => calls.push('explore'), onLibrary: () => calls.push('library'), onSearch: () => calls.push('search'),
      onBack: () => calls.push('back'), onForward: () => calls.push('forward'), onLogin: () => calls.push('login'), onCancelLogin: () => calls.push('cancel'), onLogout: () => calls.push('logout'),
      onCheckUpdates: () => calls.push('updates'), onLikes: () => calls.push('likes'), onHistory: () => calls.push('history'), onCreatePlaylist: () => calls.push('create'), ...extra};
  }

  test('top navigation calls the same handlers, marks the destination and enables history by props', async () => {
    setLanguage('en');
    const calls = [], node = host(); let app;
    flushSync(() => app = mount(TopNavigation, {target: node, props: navProps(calls)})); await settle();
    try {
      const destinations = [...node.querySelectorAll('.destinations button')];
      // Search at the start, destinations in the middle column, account and then history at the far end.
      const names = ['reopen', 'search', 'destinations', 'account', 'history'];
      assert.deepEqual([...node.querySelectorAll(names.map(name => '.' + name).join())].map(element => names.find(name => element.classList.contains(name))), names);
      assert.deepEqual([...node.querySelector('.topnav').children].map(element => element.className.replace(/\s*s-\S+|\s*svelte-\S+/g, '').trim().split(' ').filter(part => ['side', 'start', 'end', 'destinations'].includes(part)).join(' ')), ['side start', 'destinations', 'side end']);
      assert.ok(node.querySelector('.side.start .search') && node.querySelector('.side.end .account + .history'));
      assert.deepEqual(destinations.map(b => b.getAttribute('aria-label')), ['Home', 'Explore', 'Library']);
      assert.deepEqual(destinations.map(b => b.getAttribute('aria-current')), ['page', null, null]);
      for (const button of destinations) await click(button);
      await click(node.querySelector('[data-topnav-search]'));
      await click(node.querySelector('[data-topnav-reopen]'));
      const [back, forward] = node.querySelectorAll('.history button');
      assert.equal(back.disabled, false); assert.equal(forward.disabled, true);
      await click(back); await click(forward);
      assert.deepEqual(calls, ['home', 'explore', 'library', 'search', 'reopen', 'back']);
    } finally { await unmount(app); node.remove(); }
    // Selection only for the three destinations; album/artist/etc. select nothing.
    for (const [activeDestination, expectedIndex] of [['explore', 1], ['library', 2], ['album', -1], ['search', -1], ['likes', -1]]) {
      const target = host(); let instance; flushSync(() => instance = mount(TopNavigation, {target, props: navProps([], {activeDestination})})); await settle();
      assert.equal([...target.querySelectorAll('.destinations button')].findIndex(b => b.getAttribute('aria-current') === 'page'), expectedIndex, activeDestination);
      await unmount(instance); target.remove();
    }
    const target = host(); let instance; flushSync(() => instance = mount(TopNavigation, {target, props: navProps([], {canBack: false, canForward: true})})); await settle();
    assert.deepEqual([...target.querySelectorAll('.history button')].map(b => b.disabled), [true, false]);
    await unmount(instance); target.remove();
  });

  test('open search takes destinations out of focus; fullscreen compact keeps only the reopen control', async () => {
    const calls = [], node = host(); let app;
    flushSync(() => app = mount(TopNavigation, {target: node, props: navProps(calls, {searchOpen: true})})); await settle();
    try {
      assert.equal(node.querySelector('.destinations').hasAttribute('inert'), true);
      assert.equal(node.querySelector('.destinations').classList.contains('away'), true);
      assert.equal(node.querySelector('[data-topnav-search]').hasAttribute('inert'), true);
      assert.equal(node.querySelector('.history').hasAttribute('inert'), false, 'history keeps its position and stays usable');
    } finally { await unmount(app); node.remove(); }
    const compact = host(); let instance; flushSync(() => instance = mount(TopNavigation, {target: compact, props: navProps(calls, {compact: true})})); await settle();
    try {
      assert.deepEqual([...compact.querySelectorAll('button')].map(b => b.getAttribute('aria-label')), ['Expand sidebar']);
      assert.equal(compact.querySelector('.destinations'), null); assert.equal(compact.querySelector('.history'), null); assert.equal(compact.querySelector('.account'), null);
      await click(compact.querySelector('[data-topnav-reopen]')); assert.deepEqual(calls, ['reopen']);
    } finally { await unmount(instance); compact.remove(); }
  });

  test('account menu reaches account actions, likes, history and new playlist and restores focus', async () => {
    const calls = [], node = host(); let app;
    flushSync(() => app = mount(TopNavigation, {target: node, props: navProps(calls)})); await settle();
    try {
      const button = node.querySelector('.account');
      await click(button); assert.equal(button.getAttribute('aria-expanded'), 'true');
      const menu = node.querySelector('[role="dialog"]'); assert.ok(menu);
      assert.equal(menu.querySelectorAll('button').length, 5);
      dom.dispatchEvent(new dom.KeyboardEvent('keydown', {key: 'Escape', bubbles: true, cancelable: true})); await settle(); await tick();
      assert.equal(node.querySelector('[role="dialog"]'), null); assert.equal(document.activeElement, button);
      for (const index of [0, 1, 2, 3, 4]) { await click(button); await click(node.querySelectorAll('[role="dialog"] button')[index]); assert.equal(node.querySelector('[role="dialog"]'), null); }
      assert.deepEqual(calls, ['likes', 'history', 'create', 'updates', 'logout']);
      // Outside click closes without acting.
      await click(button); document.body.dispatchEvent(new dom.MouseEvent('click', {bubbles: true})); await settle(); assert.equal(node.querySelector('[role="dialog"]'), null);
    } finally { await unmount(app); node.remove(); }
  });

  test('guest account menu offers login or cancel, updates and shortcuts without sign out', async () => {
    for (const [auth, expected] of [[guest, 'login'], [{...guest, state: 'authorizing'}, 'cancel']]) {
      const calls = [], node = host(); let app;
      flushSync(() => app = mount(TopNavigation, {target: node, props: navProps(calls, {auth})})); await settle();
      try {
        await click(node.querySelector('.account'));
        const labels = [...node.querySelectorAll('[role="dialog"] button')].map(b => b.textContent.trim());
        assert.ok(!labels.includes('Sign out'));
        assert.equal(node.querySelectorAll('[role="dialog"] button')[2].disabled, true, 'create playlist needs a signed in account');
        await click(node.querySelectorAll('[role="dialog"] button')[labels.length - 1]);
        assert.deepEqual(calls, [expected]);
      } finally { await unmount(app); node.remove(); }
    }
  });

  test('a hidden sidebar closes its account popover; the visible one keeps Escape and focus behaviour', async () => {
    const calls = [], node = host();
    const props = () => ({activeDestination: 'home', auth: ready, collapsed: false, hidden: false, onHome() {}, onSearch() {}, onToggleSidebar() {}, onLogin() {}, onCancelLogin() {}, onLogout: () => calls.push('logout'), onCheckUpdates: () => calls.push('updates'), playlists: [], albums: []});
    let app; flushSync(() => app = mount(Sidebar, {target: node, props: props()})); await settle();
    try {
      await click(node.querySelector('.profile')); assert.ok(node.querySelector('[role="dialog"]'));
      assert.equal(node.querySelectorAll('[role="dialog"] button').length, 2);
      dom.dispatchEvent(new dom.KeyboardEvent('keydown', {key: 'Escape', bubbles: true, cancelable: true})); await settle(); await tick();
      assert.equal(node.querySelector('[role="dialog"]'), null); assert.equal(document.activeElement, node.querySelector('.profile'));
      await click(node.querySelector('.profile')); await click(node.querySelector('[role="dialog"] .signout')); assert.deepEqual(calls, ['logout']);
    } finally { await unmount(app); node.remove(); }
    const state = {hidden: false}; const target = host(); let instance;
    const Wrapper = (await import(await moduleFor(path.join(root, 'src/lib/components/shell/SidebarHiddenHarness.svelte'), `<script>
      import Sidebar from '$lib/components/sidebar/Sidebar.svelte';
      let {hidden=$bindable(false)} = $props();
      globalThis.__setHidden = value => hidden = value;
    </script><Sidebar activeDestination="home" auth={{state:'ready',name:'Demo',handle:null,email:null,thumbnail:null,message:null}} {hidden} onHome={()=>{}} onSearch={()=>{}} onToggleSidebar={()=>{}} onLogin={()=>{}} onCancelLogin={()=>{}} onLogout={()=>{}} />`))).default;
    flushSync(() => instance = mount(Wrapper, {target, props: state})); await settle();
    try {
      await click(target.querySelector('.profile')); assert.ok(target.querySelector('[role="dialog"]'));
      globalThis.__setHidden(true); await settle(); assert.equal(target.querySelector('[role="dialog"]'), null);
    } finally { await unmount(instance); target.remove(); }
  });

  const preview = (query, extra = {}) => ({query, associatedQuery: query, results: null, entries: [], isLoading: false, error: null, ...extra});
  function spotlightProps(calls, extra = {}) {
    return {preview: preview('daft'), backendReady: true, onQueryChange: q => calls.push('query:' + q), onCommit: q => calls.push('commit:' + q), onDismiss: () => calls.push('dismiss'), onSelectCard: () => calls.push('card'), onPlaySong: () => calls.push('song'), ...extra};
  }

  test('anchored search renders a capsule and results panel without scrim, and keeps Escape/outside-click/Enter rules', async () => {
    const calls = [], node = host(); let app;
    flushSync(() => app = mount(SpotlightSearch, {target: node, props: spotlightProps(calls, {anchored: true})})); await settle(); await tick();
    try {
      assert.ok(node.querySelector('.anchored .capsule input')); assert.equal(node.querySelector('.scrim'), null); assert.equal(node.querySelector('.spotlight'), null);
      assert.equal(document.activeElement, node.querySelector('input'));
      assert.ok(node.querySelector('.panel .commit'), 'results panel hangs under the capsule with the commit action');
      node.querySelector('form').dispatchEvent(new dom.Event('submit', {bubbles: true, cancelable: true})); await settle();
      assert.deepEqual(calls, ['dismiss', 'commit:daft']);
    } finally { await unmount(app); node.remove(); }
    for (const dismissal of ['escape', 'outside']) {
      const dismissed = [], target = host(); let instance;
      flushSync(() => instance = mount(SpotlightSearch, {target, props: spotlightProps(dismissed, {anchored: true})})); await settle(); await tick();
      try {
        if (dismissal === 'escape') dom.dispatchEvent(new dom.KeyboardEvent('keydown', {key: 'Escape', bubbles: true, cancelable: true}));
        else {
          target.querySelector('.panel').dispatchEvent(new dom.Event('pointerdown', {bubbles: true})); await settle(); assert.deepEqual(dismissed, [], 'inside click keeps it open');
          document.body.dispatchEvent(new dom.Event('pointerdown', {bubbles: true}));
        }
        await settle(); assert.deepEqual(dismissed, ['dismiss'], dismissal);
      } finally { await unmount(instance); target.remove(); }
    }
    const empty = host(); let instance; flushSync(() => instance = mount(SpotlightSearch, {target: empty, props: spotlightProps([], {anchored: true, preview: preview('')})})); await settle();
    assert.equal(empty.querySelector('.panel'), null, 'no empty panel before there is something to show'); await unmount(instance); empty.remove();
  });

  test('centered Spotlight stays exactly as before when not anchored', async () => {
    const calls = [], node = host(); let app;
    flushSync(() => app = mount(SpotlightSearch, {target: node, props: spotlightProps(calls)})); await settle();
    try {
      assert.ok(node.querySelector('.scrim')); assert.ok(node.querySelector('.spotlight[role="dialog"][aria-modal="true"]')); assert.equal(node.querySelector('.capsule'), null);
      node.querySelector('.scrim').click(); await settle(); assert.deepEqual(calls, ['dismiss']);
    } finally { await unmount(app); node.remove(); }
  });

  test('collapse mode picker in Settings reflects and updates the preference without touching collapsed state', async () => {
    appearance.setSidebarCollapseMode('icons'); appearance.setSidebarCollapsed(true);
    const node = host(); let changed = 0, app;
    flushSync(() => app = mount(HomeSettings, {target: node, props: {settings: defaults(), kind: 'albums', categories: [], libraryError: null, onChange: () => changed++, onKind: () => changed++, onRetryLibrary: () => changed++, onClose() {}}})); await settle();
    try {
      await click(node.querySelector('button.item[data-category="appearance"]'));
      const picker = node.querySelector('#sidebar-collapse-picker');
      assert.ok(picker); assert.equal(picker.value, 'icons'); assert.ok(picker.getAttribute('aria-describedby')); assert.ok(node.querySelector('#' + picker.getAttribute('aria-describedby')));
      const rowTitle = () => node.querySelector('#' + picker.getAttribute('aria-labelledby')).textContent.trim();
      assert.equal(rowTitle(), 'When collapsing the sidebar');
      assert.deepEqual([...picker.querySelectorAll('option')].map(o => o.value), ['icons', 'hidden']);
      picker.value = 'hidden'; picker.dispatchEvent(new dom.Event('change', {bubbles: true})); await settle();
      assert.equal(get(appearance).sidebarCollapseMode, 'hidden'); assert.equal(get(appearance).sidebarCollapsed, true); assert.equal(changed, 0);
      assert.equal(deriveNavigationPresentation({collapseMode: get(appearance).sidebarCollapseMode, collapsed: get(appearance).sidebarCollapsed, fullscreen: false}).showTopNav, true, 'applies immediately while collapsed');
      setLanguage('es'); await settle(); assert.equal(rowTitle(), 'Al contraer la barra lateral');
      assert.deepEqual([...picker.querySelectorAll('option')].map(o => o.textContent.trim()), ['Mostrar sólo iconos', 'Ocultar completamente']);
    } finally { setLanguage('en'); await unmount(app); node.remove(); appearance.setSidebarCollapseMode('icons'); appearance.setSidebarCollapsed(false); }
  });
}

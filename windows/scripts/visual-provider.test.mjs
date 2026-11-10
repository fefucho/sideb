import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { test } from 'node:test';
import { pathToFileURL } from 'node:url';
import vm from 'node:vm';
import ts from 'typescript';

const require = createRequire(import.meta.url);
const svelteStore = JSON.stringify(pathToFileURL(require.resolve('svelte/store')).href);
const dataUrl = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const transpile = async relative => ts.transpileModule(await readFile(new URL(relative, import.meta.url), 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const apiStub = dataUrl('export const visualProviderApi = {};');
const routing = await import(dataUrl(await transpile('../src/lib/visualProvider/routing.ts')));
const controllerCode = (await transpile('../src/lib/visualProvider/settingsController.ts')).replace(/'svelte\/store'/, svelteStore).replace(/'\.\/api'/, JSON.stringify(apiStub));
const { createVisualProviderSettings, settingsStatusKey } = await import(dataUrl(controllerCode));
const storeCode = (await transpile('../src/lib/visualProvider/store.ts')).replace(/'svelte\/store'/, svelteStore).replace(/'\.\/api'/, JSON.stringify(apiStub));
const { createVisualProviderStore } = await import(dataUrl(storeCode));

// ---- Routing: Apple first; the provider only in the enabled vertical player ----

const asset = name => ({ name });
const route = (overrides = {}) => {
  const calls = [];
  return {
    calls,
    options: {
      verticalPlayer: true, extensionEnabled: true,
      primary: async () => { calls.push('primary'); return null; },
      secondary: async () => { calls.push('secondary'); return asset('spotify'); },
      ...overrides,
    },
  };
};

test('a usable Apple asset never consults the provider', async () => {
  const { calls, options } = route({ primary: async () => asset('apple') });
  assert.deepEqual(await routing.resolveVisualArtwork(options), asset('apple'));
  assert.deepEqual(calls, []);
});

test('the provider is a fallback only for the enabled vertical player', async () => {
  const fallback = route();
  assert.deepEqual(await routing.resolveVisualArtwork(fallback.options), asset('spotify'));
  assert.deepEqual(fallback.calls, ['primary', 'secondary']);
  for (const overrides of [{ verticalPlayer: false }, { extensionEnabled: false }, { verticalPlayer: false, extensionEnabled: false }]) {
    const blocked = route(overrides);
    assert.equal(await routing.resolveVisualArtwork(blocked.options), null, JSON.stringify(overrides));
    assert.deepEqual(blocked.calls, ['primary'], 'fullscreen / disabled never reaches the provider');
  }
});

test('an Apple error falls back only when allowed and is otherwise surfaced', async () => {
  const boom = new Error('apple failed');
  const allowed = route({ primary: async () => { throw boom; } });
  assert.deepEqual(await routing.resolveVisualArtwork(allowed.options), asset('spotify'));
  const denied = route({ verticalPlayer: false, primary: async () => { throw boom; } });
  await assert.rejects(routing.resolveVisualArtwork(denied.options), boom);
  assert.deepEqual(denied.calls, []);
});

test('cancellation stops the chain without falling back', async () => {
  const controller = new AbortController();
  const aborted = route({ signal: controller.signal, primary: async () => { controller.abort(); return null; } });
  await assert.rejects(routing.resolveVisualArtwork(aborted.options), routing.isAbortError);
  assert.deepEqual(aborted.calls, []);
  const during = new AbortController();
  const failing = route({ signal: during.signal, primary: async () => { during.abort(); throw new Error('late'); } });
  await assert.rejects(routing.resolveVisualArtwork(failing.options), routing.isAbortError);
  const abortThrown = route({ primary: async () => { throw new DOMException('x', 'AbortError'); } });
  await assert.rejects(routing.resolveVisualArtwork(abortThrown.options), routing.isAbortError);
  assert.deepEqual(abortThrown.calls, [], 'an abort from Apple is not an Apple miss');
});

// ---- Settings controller ----

const baseState = overrides => ({ installed: true, bundledAvailable: true, provider: { id: 'p', name: 'Spotify Canvas', version: '0.1.5', webLogin: true },
  enabled: false, hasCredential: false, authBlocked: false, revision: 1, statusKey: 'visualProvider.status.tokenRequired', identitySalt: null, ...overrides });

function fakeApi(overrides = {}) {
  const listeners = { changed: new Set(), login: new Set() };
  const log = [];
  let current = baseState({});
  const api = {
    log, listeners,
    set(next) { current = next; },
    state: async () => current,
    setEnabled: async enabled => { log.push(['setEnabled', enabled]); current = { ...current, enabled, revision: current.revision + 1 }; return current; },
    installBundled: async () => { log.push(['installBundled']); current = baseState({ revision: current.revision + 1 }); return current; },
    installFromFolder: async path => { log.push(['installFromFolder', path]); return current; },
    uninstall: async () => { log.push(['uninstall']); current = baseState({ installed: false, provider: null, revision: current.revision + 1 }); return current; },
    saveToken: async token => { log.push(['saveToken', token]); current = { ...current, hasCredential: true, revision: current.revision + 1 }; return current; },
    openLogin: async title => { log.push(['openLogin', title]); return true; },
    cancelLogin: async () => { log.push(['cancelLogin']); },
    onChanged: async listener => { listeners.changed.add(listener); return () => listeners.changed.delete(listener); },
    onLogin: async listener => { listeners.login.add(listener); return () => listeners.login.delete(listener); },
    ...overrides,
  };
  return api;
}
const flush = () => new Promise(resolve => setTimeout(resolve, 0));
const read = store => { let value; store.subscribe(next => { value = next; })(); return value; };

test('the tokenRequired status uses the Windows wording instead of the Keychain one', () => {
  assert.equal(settingsStatusKey('visualProvider.status.tokenRequired'), 'windows.visualProvider.status.tokenRequired');
  assert.equal(settingsStatusKey('visualProvider.status.ready'), 'visualProvider.status.ready');
});

test('settings load the host state, follow its events and stop listening', async () => {
  const api = fakeApi();
  const settings = createVisualProviderSettings(api, () => undefined);
  const stop = settings.start();
  await flush();
  assert.equal(read(settings).state.provider.name, 'Spotify Canvas');
  api.listeners.changed.forEach(listener => listener(baseState({ revision: 5, enabled: true, hasCredential: true })));
  assert.equal(read(settings).state.enabled, true);
  api.listeners.changed.forEach(listener => listener(baseState({ revision: 2 })));
  assert.equal(read(settings).state.revision, 5, 'a stale event never rolls the section back');
  stop();
  assert.equal(api.listeners.changed.size + api.listeners.login.size, 0);
});

test('operations disable the controls while pending and report a generic failure', async () => {
  const gate = Promise.withResolvers();
  const api = fakeApi({ uninstall: async () => { await gate.promise; throw new Error('secret path C:\\Users\\x'); } });
  const settings = createVisualProviderSettings(api, () => undefined);
  settings.start();
  await flush();
  const pending = settings.uninstall();
  assert.equal(read(settings).pending, true);
  gate.resolve();
  assert.equal(await pending, false);
  const view = read(settings);
  assert.deepEqual([view.pending, view.failed], [false, true]);
  assert.equal(JSON.stringify(view).includes('secret path'), false, 'error details never reach the view');
  assert.equal(await settings.setEnabled(true), true);
  assert.equal(read(settings).failed, false, 'a later success clears the error');
});

test('sign-in opens the login window once and the dialog follows host events', async () => {
  const api = fakeApi();
  const timers = [];
  const settings = createVisualProviderSettings(api, (run, ms) => timers.push({ run, ms }));
  settings.start();
  await flush();
  await settings.signIn('Sign in to Spotify Canvas');
  assert.deepEqual(api.log.at(-1), ['openLogin', 'Sign in to Spotify Canvas']);
  assert.equal(read(settings).login, 'waiting');
  api.listeners.login.forEach(listener => listener('extracting'));
  assert.equal(read(settings).login, 'extracting');
  api.listeners.login.forEach(listener => listener('connected'));
  assert.equal(read(settings).login, 'connected');
  assert.equal(timers.length, 1);
  timers[0].run();
  assert.equal(read(settings).login, null, 'the success notice hides itself');
  // Closing the window without a token just dismisses the dialog.
  await settings.signIn(null);
  api.listeners.login.forEach(listener => listener('closed'));
  assert.equal(read(settings).login, null);
  // A failure stays visible until the user closes it, and closing cancels the window.
  api.listeners.login.forEach(listener => listener('failed'));
  assert.equal(read(settings).login, 'failed');
  await settings.closeLogin();
  assert.equal(read(settings).login, null);
  assert.deepEqual(api.log.at(-1), ['cancelLogin']);
});

test('a stale success timer does not hide a newer login attempt', async () => {
  const api = fakeApi();
  const timers = [];
  const settings = createVisualProviderSettings(api, run => timers.push(run));
  settings.start();
  await flush();
  api.listeners.login.forEach(listener => listener('connected'));
  api.listeners.login.forEach(listener => listener('waiting'));
  timers[0]();
  assert.equal(read(settings).login, 'waiting');
});

test('a login window that cannot open shows the failure', async () => {
  const settings = createVisualProviderSettings(fakeApi({ openLogin: async () => false }), () => undefined);
  settings.start();
  await settings.signIn(null);
  assert.equal(read(settings).login, 'failed');
});

test('manual token and folder install trim input and go through the host only', async () => {
  const api = fakeApi();
  const settings = createVisualProviderSettings(api, () => undefined);
  settings.start();
  await flush();
  await settings.installFromFolder('  C:\\Proveedores\\spotify-canvas  ');
  await settings.saveToken('BQD-token-token-token-token');
  assert.deepEqual(api.log, [['installFromFolder', 'C:\\Proveedores\\spotify-canvas'], ['saveToken', 'BQD-token-token-token-token']]);
  assert.equal(JSON.stringify(read(settings)).includes('BQD-token'), false, 'the view never retains a token');
});

test('the shared store keeps the newest revision and unsubscribes', async () => {
  const api = fakeApi();
  const store = createVisualProviderStore(api);
  const seen = [];
  const unsubscribe = store.subscribe(value => seen.push(value?.revision ?? null));
  await flush();
  api.listeners.changed.forEach(listener => listener(baseState({ revision: 4 })));
  api.listeners.changed.forEach(listener => listener(baseState({ revision: 3 })));
  assert.deepEqual(seen, [null, 1, 4]);
  unsubscribe();
  assert.equal(api.listeners.changed.size, 0);
});

// ---- The injected page hook, executed for real in a sandbox ----

async function sandbox({ session, fetchImpl } = {}) {
  const context = vm.createContext({ console });
  context.window = context;
  context.document = {
    readyState: 'complete',
    getElementById: id => (id === 'session' && session !== undefined ? { textContent: typeof session === 'string' ? session : JSON.stringify(session) } : null),
    addEventListener() {},
    body: { innerText: '' },
  };
  const requests = [];
  context.fetch = fetchImpl ?? (async (...args) => { requests.push(args); return { ok: true, json: async () => ({ accessToken: 'T'.repeat(40) }), clone() { return this; } }; });
  context.requests = requests;
  const headers = [];
  context.XMLHttpRequest = class { setRequestHeader(name, value) { headers.push([name, value]); } };
  context.xhrHeaders = headers;
  const hook = await readFile(new URL('../src-tauri/src/visual_provider/js/hook.js', import.meta.url), 'utf8');
  vm.runInContext(hook, context);
  const read = await readFile(new URL('../src-tauri/src/visual_provider/js/read.js', import.meta.url), 'utf8');
  return { context, tokens: () => Array.from(vm.runInContext(read, context)), run: code => vm.runInContext(code, context) };
}
const token = prefix => prefix.padEnd(40, 'x');

test('the hook reads the page session but ignores anonymous ones', async () => {
  assert.deepEqual((await sandbox({ session: { accessToken: token('anon'), isAnonymous: true } })).tokens(), []);
  assert.deepEqual((await sandbox({ session: { accessToken: token('user'), isAnonymous: false } })).tokens(), [token('user')]);
  assert.deepEqual((await sandbox({ session: '{broken json' })).tokens(), []);
  assert.deepEqual((await sandbox({})).tokens(), []);
});

test('the hook remembers Authorization headers from fetch (object, Headers, array) and XHR', async () => {
  const box = await sandbox();
  await box.context.fetch('https://api.example/x', { headers: { Authorization: `Bearer ${token('one')}` } });
  await box.context.fetch('https://api.example/x', { headers: { get: name => (name === 'authorization' ? `bearer ${token('two')}` : null) } });
  await box.context.fetch('https://api.example/x', { headers: [['AUTHORIZATION', token('three')]] });
  await box.context.fetch({ url: 'https://api.example/x', headers: { get: name => (name === 'Authorization' ? `Bearer ${token('four')}` : null) } });
  box.context.xhrHeaders.length = 0;
  new box.context.XMLHttpRequest().setRequestHeader('authorization', `Bearer ${token('five')}`);
  assert.deepEqual(box.tokens(), ['one', 'two', 'three', 'four', 'five'].map(token));
  assert.equal(box.context.xhrHeaders.length, 1, 'the original XHR method still runs');
});

test('short values are ignored, repeats move to the end and only eight are kept', async () => {
  const box = await sandbox();
  for (let i = 0; i < 10; i++) await box.context.fetch('https://x/y', { headers: { Authorization: token(`t${i}`) } });
  await box.context.fetch('https://x/y', { headers: { Authorization: 'Bearer short' } });
  await box.context.fetch('https://x/y', { headers: { Authorization: token('t5') } });
  const tokens = box.tokens();
  assert.equal(tokens.length, 8);
  assert.equal(tokens.at(-1), token('t5'));
  assert.equal(tokens.filter(value => value === token('t5')).length, 1);
  assert.equal(tokens.includes(token('t0')), false);
});

test('token responses are remembered unless the session is anonymous', async () => {
  const respond = body => async () => ({ ok: true, json: async () => body, clone() { return this; } });
  let box = await sandbox({ fetchImpl: respond({ accessToken: token('fromjson') }) });
  await box.context.fetch('https://open.example/get_access_token');
  await new Promise(resolve => setTimeout(resolve, 5));
  assert.deepEqual(box.tokens(), [token('fromjson')]);
  box = await sandbox({ fetchImpl: respond({ accessToken: token('anon'), isAnonymous: true }) });
  await box.context.fetch('https://open.example/get_access_token');
  await new Promise(resolve => setTimeout(resolve, 5));
  assert.deepEqual(box.tokens(), []);
  box = await sandbox({ fetchImpl: respond({ accessToken: token('unrelated') }) });
  await box.context.fetch('https://open.example/other');
  await new Promise(resolve => setTimeout(resolve, 5));
  assert.deepEqual(box.tokens(), [], 'only token/session/auth URLs are inspected');
});

test('pull asks the token endpoint with the session once at a time and is not enumerable', async () => {
  const gate = Promise.withResolvers();
  const box = await sandbox({ fetchImpl: async (...args) => { box.context.requests.push(args); await gate.promise; return { ok: true, json: async () => ({ accessToken: token('pulled') }) }; } });
  box.run('window.__sidebVp.pull("https://open.example/token")');
  box.run('window.__sidebVp.pull("https://open.example/token")');
  assert.equal(box.context.requests.length, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(box.context.requests[0])), ['https://open.example/token', { credentials: 'include', headers: { Accept: 'application/json' } }]);
  gate.resolve();
  await new Promise(resolve => setTimeout(resolve, 5));
  assert.deepEqual(box.tokens(), [token('pulled')]);
  box.run('window.__sidebVp.pull("https://open.example/token")');
  assert.equal(box.context.requests.length, 2, 'a later pull runs again');
  assert.equal(Object.keys(box.context).includes('__sidebVp'), false);
});

test('a failed or anonymous pull leaves the slot empty and never throws', async () => {
  let box = await sandbox({ fetchImpl: async () => { throw new Error('offline'); } });
  box.run('window.__sidebVp.pull("https://open.example/token")');
  await new Promise(resolve => setTimeout(resolve, 5));
  assert.deepEqual(box.tokens(), []);
  box = await sandbox({ fetchImpl: async () => ({ ok: true, json: async () => ({ accessToken: token('anon'), isAnonymous: true }) }) });
  box.run('window.__sidebVp.pull("https://open.example/token")');
  await new Promise(resolve => setTimeout(resolve, 5));
  assert.deepEqual(box.tokens(), []);
});

test('injecting the hook twice does not wrap the page APIs twice', async () => {
  const box = await sandbox();
  const wrapped = box.context.fetch;
  const hook = await readFile(new URL('../src-tauri/src/visual_provider/js/hook.js', import.meta.url), 'utf8');
  vm.runInContext(hook, box.context);
  assert.equal(box.context.fetch, wrapped);
});

test('the endpoint-body script returns a non-anonymous token only', async () => {
  const body = await readFile(new URL('../src-tauri/src/visual_provider/js/body.js', import.meta.url), 'utf8');
  const run = text => vm.runInNewContext(body, { document: { body: { innerText: text } } });
  assert.equal(run(JSON.stringify({ accessToken: token('body') })), token('body'));
  assert.equal(run(JSON.stringify({ access_token: token('snake') })), token('snake'));
  assert.equal(run(JSON.stringify({ accessToken: token('anon'), isAnonymous: true })), null);
  assert.equal(run('<html>not json</html>'), null);
});

test('no script talks to the app: no IPC, no beacon, no cookie or storage writes', async () => {
  for (const name of ['hook', 'body', 'read']) {
    const source = await readFile(new URL(`../src-tauri/src/visual_provider/js/${name}.js`, import.meta.url), 'utf8');
    for (const forbidden of ['__TAURI', 'postMessage', 'sendBeacon', 'document.cookie', 'localStorage', 'sessionStorage', 'WebSocket']) assert.equal(source.includes(forbidden), false, `${name}: ${forbidden}`);
  }
});

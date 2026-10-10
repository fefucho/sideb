import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { test } from 'node:test';
import ts from 'typescript';
const source = await readFile(new URL('../src/lib/i18n/format.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { lookup, format, message, normalizeLanguage } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const catalog = JSON.parse(await readFile(new URL('../src/lib/i18n/catalog.json', import.meta.url), 'utf8'));
test('all Apple editorial keys are exactly preserved and generated resources are current', () => {
  execFileSync(process.execPath, [fileURLToPath(new URL('./sync-localizations.mjs', import.meta.url)), '--check']);
});
test('Spanish defaults/fallback, English and complete plurals at presentation time', () => {
  assert.equal(normalizeLanguage('pt'), 'es');
  for (const [lang, expected] of [['es', ['0 canciones', '1 canción', '2 canciones']], ['en', ['0 songs', '1 song', '2 songs']]]) {
    assert.deepEqual([0, 1, 2].map(count => lookup(catalog, 'common.songCount', lang, [], count)), expected);
  }
  assert.equal(lookup(catalog, 'common.cancel', 'en'), 'Cancel');
  assert.equal(lookup(catalog, 'missing.key', 'en'), 'No disponible');
});
test('arguments preserve external percent signs, positional values and message descriptors remain reusable', () => {
  assert.equal(format('%@ / %@ %%', ['100% Música', 'B']), '100% Música / B %');
  assert.equal(format('%2$@ %1$@', ['a', 'b']), 'b a');
  const descriptor = message('genius.annotationBy', ['External artist']);
  assert.equal(lookup(catalog, descriptor.key, 'es', descriptor.args), 'Por External artist');
  assert.equal(lookup(catalog, descriptor.key, 'en', descriptor.args), 'By External artist');
  assert.deepEqual(descriptor, { key: 'genius.annotationBy', args: ['External artist'] });
});
test('reactive language updates preserve descriptors and installation preference across resolver instances', async () => {
  const require = createRequire(import.meta.url);
  const storage = new Map(); const previous = Object.getOwnPropertyDescriptor(globalThis, 'localStorage');
  Object.defineProperty(globalThis, 'localStorage', { configurable: true, value: { getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value) } });
  try {
    const resources = JSON.parse(await readFile(new URL('../src/lib/i18n/windows.json', import.meta.url), 'utf8'));
    const source = await readFile(new URL('../src/lib/i18n/index.ts', import.meta.url), 'utf8');
    const formatUrl = `data:text/javascript;base64,${Buffer.from(output).toString('base64')}`;
    const index = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText
      .replaceAll("'svelte/store'", JSON.stringify(pathToFileURL(require.resolve('svelte/store')).href))
      .replace("import catalog from './catalog.json';", `const catalog = ${JSON.stringify(catalog)};`)
      .replace("import windows from './windows.json';", `const windows = ${JSON.stringify(resources)};`)
      .replaceAll("'./format'", JSON.stringify(formatUrl));
    const load = async suffix => import(`data:text/javascript;base64,${Buffer.from(index + '\n//' + suffix).toString('base64')}`);
    const resolver = await load('first'); const labels = []; const descriptor = resolver.message('genius.annotationBy', ['Original name']);
    const unsubscribe = resolver.t.subscribe(t => labels.push(t('common.cancel')));
    resolver.setLanguage('en'); assert.equal(resolver.resolveMessage(descriptor), 'By Original name');
    assert.equal(storage.get('sideb.ui.language.v1'), 'en');
    resolver.setLanguage('es'); assert.equal(resolver.resolveMessage(descriptor), 'Por Original name');
    assert.deepEqual(labels, ['Cancelar', 'Cancel', 'Cancelar']);
    resolver.setLanguage('en'); const reloaded = await load('second'); assert.equal(reloaded.text('common.cancel'), 'Cancel');
    assert.equal(reloaded.translateOwnText('Nueva playlist…'), 'New playlist…');
    assert.equal(reloaded.translateOwnText('Original artist title'), 'Original artist title'); unsubscribe();
    assert.equal(reloaded.translateOwnText('No se pudo completar la lista: Original provider detail'), 'Couldn’t load the playlist: Original provider detail');
    assert.equal(reloaded.translateOwnText('Error en el actualizador (download): Original provider detail 50%'), 'Updater error (download): Original provider detail 50%');
    assert.equal(reloaded.translateOwnText('No se pudo completar la playlist: el proveedor repitió una página.'), 'Couldn’t complete the playlist: the provider repeated a page.');
  } finally { if (previous) Object.defineProperty(globalThis, 'localStorage', previous); else delete globalThis.localStorage; }
});

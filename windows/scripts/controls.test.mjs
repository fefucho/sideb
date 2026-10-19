import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { compile } from 'svelte/compiler';
import ts from 'typescript';
import { render } from 'svelte/server';

const root = fileURLToPath(new URL('../', import.meta.url));
const cache = path.join(root, '.cache/controls-test');
await mkdir(cache, { recursive: true });
const compiled = new Map();
async function compileFile(filename) {
  if (compiled.has(filename)) return compiled.get(filename);
  const destination = path.join(cache, path.basename(filename).replace(/\.(svelte|ts)$/, '.mjs'));
  compiled.set(filename, pathToFileURL(destination).href);
  const source = await readFile(filename, 'utf8');
  let code = filename.endsWith('.svelte') ? compile(source, { filename, generate: 'server' }).js.code
    : ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
  code = code.replace(/import\s+['"][^'"]+\.css['"];?/g, '');
  for (const match of [...code.matchAll(/from\s+(['"])(\.\/[^'"]+)\1/g)]) {
    let target = path.resolve(path.dirname(filename), match[2]);
    if (!path.extname(target)) target += '.ts';
    code = code.replace(match[0], `from '${await compileFile(target)}'`);
  }
  await writeFile(destination, code);
  return compiled.get(filename);
}
const directory = path.join(root, 'src/lib/components/common');
const Button = (await import(await compileFile(path.join(directory, 'ControlButton.svelte')))).default;
const Segments = (await import(await compileFile(path.join(directory, 'ControlSegments.svelte')))).default;
const { segmentKeyIndex } = await import(await compileFile(path.join(directory, 'controls.ts')));
const buttons = html => [...html.matchAll(/<button\b[^>]*>/g)].map(match=>match[0]);
const segments = props => render(Segments, { props: { id:'panel-tab', panelId:'panel', label:'Panel', options:[{id:'queue',label:'Cola'},{id:'lyrics',label:'Letras'},{id:'related',label:'Relacionado'}], value:'lyrics', onChange:()=>{}, ...props } }).body;

test('panel tabs expose one keyboard entry, shared panel association and persistent selected state', () => {
  const html = segments({});
  assert.match(html, /role="tablist"/);
  const tabs = buttons(html);
  assert.equal(tabs.length, 3);
  assert.equal(tabs.filter(tab=>tab.includes('tabindex="0"')).length,1);
  assert.ok(tabs[1].includes('tabindex="0"'));
  for(const tab of tabs) assert.ok(tab.includes('role="tab"') && tab.includes('aria-controls="panel"'));
  assert.ok(tabs[1].includes('aria-selected="true"') && tabs[1].includes('data-selected="true"'));
});

test('disabled selected tab falls back to an enabled keyboard entry, and button groups keep button semantics', () => {
  const tabs=buttons(segments({options:[{id:'queue',label:'Cola'},{id:'lyrics',label:'Letras',disabled:true}]}));
  assert.ok(tabs[0].includes('tabindex="0"') && tabs[0].includes('aria-selected="true"'));
  assert.ok(tabs[1].includes('aria-selected="false"'));
  assert.ok(tabs[1].includes('tabindex="-1"')&&tabs[1].includes('disabled'));
  const html=segments({panelId:undefined});
  assert.match(html,/role="group"/);
  assert.doesNotMatch(html,/role="tab"|aria-selected=/);
  assert.match(html,/aria-pressed="true"/);
});

test('unknown tab values keep accessible and visual selection aligned with the first enabled tab', () => {
  const tabs=buttons(segments({value:'missing'}));
  assert.ok(tabs[0].includes('aria-selected="true"') && tabs[0].includes('data-selected="true"') && tabs[0].includes('tabindex="0"'));
  assert.ok(tabs.slice(1).every(tab=>tab.includes('aria-selected="false"') && tab.includes('data-selected="false"')));
});

test('loading action disables interaction and retains native form type and accessible name', () => {
  const html=render(Button,{props:{loading:true,type:'submit','aria-label':'Guardar playlist',selected:true}}).body;
  assert.match(html,/type="submit"/);
  assert.match(html,/disabled/);
  assert.match(html,/aria-busy="true"/);
  assert.match(html,/aria-label="Guardar playlist"/);
  assert.match(html,/data-selected="true"/);
  assert.match(html,/sideb-control-spinner" aria-hidden="true"/);
  assert.doesNotMatch(render(Button,{props:{}}).body,/aria-busy=/);
});

test('tab arrows wrap, respect RTL and leave vertical, Enter and modifier-neutral keys native', () => {
  assert.equal(segmentKeyIndex('ArrowRight',2,3),0);
  assert.equal(segmentKeyIndex('ArrowLeft',0,3),2);
  assert.equal(segmentKeyIndex('ArrowRight',0,3,true),2);
  assert.equal(segmentKeyIndex('ArrowLeft',2,3,true),0);
  assert.equal(segmentKeyIndex('Home',2,3),0);
  assert.equal(segmentKeyIndex('End',0,3),2);
  for(const key of ['ArrowDown','ArrowUp','Enter',' ','Tab','Escape']) assert.equal(segmentKeyIndex(key,1,3),null);
  assert.equal(segmentKeyIndex('ArrowRight',0,0),null);
  assert.equal(segmentKeyIndex('ArrowRight',0,1),0);
});

test('optimistic toggle feedback keeps its label and selected state while preventing duplicate submissions', () => {
  const html=render(Button,{props:{loading:true,loadingFeedback:'subtle',selected:true,'aria-label':'En biblioteca'}}).body;
  assert.match(html,/disabled/);assert.match(html,/aria-busy="true"/);assert.match(html,/data-selected="true"/);
  assert.match(html,/data-loading-feedback="subtle"/);assert.match(html,/sideb-control-pending" aria-hidden="true"/);
  assert.doesNotMatch(html,/sideb-control-spinner/);
});

test('compact toolbar appearance is opt-in and preserves tab selection and keyboard entry', () => {
  assert.match(segments({}), /data-appearance="standard"/);
  const html = segments({appearance:'toolbar'});
  assert.match(html, /data-appearance="toolbar"/);
  assert.match(html, /role="tablist"/);
  const tabs = buttons(html);
  assert.ok(tabs[1].includes('aria-selected="true"') && tabs[1].includes('tabindex="0"'));
  assert.equal(tabs.filter(tab => tab.includes('tabindex="0"')).length, 1);
});

import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import ts from 'typescript';
const require=createRequire(import.meta.url);
const source=await readFile(new URL('../src/lib/player/queuePreferences.ts',import.meta.url),'utf8');
const js=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText
 .replace("'svelte/store'",JSON.stringify(pathToFileURL(require.resolve('svelte/store')).href));
const {createQueuePreferences,queueSelectionKey,resolveQueueSelection}=await import(`data:text/javascript;base64,${Buffer.from(js).toString('base64')}`);
test('queue selection defaults to advancing and validates persisted values',()=>{
 for(const raw of [undefined,null,'broken','selected-only',{},true])assert.equal(resolveQueueSelection(raw),'advance');
 assert.equal(resolveQueueSelection('play-only'),'play-only');
 const values=new Map(),storage={getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value)};
 let prefs=createQueuePreferences(storage);const events=[];const unsubscribe=prefs.subscribe(value=>events.push(value));
 assert.equal(prefs.currentSelection(),'advance');assert.equal(values.size,0,'reading does not mutate storage');
 prefs.setSelection('play-only');assert.equal(events.at(-1),'play-only');assert.equal(values.get(queueSelectionKey),'play-only');
 prefs=createQueuePreferences(storage);assert.equal(prefs.currentSelection(),'play-only');
 prefs.setSelection('advance');assert.equal(createQueuePreferences(storage).currentSelection(),'advance');unsubscribe();
});
test('queue selection remains usable when preference storage is unavailable',()=>{
 const prefs=createQueuePreferences({getItem(){throw Error('blocked');},setItem(){throw Error('blocked');}});
 assert.equal(prefs.currentSelection(),'advance');prefs.setSelection('play-only');assert.equal(prefs.currentSelection(),'play-only');
});

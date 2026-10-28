import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import ts from 'typescript';

const source=await readFile(new URL('../src/lib/artwork/runtime.ts',import.meta.url),'utf8');
const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText
 .replace(/import \{ invoke \} from ['"]@tauri-apps\/api\/core['"];?/, 'const invoke=(...args)=>globalThis.__artworkRuntimeTest.invoke(...args);')
 .replace(/import \{ listen \} from ['"]@tauri-apps\/api\/event['"];?/, 'const listen=(...args)=>globalThis.__artworkRuntimeTest.listen(...args);');
const {observeAnimatedArtworkRuntime}=await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
const deferred=()=>{let resolve;const promise=new Promise(done=>resolve=done);return {promise,resolve};};
const flush=async()=>{for(let i=0;i<8;i++)await Promise.resolve();};
const visible={visible:true,minimized:false,cloaked:false,powerSaver:false,memoryPressure:false};

test('native event received while the initial snapshot is pending owns the current policy',async()=>{
 const snapshot=deferred();let handler,stops=0;const published=[];
 globalThis.__artworkRuntimeTest={listen:async(name,callback)=>{assert.equal(name,'animated-artwork-runtime-changed');handler=callback;return()=>stops++;},invoke:command=>{assert.equal(command,'get_animated_artwork_runtime_state');return snapshot.promise;}};
 const stop=observeAnimatedArtworkRuntime(state=>published.push(state));await flush();
 const minimized={...visible,minimized:true};handler({payload:minimized});snapshot.resolve(visible);await flush();
 assert.deepEqual(published,[minimized]);stop();assert.equal(stops,1);
});

test('unmount before listener registration completes removes it without starting a stale snapshot',async()=>{
 const registered=deferred();let stops=0,snapshots=0;const published=[];
 globalThis.__artworkRuntimeTest={listen:()=>registered.promise,invoke:async()=>{snapshots++;return visible;}};
 const stop=observeAnimatedArtworkRuntime(state=>published.push(state));stop();registered.resolve(()=>stops++);await flush();
 assert.equal(stops,1);assert.equal(snapshots,0);assert.deepEqual(published,[]);
});

test('unmount while a snapshot is pending cannot publish into a later fullscreen owner',async()=>{
 const snapshot=deferred();let stops=0;const published=[];
 globalThis.__artworkRuntimeTest={listen:async()=>()=>stops++,invoke:()=>snapshot.promise};
 const stop=observeAnimatedArtworkRuntime(state=>published.push(state));await flush();stop();snapshot.resolve(visible);await flush();
 assert.equal(stops,1);assert.deepEqual(published,[]);
});

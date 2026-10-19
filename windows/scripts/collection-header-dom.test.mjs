import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if(!process.execArgv.includes('--conditions=browser')) {
  test('real collection details preserve toolbar actions, filter focus and occurrence identity',()=>{
    const {NODE_TEST_CONTEXT,...env}=process.env;
    const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
    assert.equal(result.status,0,result.stdout+result.stderr);
  });
} else {
  const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
  const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('collection-header-dom');
  globalThis.IntersectionObserver=class {observe(){} disconnect(){}};
  const Fixture=(await import(await moduleFor(path.join(root,'scripts/fixtures/CollectionLayout.svelte')))).default;
  let session=0;
  async function fixture(mode='playlist',paginated=false) {
    const host=document.createElement('div');document.body.append(host);const calls=[];let instance;
    flushSync(()=>instance=mount(Fixture,{target:host,props:{mode,paginated,session:'collection-test-'+session++,onAction:(...args)=>calls.push(args)},intro:false}));
    const input=host.querySelector('input');
    const filter=value=>{input.value=value;input.dispatchEvent(new dom.Event('input',{bubbles:true}));flushSync();};
    return {host,calls,input,filter,instance,dispose:async()=>{await unmount(instance);host.remove();}};
  }
  test('toolbar is below the complete identity row and editing/resizing keeps the actual input and selection',async()=>{
    const f=await fixture();const header=f.host.querySelector('header.collection-header');
    assert.deepEqual([...header.children].map(node=>node.className.split(' ')[0]),['identity','toolbar']);
    assert.equal(header.querySelector('.metadata .toolbar'),null);
    f.input.focus();f.filter('Coincidencia');f.input.setSelectionRange(2,6);
    flushSync(()=>f.instance.configure({width:480}));await tick();
    assert.equal(f.host.querySelector('input'),f.input);assert.equal(document.activeElement,f.input);assert.equal(f.input.value,'Coincidencia');assert.equal(f.input.selectionStart,2);assert.equal(f.input.selectionEnd,6);
    f.host.querySelectorAll('button.song-title')[1].click();flushSync();
    assert.deepEqual(f.calls.find(call=>call[0]==='play'),['play',[1,false,'custom']]);
    const clear=f.host.querySelector('.filter button');clear.click();flushSync();assert.equal(f.input.value,'');assert.equal(document.activeElement,f.input);
    f.filter('Canción');f.input.dispatchEvent(new dom.KeyboardEvent('keydown',{key:'Escape',bubbles:true}));flushSync();assert.notEqual(document.activeElement,f.input);assert.equal(f.input.value,'Canción');
    await f.dispose();
  });
  test('album omits sorting and playlist variants retain their save and editing permissions',async()=>{
    for(const mode of ['album','playlist','owned','liked']) {
      const f=await fixture(mode);
      assert.equal(Boolean(f.host.querySelector('select')),mode!=='album');
      assert.equal(f.host.querySelectorAll('.actions > button').length,mode==='owned'||mode==='liked'?3:4);
      assert.equal(Boolean(f.host.querySelector('[draggable=true]')),mode==='owned');
      if(mode==='owned'){f.filter('Coincidencia');assert.equal(Boolean(f.host.querySelector('[draggable=true]')),false);}
      const actions=f.host.querySelector('header .actions');actions.querySelector('button').click();flushSync();
      assert.equal(f.calls.at(-1)[0],'play');
      await f.dispose();
    }
  });
  test('ordering a paginated playlist requests completion and preserves filter input',async()=>{
    const f=await fixture('playlist',true);f.input.focus();f.filter('Coincidencia');
    const select=f.host.querySelector('select');
    // Happy DOM omits option:checked; supply the browser's selected-option query for Svelte's binding.
    const querySelector=select.querySelector.bind(select);
    select.querySelector=selector=>selector===':checked'?select.selectedOptions[0]??null:querySelector(selector);
    select.selectedIndex=1;select.dispatchEvent(new dom.Event('change',{bubbles:true}));flushSync();await tick();
    assert.deepEqual(f.calls.filter(call=>call[0]==='complete'),[['complete']]);assert.equal(f.host.querySelector('input'),f.input);assert.equal(document.activeElement,f.input);assert.equal(f.input.value,'Coincidencia');
    assert.equal(f.host.querySelector('header .actions button').disabled,true);
    await f.dispose();
  });
  test('both detail headers retain shuffle, save, menu, description and credit destinations',async()=>{
    for(const mode of ['album','playlist']) {
      const f=await fixture(mode);const actions=f.host.querySelectorAll('header .actions > button');
      actions[1].click();flushSync();assert.deepEqual(f.calls.at(-1),['play',mode==='album'?[0,true]:[0,true,'custom']]);
      actions[2].click();flushSync();await tick();assert.equal(f.calls.at(-1)[0],'save');
      actions[3].dispatchEvent(new dom.KeyboardEvent('keydown',{key:'F10',shiftKey:true,bubbles:true}));flushSync();
      if(mode==='album')assert.deepEqual(f.calls.at(-1),['menu','album']);else assert.deepEqual(f.calls.at(-1),['menu']);
      if(mode==='album'){f.host.querySelector('.credit button').click();flushSync();assert.deepEqual(f.calls.at(-1),['artist','artist']);}
      const description=f.host.querySelector('button.description');description.focus();description.click();flushSync();await tick();
      assert.ok(f.host.querySelector('[role=dialog]'));document.dispatchEvent(new dom.KeyboardEvent('keydown',{key:'Escape',bubbles:true}));flushSync();await tick();
      assert.equal(f.host.querySelector('[role=dialog]'),null);assert.equal(document.activeElement,description);
      await f.dispose();
    }
  });
}

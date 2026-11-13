import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if(!process.execArgv.includes('--conditions=browser')) {
 test('mounted search groups the general search by category and keeps the provider list for filtered pages',()=>{
  const {NODE_TEST_CONTEXT,...env}=process.env;
  const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
  assert.equal(result.status,0,result.stdout+result.stderr);
 });
} else {
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('search-categories-dom');
 globalThis.IntersectionObserver=class {observe(){} disconnect(){}};
 const Fixture=(await import(await moduleFor(path.join(root,'scripts/fixtures/SearchCategories.svelte')))).default;
 const settle=async()=>{flushSync();await tick();flushSync();await new Promise(r=>setTimeout(r,30));flushSync();};
 const text=host=>host.querySelector('.search-page').textContent;
 async function mounted(props){const host=document.createElement('div');document.body.append(host);const calls=[];let app;
  flushSync(()=>app=mount(Fixture,{target:host,props:{...props,onCall:(...args)=>calls.push(args)},intro:false}));await settle();
  return {host,calls,done:async()=>{await unmount(app);host.remove();}};}

 test('the general search shows the principal then one section per category, without «Listen again» or load more',async()=>{
  const {host,calls,done}=await mounted({});
  assert.ok(text(host).includes('Kendrick Lamar'),'the principal block stays');
  assert.equal(text(host).includes('Listen again'),false);assert.equal(text(host).includes('Personal pick'),false);
  assert.equal([...host.querySelectorAll('.section-heading h2')].length>=3,true,'Songs, Artists and Albums headings');
  const grid=host.querySelector('.song-grid');assert.ok(grid,'songs form a grid');
  assert.equal(grid.querySelectorAll('.song-row').length,3,'three rows, and only the columns follow the width');
  assert.ok(host.querySelector('[role=status] .spinner'),'the pending Playlists category shows a placeholder');
  assert.equal([...host.querySelectorAll('button')].some(button=>/more results|Cargar más/i.test(button.textContent)),false,'category sections are complete; «show all» replaces paging');
  const showAll=[...host.querySelectorAll('.section-heading button')];assert.ok(showAll.length>=1);
  showAll[0].click();flushSync();
  assert.equal(calls.at(-1)[0],'more');assert.match(calls.at(-1)[1].moreParams,/^params-/,'show all is the chip search');
  await done();
 });

 test('the principal\'s related song without artist is credited to that artist, not left blank',async()=>{
  const {host,done}=await mounted({});
  assert.ok(text(host).includes('Song r1'));
  assert.ok(host.querySelector('.related .credits')?.textContent.includes('Kendrick Lamar'),'the credit line names the artist');
  await done();
 });

 test('a filtered page keeps the provider list, including its titled shelves',async()=>{
  const {host,done}=await mounted({filtered:true});
  assert.ok(text(host).includes('Listen again'));assert.equal(host.querySelector('.song-grid'),null);
  await done();
 });
}

import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if(!process.execArgv.includes('--conditions=browser')) {
 test('mounted artist profile recycles shelves/cards, owns horizontal input and keeps actions',()=>{
  const {NODE_TEST_CONTEXT,...env}=process.env;
  const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
  assert.equal(result.status,0,result.stdout+result.stderr);
 });
} else {
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('artist-profile-dom');
 globalThis.IntersectionObserver=class {observe(){} disconnect(){}};
 const Fixture=(await import(await moduleFor(path.join(root,'scripts/fixtures/ArtistProfile.svelte')))).default;
 const settle=async()=>{flushSync();await tick();flushSync();await new Promise(r=>setTimeout(r,30));flushSync();};
 test('only nearby shelves and cards are mounted; shelves own horizontal gestures; actions keep working',async()=>{
  const host=document.createElement('div');document.body.append(host);const calls=[];let app;
  try {
   app=mount(Fixture,{target:host,props:{sections:24,cards:120,onCall:(...args)=>calls.push(args)},intro:false});await settle();
   const shelves=host.querySelectorAll('[data-artist-shelf]'),cards=host.querySelectorAll('.carousel-card');
   assert.ok(shelves.length>0&&shelves.length<=6,`mounted shelves ${shelves.length}`);
   assert.ok(cards.length<=shelves.length*30,`mounted cards ${cards.length} of ${24*120}`);
   for(const carousel of host.querySelectorAll('[data-artist-carousel]')){
    assert.ok(carousel.hasAttribute('data-horizontal-scroll'),'arrow navigation keeps its scroller');
    assert.ok(carousel.hasAttribute('data-gesture-local'),'the shelf owns horizontal gestures');
   }
   const track=host.querySelector('.track');
   assert.match(track.style.paddingInlineEnd,/px$/,'spacer keeps the remaining extent');
   assert.ok(host.querySelector('[data-artist-shelf] h2').textContent.startsWith('Shelf'));
   assert.equal(host.querySelectorAll('[data-artist-shelf] h2').length,shelves.length);
   // "See all" appears only for browse IDs that can open a catalog, and still reaches the page.
   const more=[...host.querySelectorAll('[data-artist-shelf] .section-heading button')];
   assert.ok(more.length>0);more[0].click();flushSync();
   assert.equal(calls.at(-1)[0],'catalog');assert.match(calls.at(-1)[1],/^MPRE/);
   // Cards: video/song activation plays, albums open.
   host.querySelector('.carousel-card .primary').click();flushSync();
   assert.ok(['play','album'].includes(calls.at(-1)[0]),String(calls.at(-1)));
  } finally {if(app)await unmount(app);host.remove();}
 });
 test('sections without items are omitted and an empty profile mounts no shelf',async()=>{
  const host=document.createElement('div');document.body.append(host);let app;
  try {
   app=mount(Fixture,{target:host,props:{sections:0,cards:0},intro:false});await settle();
   assert.equal(host.querySelectorAll('[data-artist-shelf]').length,0);
  } finally {if(app)await unmount(app);host.remove();}
 });
}

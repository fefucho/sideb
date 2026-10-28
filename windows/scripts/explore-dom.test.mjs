import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if(!process.execArgv.includes('--conditions=browser')) {
 test('Explore preserves its real scroll through modal coverage and applies navigation restores',()=>{
  const {NODE_TEST_CONTEXT,...env}=process.env;
  const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
  assert.equal(result.status,0,result.stdout+result.stderr);
 });
} else {
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('explore-retention-test');
 const settle=async()=>{flushSync();await tick();flushSync();};
 const Fixture=(await import(await moduleFor(path.join(root,'scripts/fixtures/ExploreRetentionFixture.svelte'),`<script>
  import ExploreView from '$lib/components/explore/ExploreView.svelte';
  let active=$state(true);
  let data=$state({route:'genres',items:[],sections:[],countries:[],detectedCountry:null,regionMessage:null,isLoading:false,error:null,scrollTop:0});
  export function cover(value){active=!value;}
  export function restore(route,scrollTop){data={...data,route,scrollTop};}
 </script><ExploreView {data} {active} onNavigate={()=>{}} onRefresh={()=>{}} onOpenCard={()=>{}} onScrollTop={value=>globalThis.__exploreRetainedOffset=value}/>`))).default;

 test('modal coverage does not overwrite actual scroll with the controllers old publication',async()=>{
  const target=document.createElement('div');document.body.append(target);let app;
  try {
   app=mount(Fixture,{target});await settle();const scroll=target.querySelector('.explore-scroll');
   for(let i=0;i<10;i++){
    const offset=500+i*20;
    scroll.scrollTop=offset;scroll.dispatchEvent(new dom.Event('scroll'));await settle();
    assert.equal(globalThis.__exploreRetainedOffset,offset);
    app.cover(true);await settle();assert.equal(target.querySelector('.explore-scroll'),scroll);
    app.cover(false);await settle();assert.equal(scroll.scrollTop,offset);
   }
  } finally {if(app)await unmount(app);target.remove();}
 });

 test('a restored navigation snapshot still replaces scroll, including while inactive',async()=>{
  const target=document.createElement('div');document.body.append(target);let app;
  try {
   app=mount(Fixture,{target});await settle();const scroll=target.querySelector('.explore-scroll');
   scroll.scrollTop=500;scroll.dispatchEvent(new dom.Event('scroll'));await settle();
   app.restore('genres',170);await settle();assert.equal(scroll.scrollTop,170);
   app.cover(true);await settle();app.restore('moods',240);await settle();
   app.cover(false);await settle();assert.equal(scroll.scrollTop,240);
  } finally {if(app)await unmount(app);target.remove();}
 });
}

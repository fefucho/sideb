import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
if(!process.execArgv.includes('--conditions=browser')){
 test('secondary metadata badges preserve credits, title actions and recycled state',()=>{
  const {NODE_TEST_CONTEXT,...env}=process.env;
  const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
  assert.equal(result.status,0,result.stdout+result.stderr);
 });
}else{
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('content-rating-layout');
 const source=`<script>
 import Credits from '$lib/components/ArtistCredits.svelte';import Title from '$lib/components/FeaturedTrackTitle.svelte';import Header from '$lib/components/detail/CollectionHeader.svelte';
 let rating=$state('explicit'),missing=$state(false);const calls=[];
 const track=$derived({videoId:'same-id',title:'Same selected song',artists:missing?'':'Artist',contentRating:rating});
 globalThis.lab={update:(value,empty=false)=>{rating=value;missing=empty},calls,identity:()=>track.videoId};
 </script><h1><Title {track} onPlay={()=>calls.push(track.videoId)}/></h1><section class="credits"><Credits {track} artists={track.artists} artistId="artist-id" onOpenArtist={id=>calls.push(id)} album={missing?null:'Album'} albumId="album-id" onOpenAlbum={id=>calls.push(id)}/></section><Header identity="album" title="Album" thumbnail={null} kind="Album" content={{contentRating:rating}}>{#snippet actions()}<button>Play album</button>{/snippet}</Header>`;
 const Harness=(await import(await moduleFor(path.join(root,'scripts/ContentRatingLayoutHarness.svelte'),source))).default;
 test('title is free; linked credits retain actions; known metadata alone survives missing artists',async()=>{
  const target=document.createElement('div');document.body.append(target);let app;flushSync(()=>app=mount(Harness,{target}));await tick();
  assert.equal(target.querySelectorAll('h1 .explicit-badge').length,0);
  assert.equal(target.querySelectorAll('.credits .explicit-badge').length,1);
  assert.equal(target.querySelector('.credits .artist-credits').firstElementChild.getAttribute('role'),'img');
  target.querySelector('.title-text').click();target.querySelector('.credits .featured-link').click();target.querySelector('.album-name').click();
  assert.deepEqual(lab.calls,['same-id','artist-id','album-id']);
  for(const rating of ['unknown','clean','explicit','unknown']){
   flushSync(()=>lab.update(rating));await tick();
   assert.equal(lab.identity(),'same-id');
   assert.equal(target.querySelectorAll('.credits .explicit-badge').length,rating==='unknown'?0:1);
   assert.equal(target.querySelectorAll('.collection-header .credit').length,rating==='unknown'?0:1,'unknown without credit must not reserve an empty secondary row');
   assert.equal(target.querySelectorAll('h1 .explicit-badge').length,0);
  }
  flushSync(()=>lab.update('explicit',true));await tick();
  assert.equal(target.querySelectorAll('.credits .explicit-badge').length,1);
  assert.equal(target.querySelectorAll('.credits .credit-content').length,0,'badge alone does not reserve a text gap');
  flushSync(()=>lab.update('unknown',true));await tick();assert.equal(target.querySelectorAll('.credits .artist-credits').length,0);
  await unmount(app);target.remove();
 });
}

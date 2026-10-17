import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if(!process.execArgv.includes('--conditions=browser')) {
  test('mounted TrackList playback identity, selection and keyboard',()=>{
    const {NODE_TEST_CONTEXT,...env}=process.env;
    const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
    assert.equal(result.status,0,result.stdout+result.stderr);
  });
} else {
  const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
  const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('track-list-dom-test');
  const source=`<script>
    import {setContext} from 'svelte';
    import TrackList from '$lib/components/common/TrackList.svelte';
    import {MEDIA_CONTEXT,occurrenceActive} from '$lib/player/media';
    let {items,initial,withMedia=true,onPlay,onToggle}=$props();
    let snapshot=$state(initial);
    if(withMedia)setContext(MEDIA_CONTEXT,{state:()=>snapshot,pending:()=>null,activate:()=>{},toggle:onToggle,rowActive:(song,index,source)=>occurrenceActive(snapshot,song,index,source.kind,source.id)});
    export function update(value){snapshot=value;}
  </script>
  <TrackList {items} source={{kind:'playlist',id:'PL1'}} currentTrackId={snapshot.currentTrack?.videoId??null} isPlaying={snapshot.isPlaying} {onPlay} />`;
  const Fixture=(await import(await moduleFor(path.join(root,'scripts/fixtures/TrackListPlayback.svelte'),source))).default;
  const songs=[{videoId:'same',title:'First',artists:'Artist',setVideoId:'first'},{videoId:'same',title:'Second',artists:'Artist',setVideoId:'second'},{videoId:'next',title:'Next',artists:'Artist'}];
  const entries=songs.map((song,index)=>({...song,entryId:'queue-native-'+index,sourceOccurrenceId:['collection','playlist','PL1',song.setVideoId??'index:'+index,song.videoId].map(encodeURIComponent).join('|')}));
  const state=index=>({currentTrack:entries[index],isPlaying:true,isLoading:false,isShuffle:true,queue:{items:[entries[1],entries[2],entries[0]],currentIndex:[2,0,1][index],source:{kind:'playlist',id:'PL1'},revision:index}});
  async function fixture(withMedia=true) {
    const host=document.createElement('div');document.body.append(host);const played=[],toggled=[];let instance;
    flushSync(()=>instance=mount(Fixture,{target:host,props:{items:songs,initial:state(1),withMedia,onPlay:index=>played.push(index),onToggle:()=>toggled.push(true)},intro:false}));
    const rows=()=>[...host.querySelectorAll('.track-row')];
    return {host,instance,played,toggled,rows,click:(index,options={})=>{rows()[index].dispatchEvent(new dom.MouseEvent('click',{bubbles:true,detail:1,...options}));flushSync();},dispose:async()=>{await unmount(instance);host.remove();}};
  }
  test('only the exact native source occurrence is active; another duplicate plays instead of toggling',async()=>{
    const f=await fixture();assert.deepEqual(f.rows().map(row=>row.classList.contains('active')),[false,true,false]);
    f.click(0);assert.deepEqual(f.played,[0]);assert.equal(f.toggled.length,0);assert.equal(f.host.querySelectorAll('.selected').length,0);
    f.click(1);assert.equal(f.toggled.length,1);
    flushSync(()=>f.instance.update(state(2)));assert.deepEqual(f.rows().map(row=>row.classList.contains('active')),[false,false,true]);
    assert.equal(f.host.querySelectorAll('.selected').length,0);await f.dispose();
  });
  test('modifier selection survives until playback changes and arrow keys focus the actual title button',async()=>{
    const f=await fixture();f.click(0,{ctrlKey:true});assert.equal(f.host.querySelectorAll('.selected').length,1);assert.equal(f.played.length,0);assert.equal(f.toggled.length,0);
    const first=f.rows()[0].querySelector('button.song-title');first.focus();first.dispatchEvent(new dom.KeyboardEvent('keydown',{bubbles:true,key:'ArrowDown'}));flushSync();await tick();
    assert.equal(document.activeElement,f.rows()[1].querySelector('button.song-title'));
    flushSync(()=>f.instance.update(state(2)));assert.equal(f.host.querySelectorAll('.selected').length,0);await f.dispose();
  });
  test('without a media service the ID fallback still invokes onPlay',async()=>{
    const f=await fixture(false);assert.deepEqual(f.rows().map(row=>row.classList.contains('active')),[true,false,false]);f.click(0);assert.deepEqual(f.played,[0]);await f.dispose();
  });
}

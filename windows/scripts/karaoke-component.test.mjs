import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {mountedSvelteEnvironment} from './helpers/mount-svelte.mjs';
if(!process.execArgv.includes('--conditions=browser')) {
 test('mounted lyrics fallback, manual blur and source lifecycle',()=>{const {NODE_TEST_CONTEXT,...env}=process.env;const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});assert.equal(result.status,0,result.stdout+result.stderr);});
}else{
 const {root,dom,moduleFor,mount,unmount,flushSync}=await mountedSvelteEnvironment('karaoke-component');
 dom.Range.prototype.getClientRects=()=>[];
 dom.matchMedia=()=>({matches:false,addEventListener(){},removeEventListener(){}});
 const pending=[];dom.__TAURI_INTERNALS__={invoke:(command,args)=>new Promise((resolve,reject)=>pending.push({command,args,resolve,reject}))};
 // No native shaping geometry exists in happy-dom. This test verifies mounted
 // state/interaction, not glyph placement or GPU/WebView2 frame presentation.
 const Panel=(await import(await moduleFor(path.join(root,'src/lib/components/fullscreen/LyricsPanel.svelte')))).default;
 const component=path.join(root,'src/lib/components/fullscreen/LyricsPanel.svelte');
 const lyric=(text,timeMs)=>({text,timeMs,endTimeMs:timeMs+500,words:[]});
 const classic={status:'ready',trackKey:JSON.stringify(['a',1]),lyrics:{provider:'LRCLIB',isSynced:true,lines:[lyric('Original phrase',3418),lyric('Later phrase',12000)]},error:null};
 const playback={isPlaying:false,isLoading:false,position:4,duration:20,generation:1,queue:{items:[{entryId:'one'}],currentIndex:0},currentTrack:{videoId:'a',title:'Song',artists:'Artist',duration:20}};
 globalThis.__lyricProps={state:classic,playback,session:1,active:true,onSeek:s=>globalThis.__lyricSeek=s,onRetry:()=>{}};
 const source=`<script>import Panel from '${component}';let values=$state(globalThis.__lyricProps);globalThis.__setLyricProps=next=>Object.assign(values,next);</script><Panel {...values}/>`;
 const Harness=(await import(await moduleFor(path.join(root,'src/lib/components/fullscreen/LyricsHarness.svelte'),source.replace(component,'./LyricsPanel.svelte')))).default;
 const settle=async()=>{await new Promise(r=>setTimeout(r,5));flushSync();};
 test('fallback and late rich arrival share size/mode/manual; user scroll alone strips contextual blur until Volver',async()=>{
  const app=mount(Harness,{target:document.body});flushSync();await settle();assert.equal(pending.length,1);assert.match(document.body.textContent,/Original phrase/);
  const button=label=>[...document.querySelectorAll('button')].find(b=>b.textContent===label);
  document.querySelector('.more').click();flushSync();
  const size=document.querySelector('input[type=range]');size.value='42';size.dispatchEvent(new dom.Event('input',{bubbles:true}));flushSync();assert.match(document.querySelector('section').getAttribute('style'),/--size:\s*42px/);
  const scroll=document.querySelector('.lyrics-scroll');scroll.dispatchEvent(new dom.WheelEvent('wheel',{deltaY:100,bubbles:true}));flushSync();assert.ok(document.querySelector('section').classList.contains('manual'));
  pending[0].resolve({provider:'TTML',isSynced:true,instrumental:false,lines:[{...lyric('New phrase',3418),translation:'Frase traducida',words:[{text:'New',startMs:3418,endMs:3600},{text:'phrase',startMs:3600,endMs:3918}]},lyric('New later',12000)]});await settle();assert.match(document.body.textContent,/New phrase/);assert.ok(document.querySelector('section').classList.contains('manual'));assert.match(document.querySelector('section').getAttribute('style'),/--size:\s*42px/);
  globalThis.__setLyricProps({playback:{...playback,position:13}});flushSync();await settle();assert.ok(document.querySelector('section').classList.contains('manual'));
  document.querySelector('.follow').click();flushSync();assert.ok(!document.querySelector('section').classList.contains('manual'));
  const controls=document.querySelectorAll('.menu input[type=checkbox]');assert.equal(controls.length,2);controls[0].click();controls[1].click();flushSync();assert.equal(document.querySelector('.translation'),null);
  button('Lectura').click();flushSync();assert.ok(document.querySelector('section').classList.contains('reading'));
  const timing=document.querySelector('input[min="-5000"]');timing.value='100';timing.dispatchEvent(new dom.Event('input',{bubbles:true}));flushSync();document.querySelector('button.line').click();flushSync();assert.equal(globalThis.__lyricSeek,3.318);
  button('Letras originales').click();flushSync();await settle();assert.match(document.body.textContent,/Original phrase/);assert.ok(document.querySelector('section').classList.contains('reading'));assert.match(document.querySelector('section').getAttribute('style'),/--size:\s*42px/);
  document.querySelector('button.line').click();flushSync();assert.equal(globalThis.__lyricSeek,3.418);
  const count=pending.length;globalThis.__setLyricProps({active:false});flushSync();await settle();assert.equal(pending.length,count);assert.equal(document.querySelector('section').hidden,true);assert.equal(document.querySelector('.lyrics-scroll'),null);
  await unmount(app);await settle();
 });
}

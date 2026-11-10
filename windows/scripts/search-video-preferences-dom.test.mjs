import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if(!process.execArgv.includes('--conditions=browser')) {
 test('mounted search results and suggestions hide and restore videos from the real settings switch',()=>{
  const {NODE_TEST_CONTEXT,...env}=process.env;
  const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
  assert.equal(result.status,0,result.stdout+result.stderr);
 });
} else {
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('search-video-preferences-dom');
 globalThis.IntersectionObserver=class {observe(){} disconnect(){}};
 const Fixture=(await import(await moduleFor(path.join(root,'scripts/fixtures/SearchVideoPreference.svelte')))).default;
 const prefs=(await import(await moduleFor(path.join(root,'src/lib/search/searchPreferences.ts')))).searchPreferences;
 const settle=async()=>{flushSync();await tick();flushSync();await new Promise(r=>setTimeout(r,30));flushSync();};
 const text=host=>host.querySelector('.search-page').textContent;
 test('the settings switch filters visible results, appended pages, provider actions and suggestions, and restores them',async()=>{
  prefs.setShowVideos(true);
  const host=document.createElement('div');document.body.append(host);const calls=[];let app;
  try {
   app=mount(Fixture,{target:host,props:{onCall:(...args)=>calls.push(args)},intro:false});await settle();
   const toggle=host.querySelector('#search-show-videos');
   assert.equal(toggle.checked,true,'videos are shown by default');
   assert.ok(text(host).includes('Hidden video row'));assert.ok(text(host).includes('Video only card'));assert.ok(text(host).includes('Only videos section'));
   assert.ok(host.querySelector('.principal-container .actions, .principal-container [class*=action]')||text(host).includes('Provider action'));
   toggle.checked=false;toggle.dispatchEvent(new window.Event('change',{bubbles:true}));await settle();
   assert.equal(prefs.currentShowVideos(),false);
   for(const hidden of ['Hidden video row','Video only card','Only videos section','Provider action'])assert.equal(text(host).includes(hidden),false,hidden+' stays hidden');
   for(const kept of ['Principal artist','Visible song one','Visible song two'])assert.ok(text(host).includes(kept),kept+' remains');
   // Appending a continuation keeps filtering and keeps the Load more control for the original token.
   host.querySelector('[data-append]').click();await settle();
   assert.equal(text(host).includes('Appended video'),false);assert.ok(text(host).includes('Appended song'));assert.equal(text(host).includes('More videos'),false);
   assert.ok([...host.querySelectorAll('button')].some(button=>button.textContent.trim().length&&button.closest('.results-scroll')&&!button.closest('[role=region]')),'a load-more control remains');
   // Suggestions in the focused dropdown: text and history stay, video media does not.
   host.querySelector('.search-field input').dispatchEvent(new window.FocusEvent('focus'));await settle();
   const preview=host.querySelector('.preview-content')?.textContent??'';
   assert.ok(preview.includes('video games')&&preview.includes('old video'),'text queries and remote history remain');
   assert.equal(preview.includes('Suggested video'),false);assert.ok(preview.includes('Suggested song'));
   // Reactivation returns the same videos with no refetch.
   toggle.checked=true;toggle.dispatchEvent(new window.Event('change',{bubbles:true}));await settle();
   assert.equal(prefs.currentShowVideos(),true);
   for(const shown of ['Hidden video row','Video only card','Only videos section','Appended video','More videos'])assert.ok(text(host).includes(shown),shown+' returns');
   assert.ok((host.querySelector('.preview-content')?.textContent??'').includes('Suggested video'));
   assert.equal(calls.some(call=>call[0]==='loadMore'),false,'toggling never refetches');
  } finally {if(app)await unmount(app);host.remove();prefs.setShowVideos(true);}
 });
}

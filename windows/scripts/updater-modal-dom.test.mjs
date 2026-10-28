import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
if(!process.execArgv.includes('--conditions=browser')){
 test('mounted updater owns keyboard and focus only while open',()=>{
  const {NODE_TEST_CONTEXT,...env}=process.env;
  const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});assert.equal(result.status,0,result.stdout+result.stderr);
 });
}else{
 const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
 const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('updater-modal-dom');
 Object.defineProperty(dom.HTMLElement.prototype,'offsetParent',{configurable:true,get(){return this.parentElement;}});
 const Fixture=(await import(await moduleFor(path.join(root,'scripts/fixtures/UpdaterModal.svelte')))).default;
 const settle=async()=>{flushSync();await tick();await Promise.resolve();flushSync();};
 const key=(target,name,shiftKey=false)=>{const event=new KeyboardEvent('keydown',{key:name,shiftKey,bubbles:true,cancelable:true});target.dispatchEvent(event);flushSync();return event;};
 test('closed updater leaves Escape and Tab untouched, allowing Spotlight to dismiss and restore focus',async()=>{
  const host=document.createElement('div');document.body.append(host);let app;flushSync(()=>app=mount(Fixture,{target:host}));await settle();
  const opener=host.querySelector('[data-spotlight]');opener.focus();assert.equal(key(opener,'Tab').defaultPrevented,false);opener.click();await settle();
  assert.ok(host.querySelector('.spotlight'));assert.equal(document.activeElement,host.querySelector('.spotlight input'));
  const escape=key(document.activeElement,'Escape');await settle();assert.equal(escape.defaultPrevented,true);assert.equal(host.querySelector('.spotlight'),null);assert.equal(document.activeElement,opener);
  assert.equal(key(opener,'Escape').defaultPrevented,false);
  await unmount(app);host.remove();
 });
 test('each updater opening captures its actual opener; Tab stays scoped and installing cannot close',async()=>{
  const host=document.createElement('div');document.body.append(host);let app;flushSync(()=>app=mount(Fixture,{target:host}));await settle();
  const other=document.createElement('div');other.setAttribute('role','dialog');other.innerHTML='<button>Other dialog</button>';document.body.append(other);
  const opener=host.querySelector('[data-update]');opener.focus();opener.click();await settle();
  const dialog=host.querySelector('.dialog'),controls=[...dialog.querySelectorAll('button')];assert.equal(document.activeElement,controls[0]);
  controls.at(-1).focus();assert.equal(key(document.activeElement,'Tab').defaultPrevented,true);assert.equal(document.activeElement,controls[0]);
  key(document.activeElement,'Tab',true);assert.equal(document.activeElement,controls.at(-1));assert.notEqual(document.activeElement,other.querySelector('button'));
  key(document.activeElement,'Escape');await settle();assert.equal(host.querySelector('.dialog'),null);assert.equal(document.activeElement,opener);
  const installing=host.querySelector('[data-installing]');installing.focus();installing.click();await settle();assert.equal(document.activeElement,host.querySelector('.dialog'));
  key(document.activeElement,'Escape');await settle();assert.ok(host.querySelector('.dialog'));assert.equal(key(document.activeElement,'Tab').defaultPrevented,true);
  host.querySelector('[data-finish]').click();await settle();assert.equal(document.activeElement,installing);
  other.remove();await unmount(app);host.remove();
 });
}

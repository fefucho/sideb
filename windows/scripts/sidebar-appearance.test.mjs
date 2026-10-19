import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import ts from 'typescript';
import {compile} from 'svelte/compiler';
import {Window} from 'happy-dom';

if (!process.execArgv.includes('--conditions=browser')) {
  test('sidebar actions and independent Home appearance in mounted Svelte components', () => {
    const {NODE_TEST_CONTEXT,...env}=process.env;
    const run=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
    assert.equal(run.status,0,run.stdout+run.stderr);
    assert.match(run.stdout,/solid Home unmounts its ambient/);
  });
} else {
const root=fileURLToPath(new URL('../',import.meta.url)),cache=path.join(root,'.cache/sidebar-appearance-test');
await mkdir(cache,{recursive:true});
const modules=new Map();
async function moduleFor(filename) {
  if(modules.has(filename))return modules.get(filename);
  const target=path.join(cache,createHash('sha256').update(filename).digest('hex')+'.mjs'),url=pathToFileURL(target).href;
  modules.set(filename,url);
  const source=await readFile(filename,'utf8');
  let code=filename.endsWith('.json')?'export default '+source:filename.endsWith('.svelte')?compile(source,{filename,generate:'client',css:'external'}).js.code:ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
  for(const match of [...code.matchAll(/(?:from\s+|import\s*\()(['"])(\$lib\/[^'"]+|\.{1,2}\/[^'"]+)\1/g)]) {
    let resolved=match[2].startsWith('$lib/')?path.join(root,'src/lib',match[2].slice(5)):path.resolve(path.dirname(filename),match[2]);
    if(!path.extname(resolved)){try{await readFile(resolved+'.ts');resolved+='.ts';}catch{resolved=path.join(resolved,'index.ts');}}
    code=code.replaceAll(match[0],match[0].replace(match[2],await moduleFor(resolved)));
  }
  await writeFile(target,code);return url;
}
const dom=new Window({url:'http://localhost',settings:{disableJavaScriptFileLoading:true,disableJavaScriptEvaluation:true}});
for(const name of ['window','document','navigator','localStorage','Element','HTMLElement','HTMLInputElement','HTMLButtonElement','HTMLMediaElement','SVGElement','Node','Text','Comment','Event','MouseEvent','KeyboardEvent','MutationObserver','Image'])Object.defineProperty(globalThis,name,{configurable:true,value:name==='window'?dom:name==='document'?dom.document:dom[name]});
globalThis.requestAnimationFrame=dom.requestAnimationFrame.bind(dom);globalThis.cancelAnimationFrame=dom.cancelAnimationFrame.bind(dom);
globalThis.ResizeObserver=class {observe(){}unobserve(){}disconnect(){}};
const workers=[];
globalThis.Worker=class { constructor(url){this.url=String(url);this.terminated=false;workers.push(this);}postMessage(){}terminate(){this.terminated=true;} };
document.hasFocus=()=>false;
const {mount,unmount,flushSync,tick}=await import('svelte');
const {get}=await import('svelte/store');
const preferences=await import(await moduleFor(path.join(root,'src/lib/appearance/preferences.ts')));
const {appearance,appearanceKey,createAppearancePreferences}=preferences;
const {setLanguage}=await import(await moduleFor(path.join(root,'src/lib/i18n/index.ts')));setLanguage('en');
const {MENU_CONTEXT}=await import(await moduleFor(path.join(root,'src/lib/menu/types.ts')));
const {defaults}=await import(await moduleFor(path.join(root,'src/lib/home/settings.ts')));
const {default:Sidebar}=await import(await moduleFor(path.join(root,'src/lib/components/sidebar/Sidebar.svelte')));
const {default:HomeSettings}=await import(await moduleFor(path.join(root,'src/lib/components/home/HomeSettings.svelte')));
const {default:HomeBackground}=await import(await moduleFor(path.join(root,'src/lib/components/home/HomeBackground.svelte')));
const {default:HomeAmbient}=await import(await moduleFor(path.join(root,'src/lib/components/home/HomeAmbient.svelte')));
const settle=async()=>{await tick();flushSync();await tick();};
const click=async node=>{assert.ok(node);node.click();await settle();};
const ready={state:'ready',name:'Demo',handle:'@demo',email:null,thumbnail:null,message:null};
const card=(kind,id,title)=>({kind,id,title,subtitle:'Original metadata',thumbnail:null,duration:null});
function host(){const node=document.createElement('div');document.body.append(node);return node;}
function reset(){appearance.setHomeBackground('artwork');if(get(appearance).sidebarLayout==='grid')appearance.toggleSidebarLayout();setLanguage('en');}
function props(calls,extra={}) {return {activeDestination:'playlist',selectedCollectionId:'saved',auth:ready,collapsed:false,
  playlists:[card('playlist','saved','Original playlist')],albums:[card('album','saved','Original album')],
  onHome:()=>calls.push('home'),onLibrary:()=>calls.push('library'),onExplore:()=>calls.push('explore'),onSearch:()=>calls.push('search'),
  onLikes:()=>calls.push('likes'),onHistory:()=>calls.push('history'),onToggleSidebar:()=>calls.push('collapse'),onCreatePlaylist:()=>calls.push('create'),
  onOpenPlaylist:id=>calls.push('playlist:'+id),onOpenAlbum:id=>calls.push('album:'+id),onLogin:()=>calls.push('login'),onCancelLogin:()=>calls.push('cancel'),onLogout:()=>calls.push('logout'),onRetryLibrary:()=>calls.push('retry'),...extra};}

test('appearance survives recreation, rejects malformed/future values and works when storage is blocked',()=>{
  const values=new Map(),storage={getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value)};
  let store=createAppearancePreferences(storage);
  assert.deepEqual(get(store),{version:1,homeBackground:'artwork',sidebarLayout:'list'});
  store.setHomeBackground('solid');store.toggleSidebarLayout();store=createAppearancePreferences(storage);
  assert.deepEqual(get(store),{version:1,homeBackground:'solid',sidebarLayout:'grid'});
  assert.deepEqual(Object.keys(JSON.parse(values.get(appearanceKey))).sort(),['version','homeBackground','sidebarLayout'].sort());
  for(const value of ['broken',JSON.stringify({version:2,homeBackground:'solid'}),JSON.stringify({version:1,homeBackground:'unknown',sidebarLayout:'unknown'})]){
    values.set(appearanceKey,value);assert.deepEqual(get(createAppearancePreferences(storage)),{version:1,homeBackground:'artwork',sidebarLayout:'list'});
  }
  store=createAppearancePreferences({getItem(){throw Error('blocked');},setItem(){throw Error('blocked');}});
  store.setHomeBackground('solid');store.toggleSidebarLayout();assert.equal(get(store).homeBackground,'solid');assert.equal(get(store).sidebarLayout,'grid');
});

test('direct list/grid toggle retains row identity, focus, selection and collection tab without navigation',async()=>{
  reset();const calls=[],menus=[],node=host();
  const component=mount(Sidebar,{target:node,props:props(calls),context:new Map([[MENU_CONTEXT,{open:(...args)=>menus.push(args)}]])});await settle();
  try {
    assert.deepEqual([...node.querySelectorAll('.primary-section button')].map(button=>button.getAttribute('aria-label')),['Home','Library','Explore','Search']);
    const row=node.querySelector('.item-row'),toggle=node.querySelector('.layout-toggle');
    assert.equal(row.getAttribute('aria-current'),'page');toggle.focus();await click(toggle);
    assert.ok(node.querySelector('.collection-list.grid'));assert.equal(node.querySelector('.item-row'),row);assert.equal(document.activeElement,toggle);assert.equal(row.getAttribute('aria-current'),'page');assert.deepEqual(calls,[]);
    await click(node.querySelectorAll('.library-tabs button')[1]);assert.match(node.querySelector('.item-row').textContent,/Original album/);assert.equal(node.querySelector('.item-row').getAttribute('aria-current'),null);
    await click(toggle);assert.equal(node.querySelector('.collection-list.grid'),null);assert.equal(node.querySelectorAll('.library-tabs button')[1].getAttribute('aria-pressed'),'true');
    node.querySelector('.item-row').dispatchEvent(new dom.KeyboardEvent('keydown',{key:'F10',shiftKey:true,bubbles:true,cancelable:true}));assert.equal(menus.at(-1)[1].kind,'album');
    await click(node.querySelectorAll('.library-tabs button')[0]);await click(node.querySelector('.item-row'));assert.deepEqual(calls,['playlist:saved']);
    node.querySelector('.item-row').dispatchEvent(new dom.MouseEvent('contextmenu',{bubbles:true,cancelable:true}));assert.equal(menus.at(-1)[1].card.title,'Original playlist');
    for(const button of node.querySelectorAll('.primary-section button'))await click(button);
    for(const button of node.querySelectorAll('.collection-section button'))await click(button);
    await click(node.querySelector('.create-playlist'));assert.deepEqual(calls.slice(1),['home','library','explore','search','likes','history','create']);
  } finally {await unmount(component);node.remove();}
});

test('collapsed sidebar retains all six navigation actions and account keyboard dismissal',async()=>{
  reset();const calls=[],node=host();const component=mount(Sidebar,{target:node,props:props(calls,{collapsed:true})});await settle();
  try {
    assert.ok(node.querySelector('aside.collapsed'));for(const button of node.querySelectorAll('.primary-section button,.collection-section button'))await click(button);
    assert.deepEqual(calls,['home','library','explore','search','likes','history']);
    await click(node.querySelector('.profile'));assert.ok(node.querySelector('[role="dialog"]'));
    dom.dispatchEvent(new dom.KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}));await settle();assert.equal(node.querySelector('[role="dialog"]'),null);assert.equal(document.activeElement,node.querySelector('.profile'));
  } finally {await unmount(component);node.remove();}
});

test('appearance settings and sidebar toggle share one persisted collection view without changing recommendations',async()=>{
  reset();const calls=[],sidebarHost=host(),settingsHost=host();let changed=0;
  const sidebar=mount(Sidebar,{target:sidebarHost,props:props(calls)});
  const settings=mount(HomeSettings,{target:settingsHost,props:{settings:defaults(),kind:'albums',categories:[],libraryError:null,
    onChange:()=>changed++,onKind:()=>changed++,onRetryLibrary:()=>changed++,onClose(){}}});await settle();
  try {
    const picker=settingsHost.querySelector('#sidebar-layout-picker');
    assert.equal(picker.value,'list');picker.value='grid';picker.dispatchEvent(new dom.Event('change',{bubbles:true}));await settle();
    assert.ok(sidebarHost.querySelector('.collection-list.grid'));
    assert.equal(get(createAppearancePreferences(dom.localStorage)).sidebarLayout,'grid');
    await click(sidebarHost.querySelector('.layout-toggle'));assert.equal(picker.value,'list');
    assert.equal(sidebarHost.querySelector('.collection-list.grid'),null);
    assert.equal(get(createAppearancePreferences(dom.localStorage)).sidebarLayout,'list');
    assert.equal(changed,0);assert.deepEqual(calls,[]);
  } finally {await unmount(settings);await unmount(sidebar);settingsHost.remove();sidebarHost.remove();reset();}
});

test('guest/loading/error/empty collections keep recovery and never expose cached private rows',async()=>{
  for(const [extra,expected,action] of [[{auth:{...ready,state:'guest'}},'Sign in', 'login'],[{playlists:[],libraryLoading:true},'Loading',null],[{playlists:[],libraryError:'Recoverable library error'},'Recoverable library error','retry'],[{playlists:[]},'No playlists',null]]){
    reset();const calls=[],node=host();const component=mount(Sidebar,{target:node,props:props(calls,extra)});await settle();
    try {assert.match(node.querySelector('.scroll-region').textContent,new RegExp(expected,'i'));assert.equal(node.querySelector('.item-row'),null);await click(node.querySelector('.layout-toggle'));assert.deepEqual(calls,[]);if(action){await click(node.querySelector(action==='login'?'.profile':'.retry-library'));assert.ok(calls.includes(action));}}
    finally{await unmount(component);node.remove();}
  }
});

test('language changes preserve grid, selected album tab and original metadata',async()=>{
  reset();const node=host(),component=mount(Sidebar,{target:node,props:props([])});await settle();
  try {await click(node.querySelectorAll('.library-tabs button')[1]);await click(node.querySelector('.layout-toggle'));const row=node.querySelector('.item-row');setLanguage('es');await settle();assert.ok(node.querySelector('.collection-list.grid'));assert.equal(node.querySelector('.item-row'),row);assert.match(row.textContent,/Original album/);assert.equal(node.querySelector('.primary-section button').getAttribute('aria-label'),'Inicio');assert.equal(node.querySelector('.layout-toggle').getAttribute('aria-label'),'Mostrar como filas');}
  finally{await unmount(component);node.remove();reset();}
});

test('solid Home unmounts its ambient and persists through settings reopen, without changing recommendations or collection ambient',async()=>{
  reset();const backgroundHost=host(),settingsHost=host(),detailHost=host();let changed=0;
  const background=mount(HomeBackground,{target:backgroundHost,props:{artwork:[],session:'isolated-test',active:false}});
  const detail=mount(HomeAmbient,{target:detailHost,props:{artwork:[],session:'isolated-test',active:false,collection:true}});
  const settingsProps={settings:defaults(),kind:'albums',categories:[],libraryError:null,onChange:()=>changed++,onKind:()=>changed++,onRetryLibrary:()=>changed++,onClose(){}};
  let settings=mount(HomeSettings,{target:settingsHost,props:settingsProps});await settle();
  try {
    assert.ok(backgroundHost.querySelector('.ambient'));const paletteWorkers=workers.filter(worker=>worker.url.includes('ambient.worker'));const homeWorker=paletteWorkers.at(-2),detailWorker=paletteWorkers.at(-1);assert.ok(homeWorker&&detailWorker);
    const select=settingsHost.querySelector('#home-background-picker');select.value='solid';select.dispatchEvent(new dom.Event('change',{bubbles:true}));await settle();
    assert.ok(backgroundHost.querySelector('.home-solid'));assert.equal(backgroundHost.querySelector('.ambient'),null);assert.equal(homeWorker.terminated,true);assert.equal(detailWorker.terminated,false);assert.ok(detailHost.querySelector('.ambient.collection'));assert.equal(changed,0);
    await unmount(settings);settings=mount(HomeSettings,{target:settingsHost,props:settingsProps});await settle();assert.equal(settingsHost.querySelector('#home-background-picker').value,'solid');assert.equal(get(createAppearancePreferences(dom.localStorage)).homeBackground,'solid');
    const again=settingsHost.querySelector('#home-background-picker');again.value='artwork';again.dispatchEvent(new dom.Event('change',{bubbles:true}));await settle();assert.ok(backgroundHost.querySelector('.ambient'));assert.equal(backgroundHost.querySelector('.home-solid'),null);assert.equal(changed,0);
  } finally {await unmount(settings);await unmount(background);await unmount(detail);backgroundHost.remove();settingsHost.remove();detailHost.remove();}
});
}

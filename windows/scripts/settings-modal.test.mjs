import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

// PLAN-023 W8 (PAR-053): Settings modal mirrors Apple's SettingsModalView. Real Svelte components under happy-dom.
if(!process.execArgv.includes('--conditions=browser')){
  test('settings modal: categories, search, preserved preferences, keyboard and host services',()=>{
    const {NODE_TEST_CONTEXT,...env}=process.env;
    const run=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
    assert.equal(run.status,0,run.stdout+run.stderr);
    assert.match(run.stdout,/seven categories/);
  });
}else{
  const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
  const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('settings-modal');
  Object.defineProperty(globalThis,'localStorage',{configurable:true,value:dom.localStorage});
  Object.defineProperty(globalThis,'InputEvent',{configurable:true,value:dom.InputEvent});
  Object.defineProperty(globalThis,'HTMLSelectElement',{configurable:true,value:dom.HTMLSelectElement});
  const at=file=>moduleFor(path.join(root,'src/lib',file));
  const {setLanguage,text,preferenceKey}=await import(await at('i18n/index.ts'));
  const {defaults}=await import(await at('home/settings.ts'));
  const {appearance}=await import(await at('appearance/preferences.ts'));
  const {queuePreferences}=await import(await at('player/queuePreferences.ts'));
  const categories=await import(await at('components/settings/settingsCategories.ts'));
  const {default:HomeSettings}=await import(await at('components/home/HomeSettings.svelte'));
  const settle=async()=>{flushSync();await tick();await new Promise(r=>setTimeout(r,0));flushSync();await tick();};
  const click=async node=>{assert.ok(node,'control exists');node.click();await settle();};
  const key=(target,k,init={})=>{const event=new dom.KeyboardEvent('keydown',{key:k,bubbles:true,cancelable:true,...init});target.dispatchEvent(event);return event;};
  const open=(target,id)=>click(target.querySelector(`button.item[data-category="${id}"]`));
  const host=()=>{const node=document.createElement('div');document.body.append(node);return node;};
  const baseProps=(extra={})=>({settings:defaults(),kind:'albums',categories:[],libraryError:null,onChange(){},onKind(){},onRetryLibrary(){},onClose(){},...extra});
  async function withSettings(props,fn,context){
    setLanguage('en');const target=host();let app;
    flushSync(()=>{app=mount(HomeSettings,{target,props,...(context?{context}:{})});});await settle();
    try{await fn(target);}finally{await unmount(app);target.remove();setLanguage('en');}
  }

  test('seven categories keep Apple identifiers, sections and localized copy',()=>{
    const ids=categories.settingsCategories.map(c=>c.id);
    assert.deepEqual([...ids].sort(),['account','appearance','general','homeFeed','playback','shortcuts','visualProviders']);
    assert.equal(new Set(ids).size,7);
    assert.deepEqual(categories.settingsSections,['app','content','account']);
    const section=Object.fromEntries(categories.settingsCategories.map(c=>[c.id,c.section]));
    assert.deepEqual(section,{general:'app',playback:'app',appearance:'app',shortcuts:'app',homeFeed:'content',visualProviders:'content',account:'account'});
    for(const language of ['es','en'])for(const c of categories.settingsCategories){
      assert.ok(text(c.titleKey,[],language).length>0&&text(c.subtitleKey,[],language).length>0,`${c.id}/${language}`);
      assert.notEqual(text(c.subtitleKey,[],language),c.subtitleKey);
    }
    assert.deepEqual(categories.settingsSections.map(s=>text(categories.settingsSectionKey(s),[],'es')),['Aplicación','Contenido','Cuenta']);
    assert.deepEqual(categories.settingsSections.map(s=>text(categories.settingsSectionKey(s),[],'en')),['App','Content','Account']);
    const translate=key=>text(key,[],'es');
    assert.deepEqual(categories.matchingCategories('',translate).map(c=>c.id),ids);
    assert.deepEqual(categories.matchingCategories('ATAJOS',translate).map(c=>c.id),['shortcuts'],'case-insensitive title');
    assert.ok(categories.matchingCategories('reproduccion',translate).some(c=>c.id==='playback'),'diacritic-insensitive title');
    assert.ok(categories.matchingCategories('privacidad',translate).some(c=>c.id==='account'),'subtitle match');
    assert.deepEqual(categories.matchingCategories('zzzz',translate),[]);
  });

  test('modal exposes dialog semantics, grouped sidebar, one current category and large title',async()=>{
    await withSettings(baseProps(),async target=>{
      const dialog=target.querySelector('[role="dialog"]');
      assert.equal(dialog.getAttribute('aria-modal'),'true');assert.equal(dialog.getAttribute('aria-label'),'Settings');
      assert.equal(document.activeElement,target.querySelector('.close'),'initial focus lands on the close button');
      const nav=target.querySelector('nav');assert.ok(nav.getAttribute('aria-label'));
      assert.deepEqual([...nav.querySelectorAll('.section-title')].map(n=>n.textContent),['App','Content','Account']);
      assert.deepEqual([...nav.querySelectorAll('button.item')].map(n=>n.dataset.category),['general','playback','appearance','shortcuts','homeFeed','visualProviders','account']);
      assert.ok([...nav.querySelectorAll('button.item')].every(n=>n.querySelector('svg[aria-hidden="true"]')),'monochrome outline icon per item');
      assert.equal(nav.querySelectorAll('[aria-current="page"]').length,1);
      assert.equal(target.querySelector('h2').textContent,'General');
      for(const [id,title] of [['playback','Playback'],['appearance','Appearance'],['shortcuts','Keyboard Shortcuts'],['homeFeed','Home Feed'],['visualProviders','Visual Providers'],['account','Account']]){
        await open(target,id);assert.equal(target.querySelector('h2').textContent,title);
        assert.equal(nav.querySelector('[aria-current="page"]').dataset.category,id);
        assert.equal(target.querySelector('.content').dataset.category,id);
      }
      setLanguage('es');await settle();assert.deepEqual([...nav.querySelectorAll('.section-title')].map(n=>n.textContent),['Aplicación','Contenido','Cuenta']);
    });
  });

  test('sidebar search filters categories, reports no results, clears and keeps the open pane',async()=>{
    await withSettings(baseProps(),async target=>{
      const input=target.querySelector('input[type="search"]');
      const type=async value=>{input.value=value;input.dispatchEvent(new dom.Event('input',{bubbles:true}));await settle();};
      const items=()=>[...target.querySelectorAll('nav button.item')].map(n=>n.dataset.category);
      await type('short');assert.deepEqual(items(),['shortcuts']);assert.deepEqual([...target.querySelectorAll('.section-title')].map(n=>n.textContent),['App']);
      await type('session');assert.ok(items().includes('account'),'subtitle text is searchable');
      await type('qqqq');assert.deepEqual(items(),[]);assert.equal(target.querySelector('nav [role="status"]').textContent,'No results');
      assert.equal(target.querySelector('h2').textContent,'General','selected pane stays visible while filtering');
      await click(target.querySelector('.clear'));assert.equal(input.value,'');assert.equal(items().length,7);assert.equal(document.activeElement,input);
    });
    let closed=0;
    await withSettings(baseProps({onClose:()=>closed++}),async target=>{
      const input=target.querySelector('input[type="search"]');input.focus();input.value='abc';input.dispatchEvent(new dom.Event('input',{bubbles:true}));await settle();
      const escape=key(input,'Escape');await settle();assert.equal(escape.defaultPrevented,true);assert.equal(closed,0,'first Escape only clears the query');assert.equal(input.value,'');
      key(input,'Escape');await settle();assert.equal(closed,1);
    });
  });

  test('Escape, scrim click and close button dismiss; Tab is trapped inside the panel',async()=>{
    let closed=0;
    await withSettings(baseProps({onClose:()=>closed++}),async target=>{
      key(document.body,'Escape');await settle();assert.equal(closed,1);
      await click(target.querySelector('.close'));assert.equal(closed,2);
      const scrim=target.querySelector('.scrim'),panel=target.querySelector('.panel');
      panel.dispatchEvent(new dom.MouseEvent('click',{bubbles:true}));await settle();assert.equal(closed,2,'clicks inside never dismiss');
      scrim.dispatchEvent(new dom.MouseEvent('click',{bubbles:true}));await settle();assert.equal(closed,2,'a click without a scrim press is not a dismissal');
      scrim.dispatchEvent(new dom.Event('pointerdown',{bubbles:true}));scrim.dispatchEvent(new dom.MouseEvent('click',{bubbles:true}));await settle();assert.equal(closed,3);
      const focusables=[...panel.querySelectorAll('button:not(:disabled), input:not(:disabled), select:not(:disabled)')];
      focusables.at(-1).focus();const forward=key(focusables.at(-1),'Tab');assert.equal(forward.defaultPrevented,true);assert.equal(document.activeElement,focusables[0]);
      focusables[0].focus();const backward=key(focusables[0],'Tab',{shiftKey:true});assert.equal(backward.defaultPrevented,true);assert.equal(document.activeElement,focusables.at(-1));
      focusables[1].focus();const middle=key(focusables[1],'Tab');assert.equal(middle.defaultPrevented,false,'inner Tab keeps native order');
      const first=target.querySelector('nav button.item');first.focus();key(first,'ArrowDown');assert.equal(document.activeElement.dataset.category,'playback');
      key(document.activeElement,'End');assert.equal(document.activeElement.dataset.category,'account');key(document.activeElement,'Home');assert.equal(document.activeElement.dataset.category,'general');
    });
  });

  test('every preference that Settings offered before is still present and writes to the same stores',async()=>{
    queuePreferences.setSelection('advance');appearance.setHomeBackground('artwork');appearance.setAnimatedArtwork(true);
    const volume=[];
    await withSettings(baseProps({exponentialVolume:false,onExponentialVolume:v=>volume.push(v)}),async target=>{
      await open(target,'general');const lang=target.querySelector('select[aria-labelledby]');assert.equal(lang.value,'en');
      lang.value='es';lang.dispatchEvent(new dom.Event('change',{bubbles:true}));await settle();assert.equal(globalThis.localStorage.getItem(preferenceKey),'es');
      assert.equal(target.querySelector('h2').textContent,'General');assert.equal(target.querySelector('nav .section-title').textContent,'Aplicación','language switches copy without leaving the pane');
      lang.value='en';lang.dispatchEvent(new dom.Event('change',{bubbles:true}));await settle();
      await open(target,'playback');
      const queue=target.querySelector('#queue-recommendation-selection');assert.equal(queue.value,'advance');
      queue.value='play-only';queue.dispatchEvent(new dom.Event('change',{bubbles:true}));await settle();assert.equal(queuePreferences.currentSelection(),'play-only');
      const exp=target.querySelector('#exponential-volume-toggle');assert.equal(exp.getAttribute('role'),'switch');assert.equal(exp.getAttribute('aria-checked'),'false');
      assert.ok(exp.getAttribute('aria-labelledby'),'switch has an accessible name');
      await click(exp);assert.deepEqual(volume,[true]);assert.equal(exp.getAttribute('aria-checked'),'false','controlled: the native result decides');
      await open(target,'appearance');
      const toggle=target.querySelector('#animated-artwork-toggle');assert.equal(toggle.getAttribute('aria-checked'),'true');
      await click(toggle);assert.equal(toggle.getAttribute('aria-checked'),'false');
      await click(toggle);assert.equal(toggle.getAttribute('aria-checked'),'true');
      assert.ok(target.querySelector('#sidebar-layout-picker')&&target.querySelector('#home-background-picker'));
    });
    await withSettings(baseProps({exponentialVolume:true,volumeModePending:true,onExponentialVolume(){}}),async target=>{
      await open(target,'playback');const exp=target.querySelector('#exponential-volume-toggle');assert.equal(exp.getAttribute('aria-checked'),'true');assert.equal(exp.disabled,true);
    });
    await withSettings(baseProps(),async target=>{await open(target,'playback');assert.equal(target.querySelector('#exponential-volume-toggle'),null,'no audio group without a host callback');});
    queuePreferences.setSelection('advance');
  });

  test('Home feed keeps source/category ordering, visibility, restore and library recovery',async()=>{
    const changes=[],kinds=[];let retried=0;
    const cats=Array.from({length:10},(_,i)=>({key:'c'+i,title:'Shelf '+i}));
    const props=baseProps({categories:cats,libraryError:'x',onChange:s=>changes.push(s),onKind:k=>kinds.push(k),onRetryLibrary:()=>retried++});
    await withSettings(props,async target=>{
      await open(target,'homeFeed');
      assert.equal(target.querySelector('.content').dataset.category,'homeFeed');
      const kind=[...target.querySelectorAll('[aria-pressed]')];assert.deepEqual(kind.map(b=>b.getAttribute('aria-pressed')),['true','false']);
      await click(kind[1]);assert.deepEqual(kinds,['playlists']);
      const first=target.querySelector('.line');
      const name=first.querySelector('.name').textContent;
      const down=first.querySelector('button[aria-label^="Move"][aria-label$="down"]');await click(down);
      assert.equal(changes.at(-1).albumSources[1].source,props.settings.albumSources[0].source,'moving down swaps the first two sources');
      const sw=first.querySelector('[role="switch"]');assert.equal(sw.getAttribute('aria-checked'),String(props.settings.albumSources[0].enabled));
      await click(sw);assert.equal(changes.at(-1).albumSources[0].enabled,!props.settings.albumSources[0].enabled);
      assert.equal(first.querySelector('[role="switch"]').getAttribute('aria-labelledby'),first.querySelector('.name').id);assert.ok(name.length>0);
      assert.equal(first.querySelector('.handle').getAttribute('draggable'),'true');
      await click(target.querySelector('[role="alert"] + button, .note-row button'));assert.equal(retried,1);
      const before=changes.length;
      const buttons=[...target.querySelectorAll('.actions button')];
      await click(buttons.find(b=>b.textContent.includes('Restore sources')));assert.deepEqual(changes.at(-1).albumSources,defaults().albumSources);
      await click(buttons.find(b=>b.textContent.includes('Show all')));assert.deepEqual(changes.at(-1).hiddenCategoryKeys,[]);
      await click(buttons.find(b=>b.textContent.includes('YouTube order')));assert.equal(changes.at(-1).categoryOrderMode,'youtube');
      await click(buttons.find(b=>b.textContent.includes('Side B order')));assert.equal(changes.at(-1).categoryOrderMode,'sideB');
      assert.equal(changes.length,before+4);
      assert.ok(target.querySelector('input[type="search"][aria-label="Search categories"]'),'category filter appears above 8 categories');
      assert.ok(target.querySelector('footer, .footer'),'footer carries the order description');
    });
  });

  test('Home feed hides, reorders and filters categories without losing hidden state',async()=>{
    const changes=[];
    const cats=Array.from({length:3},(_,i)=>({key:'c'+i,title:'Shelf '+i}));
    const settings={...defaults(),hiddenCategoryKeys:['c1']};
    await withSettings(baseProps({categories:cats,settings,onChange:s=>changes.push(s)}),async target=>{
      await open(target,'homeFeed');
      assert.equal(target.querySelector('input[type="search"][aria-label="Search categories"]'),null,'few categories need no filter');
      const rows=()=>[...target.querySelectorAll('.line.category')];
      assert.equal(rows().length,3,'virtualized list renders its rows');
      const switches=rows().map(r=>r.querySelector('[role="switch"]'));
      assert.deepEqual(switches.map(s=>s.getAttribute('aria-checked')),['true','false','true']);
      await click(switches[1]);assert.deepEqual(changes.at(-1).hiddenCategoryKeys,[]);
      await click(switches[0]);assert.deepEqual(changes.at(-1).hiddenCategoryKeys,['c1','c0']);
      await click(rows()[2].querySelector('button[aria-label^="Move"][aria-label$="up"]'));
      assert.equal(changes.at(-1).categoryOrderMode,'custom');assert.deepEqual(changes.at(-1).categoryOrder.slice(0,3),['c0','c2','c1']);
    });
  });

  test('Account and Updates use host services; without a host nothing is invented',async()=>{
    const calls=[];
    const snapshot={state:{type:'idle'},currentVersion:'1.4.0',isModalOpen:false};
    const listeners=new Set();
    const updater={subscribe(fn){listeners.add(fn);fn(snapshot);return()=>listeners.delete(fn);},async checkForUpdates(manual){calls.push(['check',manual]);}};
    const state={auth:{state:'ready',name:'Demo',handle:'@demo',email:'d@example.test',thumbnail:null,message:null}};
    const service={get auth(){return state.auth;},updater,login:()=>calls.push('login'),cancelLogin:()=>calls.push('cancel'),logout:()=>calls.push('logout')};
    const context=new Map([[categories.SETTINGS_HOST_CONTEXT,service]]);
    await withSettings(baseProps(),async target=>{
      assert.match(target.textContent,/Installed: Side B 1\.4\.0/);
      const check=[...target.querySelectorAll('button')].find(b=>b.textContent.includes('Check for Updates'));await click(check);assert.deepEqual(calls,[['check',true]]);
      await open(target,'account');assert.match(target.textContent,/Demo/);assert.match(target.textContent,/@demo/);assert.match(target.textContent,/d@example\.test/);
      await click([...target.querySelectorAll('button')].find(b=>b.textContent.trim()==='Sign Out'));assert.equal(calls.at(-1),'logout');
      assert.match(target.textContent,/DPAPI/);
    },context);
    state.auth={state:'guest',name:null,email:null,thumbnail:null,message:null};
    await withSettings(baseProps(),async target=>{
      await open(target,'account');assert.match(target.textContent,/Guest Mode/);
      await click([...target.querySelectorAll('button')].find(b=>b.textContent.trim().startsWith('Sign In')));assert.equal(calls.at(-1),'login');
    },context);
    snapshot.state={type:'failed',message:'Network down'};
    await withSettings(baseProps(),async target=>{assert.match(target.textContent,/Network down/);},context);
    await withSettings(baseProps(),async target=>{
      assert.doesNotMatch(target.textContent,/Installed:/,'no updater, no update group');
      await open(target,'account');assert.doesNotMatch(target.textContent,/Sign In|Sign Out/);assert.match(target.textContent,/DPAPI/);
    });
  });

  test('shortcuts category lists only the shortcuts the Windows shell handles, with localized Space',async()=>{
    await withSettings(baseProps(),async target=>{
      await open(target,'shortcuts');
      const rows=[...target.querySelectorAll('.row')].map(r=>[r.querySelector('.title').textContent,[...r.querySelectorAll('kbd')].map(k=>k.textContent).join('+')]);
      assert.deepEqual(rows,[['Play / Pause','Space'],['Quick Search','Ctrl+K'],['New Playlist','Ctrl+N'],['History: Back','Alt+←'],['History: Forward','Alt+→'],['Window Fullscreen','F11'],['Close Window / Dismiss','Esc']]);
      setLanguage('es');await settle();assert.equal(target.querySelector('kbd').textContent,'Espacio');
    });
  });

  test('imported section components render inside their own groups and an empty one leaves no card',async()=>{
    await withSettings(baseProps(),async target=>{
      await open(target,'general');assert.ok(target.querySelector('.slot #search-show-videos'),'search videos section is hosted');
      assert.ok([...target.querySelectorAll('h3')].some(h=>h.textContent==='Search'),'group heading comes from Settings');
      await open(target,'playback');assert.ok(target.querySelector('.slot #sidebar-bottom-content'),'sidebar lyrics section is hosted');
      assert.ok([...target.querySelectorAll('h3')].some(h=>h.textContent==='Sidebar Player'),'sidebar lyrics heading is supplied by Settings');
      await open(target,'visualProviders');assert.ok(target.querySelector('.slot .provider'),'visual providers section is hosted');
      assert.equal(target.querySelector('.provider [role="switch"]'),null,'nothing installed in the synthetic environment');
    });
  });
}

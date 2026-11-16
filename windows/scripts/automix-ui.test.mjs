import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

// PLAN-024: Automix (beta). Native runtime owns the setting and the preparation; the UI mirrors it.
if(!process.execArgv.includes('--conditions=browser')){
  test('automix: controller, presentation, translations, fullscreen pill and settings switch',()=>{
    const {NODE_TEST_CONTEXT,...env}=process.env;
    const run=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
    assert.equal(run.status,0,run.stdout+run.stderr);
    assert.match(run.stdout,/fullscreen pill/);assert.match(run.stdout,/progress bar marker/);assert.match(run.stdout,/advanced options/);
  });
}else{
  const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
  const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('automix-ui');
  Object.defineProperty(globalThis,'localStorage',{configurable:true,value:dom.localStorage});
  const at=file=>moduleFor(path.join(root,'src/lib',file));
  const {setLanguage,text}=await import(await at('i18n/index.ts'));
  const automix=await import(await at('player/automix.ts'));
  const {default:AutomixPill}=await import(await at('components/fullscreen/AutomixPill.svelte'));
  const {default:PlaybackSettings}=await import(await at('components/settings/PlaybackSettings.svelte'));
  const {default:PlayerBar}=await import(await at('components/player/PlayerBar.svelte'));
  const settle=async()=>{flushSync();await tick();await new Promise(r=>setTimeout(r,0));flushSync();await tick();};
  const status=(extra={})=>({...automix.offAutomix(),enabled:true,phase:'idle',...extra});
  const host=()=>{const node=document.createElement('div');document.body.append(node);return node;};
  const tr=(key,args=[])=>text(key,args,'en');

  function harness(initial=automix.offAutomix()){
    const calls=[];let listener=null;let current=initial;let unlistened=0;let failNext=null;
    const rpc=async(command,args)=>{
      calls.push([command,args]);
      if(command==='set_automix_enabled'){if(failNext){const e=failNext;failNext=null;throw e;}current={...current,enabled:args.enabled,phase:args.enabled?'idle':'off'};}
      return current;
    };
    const listen=async(name,handler)=>{assert.equal(name,'automix-status-changed');listener=handler;return()=>{unlistened++;};};
    const snapshots=[];const controller=new automix.AutomixController(rpc,listen,snapshot=>snapshots.push(snapshot));
    return {controller,calls,snapshots,emit:payload=>listener({payload}),unlistened:()=>unlistened,fail:error=>{failNext=error;},set:value=>{current=value;}};
  }

  test('controller reads the native status, follows its events and never trusts a malformed payload',async()=>{
    const h=harness(status({phase:'ready',kind:'mix',bpmFrom:121.6,bpmTo:124.2,bars:8,stemsModel:true,markerSeconds:108}));
    assert.equal(h.controller.snapshot.status.phase,'off','off until the runtime answers');
    await h.controller.connect();await h.controller.connect();
    assert.deepEqual(h.calls,[['get_automix_status',undefined]]);
    assert.equal(h.controller.snapshot.status.phase,'ready');assert.equal(h.controller.snapshot.status.kind,'mix');assert.equal(h.controller.snapshot.status.markerSeconds,108);
    h.emit({enabled:true,phase:'mixing',kind:'cut',bpmFrom:0,bpmTo:null,bars:2,stemsModel:false,reason:null,markerSeconds:-4});
    assert.equal(h.controller.snapshot.status.phase,'mixing');assert.equal(h.controller.snapshot.status.bpmFrom,null,'no estimate is not a tempo');
    assert.equal(h.controller.snapshot.status.markerSeconds,null,'a negative marker is not a marker');
    h.emit({enabled:true,phase:'weird',kind:'nonsense',reason:'<script>',markerSeconds:'x'});
    assert.deepEqual([h.controller.snapshot.status.phase,h.controller.snapshot.status.kind,h.controller.snapshot.status.reason,h.controller.snapshot.status.markerSeconds],['idle',null,null,null]);
    h.emit(null);assert.equal(h.controller.snapshot.status.enabled,false);
    h.emit({enabled:false,phase:'ready'});assert.equal(h.controller.snapshot.status.phase,'off','off wins over a stale phase');
    h.emit({enabled:false,phase:'unavailable',reason:'jam'});
    assert.deepEqual([h.controller.snapshot.status.enabled,h.controller.snapshot.status.phase],[false,'unavailable'],'a Jam is reported even with the preference off');
    await h.controller.dispose();assert.equal(h.unlistened(),1);
  });

  test('toggle sends one request at a time, ignores events while pending and reports failure without flipping',async()=>{
    const h=harness();await h.controller.connect();
    const first=h.controller.setEnabled(true);const second=h.controller.setEnabled(true);
    assert.equal(h.controller.snapshot.pending,true);
    h.emit({enabled:false,phase:'off'});assert.equal(h.controller.snapshot.status.enabled,false);
    await Promise.all([first,second]);
    assert.equal(h.calls.filter(c=>c[0]==='set_automix_enabled').length,1);
    assert.deepEqual([h.controller.snapshot.status.enabled,h.controller.snapshot.pending,h.controller.snapshot.error],[true,false,null]);
    await h.controller.toggle();assert.equal(h.controller.snapshot.status.enabled,false,'toggle flips the setting');
    h.fail(new Error('no'));await h.controller.toggle();
    assert.equal(h.controller.snapshot.status.enabled,false,'a failed change leaves the last confirmed state');
    assert.equal(h.controller.snapshot.error,'no');assert.equal(h.controller.snapshot.pending,false);
    await h.controller.toggle();assert.equal(h.controller.snapshot.error,null,'the next attempt clears the error');
  });

  test('presentation uses the shared Mac texts for every state and reason, in both languages',()=>{
    const p=(extra,tx=tr)=>automix.automixPresentation(status(extra),tx);
    assert.deepEqual(automix.automixPresentation(automix.offAutomix(),tr),{text:'Off',tone:'off',on:false});
    assert.deepEqual(p({phase:'idle'}),{text:'On',tone:'neutral',on:true});
    assert.deepEqual(p({phase:'preparing'}),{text:'Preparing the mix…',tone:'busy',on:true});
    assert.equal(p({phase:'ready',kind:'mix',bpmFrom:121.6,bpmTo:124.2}).text,'Ready: mix (124 bpm)');
    assert.equal(p({phase:'ready',kind:'fade'}).text,'Ready: fade');
    assert.equal(p({phase:'mixing',kind:'cut'}).text,'Mixing: cut');assert.equal(p({phase:'mixing',kind:'cut'}).tone,'active');
    assert.equal(p({phase:'unavailable',reason:'late'}).text,'Not available: the mix was ready too late');
    assert.equal(p({phase:'idle',reason:'album'}).text,'Not available: songs of the same album');
    assert.equal(p({phase:'unavailable',reason:'load'}).text,'Not available: the mix could not be prepared');
    assert.equal(p({phase:'unavailable',reason:'album'}).on,true,'blocked for this song, but still switched on');
    assert.equal(automix.automixPresentation(automix.offAutomix(),(k,a)=>text(k,a,'es')).text,'Desactivado');
    const reasons={'no-next':'noNextTrack',album:'sameAlbum','same-song':'sameTrack',jam:'jam',repeat:'repeatOne','unsupported-format':'unsupportedFormat','too-long':'tooLong',late:'tooLate',failed:'failed',load:'failed',resolve:'failed'};
    for(const reason of Object.keys(reasons))for(const language of ['es','en']){
      const value=automix.automixPresentation(status({phase:'unavailable',reason}),(k,a)=>text(k,a,language)).text;
      assert.notEqual(value,`automix.unavailable.${reasons[reason]}`,`${reason}/${language} is translated`);assert.match(value,language==='es'?/No disponible/:/Not available/);
    }
    // Status, kind, reason, pill and marker wording are the shared Mac keys; only the new options are Windows keys.
    const resources=JSON.parse(readFileSync(path.join(root,'src/lib/i18n/windows.json'),'utf8'));
    const own=Object.keys(resources).filter(k=>k.startsWith('windows.automix.'));
    assert.ok(own.includes('windows.automix.error'));
    assert.deepEqual(own.filter(k=>/^windows\.automix\.(status|kind|reason|pill|detail)/.test(k)),[],'nothing the Mac keys already say');
    assert.equal(text('automix.pill.title',[],'es'),'Beta · Automix');
  });

  test('a Jam forces Automix off in the UI and keeps the saved preference',()=>{
    const on=status({phase:'ready',kind:'mix',bpmTo:120,markerSeconds:108});
    const jam=automix.automixWithJam(on,true);
    assert.deepEqual([jam.enabled,jam.phase,jam.reason,jam.markerSeconds,jam.kind],[true,'unavailable','jam',null,null]);
    assert.equal(automix.automixBlockedByJam(jam),true);
    assert.equal(automix.automixWithJam(on,false),on,'outside a Jam nothing changes');
    assert.deepEqual(automix.automixPresentation(jam,tr),{text:'Not available in Jam',tone:'warning',on:false});
    assert.equal(automix.automixWithJam(automix.offAutomix(),true).enabled,false);
    assert.equal(automix.automixBlockedByJam(status({phase:'unavailable',reason:'album'})),false);
  });

  test('progress bar marker mapping matches the Mac rules',()=>{
    const f=automix.automixMarkerFraction;
    assert.equal(f(108,216),0.5);assert.equal(f(108,432),0.25);
    for(const duration of [0,NaN,Infinity,-5,108,100])assert.equal(f(108,duration),null,`duration ${duration}`);
    assert.notEqual(f(108,108.001),null);assert.equal(f(0,200),0);
    for(const seconds of [null,undefined,NaN,-3,Infinity])assert.equal(f(seconds,200),null,`seconds ${seconds}`);
    const l=automix.automixMarkerLayout;
    assert.deepEqual(l(150,200,400),{tickX:300,segmentWidth:100});
    const geometry=l(150,200,400);assert.equal(geometry.tickX+geometry.segmentWidth,400);
    assert.equal(l(150,200,0),null);assert.equal(l(150,100,400),null);
    assert.equal(l(156,210,210).tickX,156,'a chained song uses its own shown duration');
  });

  async function withPill(props,fn){
    setLanguage('en');const target=host();let app;
    flushSync(()=>{app=mount(AutomixPill,{target,props});});await settle();
    try{await fn(target);}finally{await unmount(app);target.remove();}
  }

  test('fullscreen pill is a labelled switch that shows the state and toggles the setting',async()=>{
    let toggles=0;
    await withPill({status:automix.offAutomix(),onToggle(){toggles++;}},async target=>{
      const button=target.querySelector('button[data-automix-pill]');
      assert.equal(button.getAttribute('role'),'switch');assert.equal(button.getAttribute('aria-checked'),'false');
      assert.equal(button.getAttribute('aria-label'),'Beta · Automix');assert.equal(button.textContent.trim(),'Beta · Automix');
      assert.equal(button.title,'Beta · Automix: Off. Turn on Automix (beta)');
      const described=target.querySelector('#'+button.getAttribute('aria-describedby'));assert.equal(described.textContent,'Off. Turn on Automix (beta)');
      button.click();await settle();assert.equal(toggles,1);
    });
    await withPill({status:status({phase:'ready',kind:'mix',bpmFrom:120,bpmTo:126}),onToggle(){}},async target=>{
      const button=target.querySelector('button[data-automix-pill]');
      assert.equal(button.getAttribute('aria-checked'),'true');assert.equal(button.dataset.tone,'ready');
      assert.equal(button.title,'Beta · Automix: Ready: mix (126 bpm). Turn off Automix (beta)');
    });
    await withPill({status:status({phase:'unavailable',reason:'unsupported-format'}),pending:true,onToggle(){}},async target=>{
      const button=target.querySelector('button[data-automix-pill]');
      assert.equal(button.disabled,true);assert.equal(button.getAttribute('aria-busy'),'true');
      assert.match(button.title,/the audio is not AAC/);
      setLanguage('es');await settle();assert.match(button.title,/^Beta · Automix: No disponible: el audio no es AAC/);
    });
    // A Jam: visible but disabled, saying why, with the preference left as it was.
    let jamToggles=0;
    await withPill({status:automix.automixWithJam(status({phase:'ready',kind:'mix'}),true),onToggle(){jamToggles++;}},async target=>{
      const button=target.querySelector('button[data-automix-pill]');
      assert.equal(button.disabled,true);button.click();await settle();assert.equal(jamToggles,0);
      assert.equal(button.title,'Beta · Automix: Not available in Jam. Not available in Jam');
      assert.equal(button.getAttribute('aria-checked'),'false');
    });
  });

  test('settings switch is off by default, describes the model download, sends the change and is disabled in a Jam',async()=>{
    const changes=[];
    const mountSettings=async(props,fn)=>{
      setLanguage('en');const target=host();let app;
      flushSync(()=>{app=mount(PlaybackSettings,{target,props:{exponentialVolume:false,volumeModePending:false,...props}});});await settle();
      try{await fn(target);}finally{await unmount(app);target.remove();}
    };
    await mountSettings({automix:automix.offAutomix(),onAutomix:value=>changes.push(value)},async target=>{
      const toggle=target.querySelector('#automix-toggle');
      assert.equal(toggle.getAttribute('aria-checked'),'false');assert.equal(toggle.disabled,false);
      assert.ok([...target.querySelectorAll('h3')].some(h=>h.textContent==='Automix (beta)'));
      assert.match(target.textContent,/210 MB/);assert.match(target.textContent,/AAC/);assert.match(target.textContent,/Jam/);
      assert.equal(target.querySelector('.automix-state'),null,'nothing to report while it is off');
      toggle.click();await settle();assert.deepEqual(changes,[true]);
    });
    await mountSettings({automix:automix.automixWithJam(status({phase:'idle'}),true),onAutomix:value=>changes.push(value)},async target=>{
      const toggle=target.querySelector('#automix-toggle');
      assert.equal(toggle.disabled,true);assert.equal(toggle.getAttribute('aria-checked'),'true','the saved preference is shown unchanged');
      assert.equal(target.querySelector('.automix-state').textContent,'Not available in Jam');
      toggle.click();await settle();assert.deepEqual(changes,[true],'no change is sent during a Jam');
    });
    // Without the native runtime (older host) the row is simply absent.
    await mountSettings({},async target=>{assert.equal(target.querySelector('#automix-toggle'),null);});
  });

  test('progress bar marker is decorative: same track, hint and accessible description, gone without a mix',async()=>{
    const playback=(extra={})=>({isPlaying:true,isLoading:false,isEnded:false,isShuffle:false,isRepeat:false,position:30,duration:216,volume:80,
      currentTrack:{videoId:'a',title:'A',artists:'X',thumbnail:null,duration:216},error:null,generation:1,
      queue:{items:[],currentIndex:null,source:null,revision:0},...extra});
    const noop=()=>{};
    const mountBar=async(props,fn)=>{
      setLanguage('en');const target=host();let app;
      flushSync(()=>{app=mount(PlayerBar,{target,props:{playback:playback(),onTogglePlayback:noop,onRetryPlayback:noop,onPrevious:noop,onNext:noop,onSeek:noop,onVolumeChange:noop,
        onSetShuffle:async()=>{},onSetRepeat:async()=>{},fullscreenOpen:false,onToggleFullscreen:noop,...props}});});await settle();
      try{await fn(target);}finally{await unmount(app);target.remove();}
    };
    for(const variant of ['bar','sidebar'])await mountBar({variant,automixMarker:108},async target=>{
      const seek=target.querySelector('input.seek');
      assert.ok(seek.classList.contains('has-mark'),variant);assert.match(seek.getAttribute('style'),/--mark:\s*50%/);
      assert.equal(seek.title,'Automix: the mix starts here (1:48)');
      assert.equal(seek.getAttribute('aria-valuetext'),'0:30 / 3:36. Automix: the mix starts here (1:48)');
      assert.equal(seek.type,'range');assert.equal(seek.disabled,false);assert.equal(seek.max,'216');assert.equal(seek.step,'0.25');
      setLanguage('es');await settle();assert.equal(seek.title,'Automix: la mezcla empieza acá (1:48)');
    });
    for(const marker of [null,undefined,250,216,-1])await mountBar({automixMarker:marker},async target=>{
      const seek=target.querySelector('input.seek');
      assert.ok(!seek.classList.contains('has-mark'),`marker ${marker}`);assert.doesNotMatch(seek.getAttribute('style'),/--mark/);
      assert.equal(seek.getAttribute('title'),null);assert.equal(seek.getAttribute('aria-valuetext'),null);
    });
    // Seeking is untouched: the same change still reaches the handler.
    const seeks=[];
    await mountBar({automixMarker:108,onSeek:v=>seeks.push(v)},async target=>{
      const seek=target.querySelector('input.seek');seek.value='100';
      seek.dispatchEvent(new dom.Event('change',{bubbles:true}));await settle();
      assert.deepEqual(seeks,[100]);
    });
  });

  const optionsPayload=(over={})=>({
    settings:{quality:'auto',fastOnBattery:true,skipSameAlbum:true,compute:'auto',lookahead:1,keepModelLoaded:false,...(over.settings??{})},
    capability:{modelReady:true,modelDownloading:false,realtimeFactor:5.57,stemsRecommended:true,provider:'DirectML',...(over.capability??{})},
    cache:{audioBytes:48*1048576,stemsBytes:70*1048576,transitionsBytes:2*1048576,modelBytes:210*1048576,...(over.cache??{})},
  });

  function optionsHarness(initial=optionsPayload()){
    const calls=[];let current=initial;let failNext=null;let failAll=null;let listener=null;
    const rpc=async(command,args)=>{
      calls.push([command,args]);
      if(failAll)throw failAll;
      if(failNext){const e=failNext;failNext=null;throw e;}
      if(command==='set_automix_options')current={...current,settings:{...args.settings,lookahead:Math.min(3,Math.max(1,args.settings.lookahead))}};
      if(command==='clear_automix_cache')current={...current,cache:{...current.cache,audioBytes:0,stemsBytes:0,transitionsBytes:0}};
      if(command==='delete_automix_model')current={...current,capability:{...current.capability,modelReady:false},cache:{...current.cache,modelBytes:0}};
      if(command==='get_automix_status')return {enabled:true,phase:'idle'};
      return current;
    };
    const listen=async(name,handler)=>{listener=handler;return()=>{};};
    let notify=null;const snapshots=[];const controller=new automix.AutomixController(rpc,listen,snapshot=>{snapshots.push(snapshot);notify?.(snapshot);});
    return {controller,calls,snapshots,subscribe:fn=>{notify=fn;},fail:e=>{failNext=e;},failAll:e=>{failAll=e;},set:v=>{current=v;}};
  }

  test('advanced options: normalization, byte formatting and the capability description',()=>{
    assert.equal(automix.normalizeAutomixOptions(null),null);assert.equal(automix.normalizeAutomixOptions({}),null);
    const clean=automix.normalizeAutomixOptions({settings:{quality:'best',fastOnBattery:'yes',compute:'tpu',lookahead:9,keepModelLoaded:true,skipSameAlbum:false},capability:{realtimeFactor:-1,provider:7},cache:{audioBytes:'x',stemsBytes:-5,modelBytes:1048576}});
    assert.deepEqual(clean.settings,{quality:'auto',fastOnBattery:true,skipSameAlbum:false,compute:'auto',lookahead:3,keepModelLoaded:true});
    assert.deepEqual(clean.capability,{modelReady:false,modelDownloading:false,realtimeFactor:null,stemsRecommended:false,provider:''});
    assert.deepEqual(clean.cache,{audioBytes:0,stemsBytes:0,transitionsBytes:0,modelBytes:1048576});
    assert.equal(automix.normalizeAutomixOptions({settings:{lookahead:0}}).settings.lookahead,1);
    assert.deepEqual(['0 MB','1.0 MB','48.2 MB','210 MB','1.3 GB'],[0,1048576,48.2*1048576,210*1048576,1.3*1073741824].map(automix.formatBytes));
    assert.equal(automix.formatBytes(NaN),'0 MB');
    assert.deepEqual(automix.describeCapability(optionsPayload().capability),{model:'ready',provider:'DirectML',speed:'5.6',recommended:true});
    assert.deepEqual(automix.describeCapability({modelReady:false,modelDownloading:true,realtimeFactor:null,stemsRecommended:false,provider:''}),{model:'downloading',provider:null,speed:null,recommended:false});
    assert.equal(automix.describeCapability({modelReady:false,modelDownloading:false,realtimeFactor:null,stemsRecommended:false,provider:''}).model,'missing');
    // The status carries the quality of the ready file.
    assert.equal(automix.normalizeAutomix({enabled:true,phase:'ready',kind:'mix',quality:'stems'}).quality,'stems');
    assert.equal(automix.normalizeAutomix({enabled:true,phase:'ready',kind:'mix',quality:'ultra'}).quality,null);
  });

  test('advanced options controller reads, sends the merged settings, and keeps the last good value on failure',async()=>{
    const h=optionsHarness();
    assert.equal(h.controller.snapshot.options,null,'nothing until the runtime answers');
    await h.controller.updateSettings({quality:'fast'});assert.equal(h.calls.length,0,'nothing to merge into yet');
    await h.controller.refreshOptions();
    assert.equal(h.controller.snapshot.options.settings.quality,'auto');
    await h.controller.updateSettings({quality:'stems'});
    assert.deepEqual(h.calls.at(-1),['set_automix_options',{settings:{quality:'stems',fastOnBattery:true,skipSameAlbum:true,compute:'auto',lookahead:1,keepModelLoaded:false}}]);
    assert.equal(h.controller.snapshot.options.settings.quality,'stems');
    await h.controller.updateSettings({lookahead:9});assert.equal(h.controller.snapshot.options.settings.lookahead,3,'the core corrects what is out of range');
    h.fail(new Error('boom'));await h.controller.updateSettings({compute:'cpu'});
    assert.equal(h.controller.snapshot.options.settings.compute,'auto','a failed change leaves the confirmed value');
    assert.equal(h.controller.snapshot.optionsError,'boom');
    await h.controller.updateSettings({compute:'cpu'});assert.equal(h.controller.snapshot.optionsError,null);assert.equal(h.controller.snapshot.options.settings.compute,'cpu');
    await h.controller.clearCache();assert.equal(h.controller.snapshot.options.cache.audioBytes,0);assert.equal(h.calls.at(-1)[0],'clear_automix_cache');
    await h.controller.deleteModel();assert.equal(h.controller.snapshot.options.capability.modelReady,false);assert.equal(h.calls.at(-1)[0],'delete_automix_model');
    h.set({nonsense:true});await h.controller.deleteModel();
    assert.ok(h.controller.snapshot.optionsError,'an invalid answer is an error, not a broken page');
    // A refresh that fails (older host) is silent.
    const old=optionsHarness();old.fail(new Error('unknown command'));await old.controller.refreshOptions();
    assert.equal(old.controller.snapshot.options,null);assert.equal(old.controller.snapshot.optionsError,null);
    // One request at a time.
    const busy=optionsHarness();await busy.controller.refreshOptions();
    const first=busy.controller.updateSettings({fastOnBattery:false});const second=busy.controller.updateSettings({skipSameAlbum:false});await Promise.all([first,second]);
    assert.equal(busy.calls.filter(c=>c[0]==='set_automix_options').length,1);
  });

  // Like the page: the host's snapshot is reactive state fed by the controller's publish callback.
  const harnessSource=`<script>
    import { setContext } from 'svelte';
    import PlaybackSettings from '$lib/components/settings/PlaybackSettings.svelte';
    import { AUTOMIX_HOST_CONTEXT } from '$lib/components/settings/automixHost';
    let { harness, props } = $props();
    let snapshot = $state(harness.controller.snapshot);
    harness.subscribe(next => { snapshot = next; });
    setContext(AUTOMIX_HOST_CONTEXT, { get snapshot() { return snapshot; }, controller: harness.controller });
  </script>
  <PlaybackSettings {...props} />`;
  const {default:Harness}=await import(await moduleFor(path.join(root,'src/lib/components/settings/AutomixHarness.svelte'),harnessSource));
  async function withAdvanced(h,fn,props={}){
    setLanguage('en');await h.controller.refreshOptions();
    const target=host();let app;
    flushSync(()=>{app=mount(Harness,{target,props:{harness:h,props:{exponentialVolume:false,volumeModePending:false,automix:status({phase:'idle'}),onAutomix(){},...props}}});});await settle();
    try{await fn(target);}finally{await unmount(app);target.remove();}
  }
  const choose=async(select,value)=>{select.value=value;select.dispatchEvent(new dom.Event('change',{bubbles:true}));await settle();};

  test('advanced options section: quality, battery and album rules, processor, lookahead, model memory, capability and cache',async()=>{
    const h=optionsHarness();
    await withAdvanced(h,async target=>{
      const texts=[...target.querySelectorAll('.title')].map(n=>n.textContent);
      for(const label of ['Quality','On battery, use only the fast version',"Don't mix consecutive songs from the same album",'Processor','Prepare ahead','Keep the model loaded','This computer','Disk space'])assert.ok(texts.includes(label),label);
      assert.ok([...target.querySelectorAll('h3')].some(x=>x.textContent==='Automix options'));
      assert.equal(target.querySelector('details.advanced summary').textContent,'Advanced');
      const quality=target.querySelector('#automix-quality');
      assert.deepEqual([...quality.options].map(o=>o.textContent),['Automatic (recommended)','Always fast','Always with stems']);
      assert.equal(quality.value,'auto');
      assert.equal(target.querySelector('#automix-fast-on-battery').getAttribute('aria-checked'),'true');
      assert.equal(target.querySelector('#automix-skip-same-album').getAttribute('aria-checked'),'true');
      assert.equal(target.querySelector('#automix-keep-model').getAttribute('aria-checked'),'false');
      assert.deepEqual([...target.querySelector('#automix-compute').options].map(o=>o.textContent),['Automatic','GPU','CPU']);
      assert.deepEqual([...target.querySelector('#automix-lookahead').options].map(o=>o.textContent),['1 song','2 songs','3 songs']);
      assert.match(target.textContent,/Model downloaded · Processor: DirectML · 5\.6× audio speed · stems recommended/);
      assert.match(target.textContent,/Songs 48\.0 MB · Stems 70\.0 MB · Transitions 2\.0 MB · Model 210 MB/);
      assert.match(target.textContent,/2 GB of memory/);
      // Each control sends the whole settings object with just its own change.
      await choose(quality,'stems');assert.equal(h.calls.at(-1)[1].settings.quality,'stems');
      target.querySelector('#automix-fast-on-battery').click();await settle();assert.equal(h.calls.at(-1)[1].settings.fastOnBattery,false);
      target.querySelector('#automix-skip-same-album').click();await settle();assert.equal(h.calls.at(-1)[1].settings.skipSameAlbum,false);
      await choose(target.querySelector('#automix-compute'),'cpu');assert.equal(h.calls.at(-1)[1].settings.compute,'cpu');
      await choose(target.querySelector('#automix-lookahead'),'3');assert.equal(h.calls.at(-1)[1].settings.lookahead,3);
      target.querySelector('#automix-keep-model').click();await settle();assert.equal(h.calls.at(-1)[1].settings.keepModelLoaded,true);
      assert.deepEqual(h.controller.snapshot.options.settings,{quality:'stems',fastOnBattery:false,skipSameAlbum:false,compute:'cpu',lookahead:3,keepModelLoaded:true});
      setLanguage('es');await settle();
      assert.ok([...target.querySelectorAll('.title')].some(n=>n.textContent==='No mezclar canciones seguidas del mismo disco'));
      assert.equal(target.querySelector('details.advanced summary').textContent,'Avanzado');
    });
  });

  test('clearing the cache and deleting the model ask for confirmation first and can be cancelled',async()=>{
    const h=optionsHarness();
    await withAdvanced(h,async target=>{
      const clear=()=>target.querySelector('#automix-clear-cache'),model=()=>target.querySelector('#automix-delete-model');
      assert.equal(clear().disabled,false);assert.equal(model().disabled,false);
      clear().click();await settle();
      assert.equal(h.calls.filter(c=>c[0]==='clear_automix_cache').length,0,'nothing is deleted by the first press');
      const dialog=target.querySelector('[role="alertdialog"]');assert.equal(dialog.getAttribute('aria-label'),'Clear the Automix cache?');
      [...dialog.querySelectorAll('button')].find(b=>b.textContent.trim()==='Cancel').click();await settle();
      assert.equal(target.querySelector('[role="alertdialog"]'),null);assert.equal(h.calls.filter(c=>c[0]==='clear_automix_cache').length,0);
      clear().click();await settle();
      [...target.querySelectorAll('[role="alertdialog"] button')].find(b=>b.textContent.trim()==='Delete').click();await settle();
      assert.equal(h.calls.filter(c=>c[0]==='clear_automix_cache').length,1);
      assert.match(target.textContent,/Songs 0 MB · Stems 0 MB · Transitions 0 MB/);assert.equal(clear().disabled,true,'nothing left to clear');
      model().click();await settle();
      assert.match(target.querySelector('[role="alertdialog"]').getAttribute('aria-label'),/Delete the model/);
      [...target.querySelectorAll('[role="alertdialog"] button')].find(b=>b.textContent.trim()==='Delete').click();await settle();
      assert.equal(h.calls.filter(c=>c[0]==='delete_automix_model').length,1);
      assert.equal(model().disabled,true,'no model left');assert.match(target.textContent,/Model not downloaded/);
    });
  });

  test('advanced options stay hidden without the runtime, show an error, and describe a model that is downloading',async()=>{
    const old=optionsHarness();old.failAll(new Error('unknown command'));
    await withAdvanced(old,async target=>{assert.ok(!target.querySelector('#automix-quality'),'no section without the runtime');assert.ok(!target.querySelector('details.advanced'));
      assert.ok(target.querySelector('#automix-toggle'),'the toggle itself is unaffected');});
    const downloading=optionsHarness(optionsPayload({capability:{modelReady:false,modelDownloading:true,realtimeFactor:null,stemsRecommended:false,provider:''}}));
    await withAdvanced(downloading,async target=>{
      assert.match(target.textContent,/Downloading the model… · Processor not determined yet · speed not measured · stems not recommended/);
      assert.equal(target.querySelector('#automix-delete-model').disabled,true);
    });
    const failing=optionsHarness();
    await withAdvanced(failing,async target=>{
      failing.fail(new Error('no'));await choose(target.querySelector('#automix-quality'),'fast');
      assert.match(target.textContent,/Couldn't save the Automix setting\./);
      assert.equal(target.querySelector('#automix-quality').value,'auto','still the confirmed value');
    });
    // Without the controller context (older shell) nothing renders and nothing breaks.
    setLanguage('en');const bare=host();let app;
    flushSync(()=>{app=mount(PlaybackSettings,{target:bare,props:{exponentialVolume:false,volumeModePending:false,automix:status({phase:'idle'}),onAutomix(){}}});});await settle();
    try{assert.equal(bare.querySelector('#automix-quality'),null);}finally{await unmount(app);bare.remove();}
  });
}

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
    assert.match(run.stdout,/fullscreen pill/);assert.match(run.stdout,/progress bar marker/);
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
    // Nothing duplicates a shared text: the only Windows-specific automix string is the failure toast.
    const resources=JSON.parse(readFileSync(path.join(root,'src/lib/i18n/windows.json'),'utf8'));
    assert.deepEqual(Object.keys(resources).filter(k=>k.includes('automix')),['windows.automix.error']);
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
}

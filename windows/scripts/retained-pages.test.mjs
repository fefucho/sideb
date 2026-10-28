import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

if(!process.execArgv.includes('--conditions=browser')) {
  test('retained pages preserve their DOM, independent scroll and draft while suspending hidden work',()=>{
    const {NODE_TEST_CONTEXT,...env}=process.env;
    const result=spawnSync(process.execPath,['--conditions=browser','--test',fileURLToPath(import.meta.url)],{encoding:'utf8',env});
    assert.equal(result.status,0,result.stdout+result.stderr);
  });
} else {
  const {mountedSvelteEnvironment}=await import('./helpers/mount-svelte.mjs');
  const {root,dom,moduleFor,mount,unmount,flushSync,tick}=await mountedSvelteEnvironment('retained-pages-test');
  const settle=async()=>{flushSync();await tick();flushSync();};
  await moduleFor(path.join(root,'scripts/fixtures/RetainedChild.svelte'),`<script>
    import {onMount} from 'svelte';
    import VirtualStack from '$lib/components/common/VirtualStack.svelte';
    let {id,active}=$props();let draft=$state('');
    const items=Array.from({length:2000},(_,i)=>i);
    onMount(()=>{globalThis.__retainedMounts++;});
  </script><input data-draft={id} bind:value={draft}/><VirtualStack {items} {active} key={i=>String(i)} height={()=>58}>{#snippet children(item)}<p>{item}</p>{/snippet}</VirtualStack>`);
  const Fixture=(await import(await moduleFor(path.join(root,'scripts/fixtures/RetainedFixture.svelte'),`<script>
    import RetainedPage from '$lib/components/shell/RetainedPage.svelte';
    import Child from './RetainedChild.svelte';
    let selected=$state('feed'),covered=$state(false),session=$state(0);
    export function select(id){selected=id;}
    export function cover(value){covered=value;}
    export function account(){session++;}
  </script><div class="content-column">{#key session}{#each ['feed','library','search_results','explore'] as id}<RetainedPage {id} selected={id===selected} {covered}>{#snippet children(active)}<Child {id} {active}/>{/snippet}</RetainedPage>{/each}{/key}</div>`))).default;

  test('ten navigation cycles retain identity and offsets; covered visuals have no observers; account purges',async()=>{
    globalThis.__retainedMounts=0;
    const observers=new Set();
    Object.defineProperty(globalThis,'ResizeObserver',{configurable:true,value:class {
      constructor(callback){this.callback=callback;}
      observe(){observers.add(this);}
      disconnect(){observers.delete(this);}
    }});
    const target=document.createElement('div');document.body.append(target);
    let app;
    try {
      app=mount(Fixture,{target});await settle();
      const page=id=>target.querySelector(`[data-retained-page="${id}"]`);
      assert.equal(globalThis.__retainedMounts,1,'unvisited destinations are lazy');
      const home=page('feed'),input=home.querySelector('input');
      input.value='draft retained';input.dispatchEvent(new dom.Event('input',{bubbles:true}));
      home.scrollTop=540;home.dispatchEvent(new dom.Event('scroll'));await settle();
      assert.equal(observers.size,1);
      app.cover(true);await settle();
      assert.equal(home.hidden,false,'translucent coverage keeps selected pixels');
      assert.equal(home.inert,true);assert.equal(home.getAttribute('aria-hidden'),'true');
      assert.equal(observers.size,0,'inactive virtual list detaches resize subscriptions');
      app.cover(false);await settle();assert.equal(observers.size,1);
      for(let i=0;i<10;i++){
        app.select('library');await settle();
        const library=page('library');library.scrollTop=70+i;library.dispatchEvent(new dom.Event('scroll'));
        assert.equal(home.hidden,true);assert.equal(home.inert,true);
        assert.equal(observers.size,1);
        app.select('feed');await settle();
        assert.equal(page('feed'),home);assert.equal(home.querySelector('input'),input);
        assert.equal(home.scrollTop,540);assert.equal(input.value,'draft retained');
      }
      assert.equal(globalThis.__retainedMounts,2,'navigation reuses rather than remounts pages');
      app.select('library');await settle();assert.equal(page('library').scrollTop,79);
      app.account();await settle();
      assert.equal(globalThis.__retainedMounts,3);
      assert.equal(page('feed'),null,'old private page unmounted on account change');
      assert.equal(home.isConnected,false);assert.equal(input.isConnected,false);
      assert.equal(page('library').querySelector('input').value,'');
    } finally { if(app)await unmount(app);target.remove();assert.equal(observers.size,0); }
  });
}

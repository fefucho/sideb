import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

if (!process.execArgv.includes('--conditions=browser')) {
  test('mounted continuous queue preserves browsing across playback generations and recommendation updates', () => {
    const { NODE_TEST_CONTEXT, ...env } = process.env;
    const result = spawnSync(process.execPath, ['--conditions=browser', '--test', fileURLToPath(import.meta.url)], { encoding: 'utf8', env });
    assert.equal(result.status, 0, result.stdout + result.stderr);
  });
} else {
  const { mountedSvelteEnvironment } = await import('./helpers/mount-svelte.mjs');
  const { root, dom, moduleFor, mount, unmount, flushSync, tick } = await mountedSvelteEnvironment('queue-continuous-runtime');
  Object.defineProperty(HTMLElement.prototype, 'clientHeight', { configurable: true, get: () => 480 });
  const Fixture = (await import(await moduleFor(path.join(root, 'scripts/fixtures/QueueContinuousFixture.svelte'), `<script>
    import QueuePanel from '$lib/components/fullscreen/QueuePanel.svelte';
    const entry = i => ({entryId:'e'+i,videoId:'v'+i,title:'Track '+i,artists:'Artist',duration:180});
    let playback=$state({generation:1,isPlaying:true,isLoading:false,currentTrack:entry(100),queue:{items:Array.from({length:1000},(_,i)=>entry(i)),currentIndex:100,source:{kind:'playlist',id:'list',title:'List'},recommendations:[entry(2000)]}});
    export function advance(){const index=playback.queue.currentIndex+1;playback={...playback,generation:playback.generation+1,currentTrack:entry(index),queue:{...playback.queue,currentIndex:index}};}
    export function recommend(){playback={...playback,queue:{...playback.queue,recommendations:[entry(2000),entry(2001)]}};}
    export function replace(){playback={...playback,generation:playback.generation+1,queue:{...playback.queue,items:[entry(4000),entry(4001)],currentIndex:0},currentTrack:entry(4000)};}
    const noop=()=>{};
  </script><QueuePanel {playback} onSelectQueue={noop} onMoveQueue={noop}/>`))).default;
  const settle = async () => { flushSync(); await tick(); await new Promise(resolve => dom.requestAnimationFrame(resolve)); flushSync(); await tick(); };
  test('actual queue follows initially, then preserves manual scroll across generations and reserve updates', async () => {
    const target = document.createElement('div'); document.body.append(target);
    const app = mount(Fixture, { target });
    try {
      await settle();
      const list = target.querySelector('.queue-list');
      assert.equal(list.scrollTop, 99 * 48);
      assert.ok(target.querySelector('[data-entry-id="e100"]'));
      assert.ok(!target.querySelector('[data-entry-id="e0"]'));
      assert.ok(target.querySelectorAll('.queue-row').length < 35);
      app.advance(); await settle();
      assert.equal(list.scrollTop, 100 * 48, 'advance follows current without changing focus');
      list.dispatchEvent(new dom.WheelEvent('wheel', { deltaY: -480, bubbles: true }));
      list.scrollTop = 60 * 48 + 13;
      list.dispatchEvent(new dom.Event('scroll')); await settle();
      app.advance(); await settle();
      assert.equal(list.scrollTop, 60 * 48 + 13, 'playback generation must not reset manual browsing');
      app.recommend(); await settle();
      assert.equal(list.scrollTop, 60 * 48 + 13, 'reserve update must preserve exact viewport offset');
      assert.ok(target.querySelector('[data-entry-id="e60"]'));
      assert.equal(target.querySelector('.previous-toggle'), null);
      app.replace(); await settle();
      assert.equal(list.scrollTop, 0, 'new occurrences identify replacement even for the same playlist');
      assert.ok(target.querySelector('[data-entry-id="e4000"]'));
    } finally { await unmount(app); target.remove(); }
  });
}

<script lang="ts">
  import { t } from '$lib/i18n';
  import type { JamActions, JamViewState } from '$lib/jam/types';
  import JamOffsetControl from './JamOffsetControl.svelte';
  import { signedMs } from './view';

  /** Debug view of the Jam mirror (port of `JamDebugPanel`): sync offset, manual trim, resync and the session log. */
  let { state: jam, actions, onClose }: { state: JamViewState; actions: Pick<JamActions, 'setManualOffset' | 'resync'>; onClose?: () => void } = $props();
  const yesNo = (value: boolean | null) => value === null ? $t('windows.jam.debug.unknown') : value ? $t('windows.jam.debug.yes') : $t('windows.jam.debug.no');
  const lines = $derived(jam.log.slice(-40));
  let copied = $state(false);
  async function copyLog() {
    try { await navigator.clipboard.writeText(jam.log.slice(-200).join('\n')); copied = true; setTimeout(() => copied = false, 1500); } catch { /* Clipboard may be unavailable. */ }
  }
</script>

<section class="debug" aria-label={$t('windows.jam.debug.title')}>
  <header>
    <h3>{$t('windows.jam.debug.title')}</h3>
    {#if onClose}<button type="button" class="close" onclick={onClose} aria-label={$t('windows.jam.debug.close')} title={$t('windows.jam.debug.close')}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><path d="M6 6 18 18M18 6 6 18" /></svg></button>{/if}
  </header>
  <dl>
    <div><dt class="sr-only">{$t('windows.jam.debug.title')}</dt><dd data-debug="runtime">{$t('windows.jam.debug.runtime', [yesNo(jam.runtime.pluginAvailable), yesNo(jam.runtime.running), yesNo(jam.runtime.signedIn)])}</dd></div>
    <div><dd data-debug="phase">{$t('windows.jam.debug.phase', [jam.phase])}</dd></div>
    <div><dd data-debug="sync">{$t('windows.jam.debug.sync', [jam.sync.status])}</dd></div>
    <div><dd data-debug="offset">{jam.sync.offsetMs === null ? $t('windows.jam.debug.offsetUnknown') : $t('windows.jam.debug.offset', [signedMs(jam.sync.offsetMs)])}</dd></div>
  </dl>
  <JamOffsetControl title={$t('windows.jam.debug.manual')} hint={$t('windows.jam.sync.manualHint')} value={jam.sync.manualOffsetMs} onChange={ms => actions.setManualOffset(ms)} steps={[10, 50]} />
  <div class="tools">
    <button type="button" class="tool" data-debug="resync" onclick={() => actions.resync()}>{$t('windows.jam.debug.resync')}</button>
    <button type="button" class="tool" data-debug="copy" disabled={!jam.log.length} onclick={copyLog}>{copied ? '✓ ' : ''}{$t('windows.jam.debug.copyLog')}</button>
  </div>
  <h4>{$t('windows.jam.debug.log')}</h4>
  <!-- svelte-ignore a11y_no_noninteractive_tabindex (scrollable region: keyboard users must be able to scroll it) -->
  <ol class="log" aria-label={$t('windows.jam.debug.log')} tabindex="0">
    {#each lines as line, index (index)}<li>{line}</li>{:else}<li class="empty">{$t('windows.jam.debug.logEmpty')}</li>{/each}
  </ol>
</section>

<style>
  .debug { display: flex; flex-direction: column; gap: 10px; box-sizing: border-box; min-width: 0; padding: 12px; border: 1px solid var(--sideb-surface-border); border-radius: 12px; background: var(--sideb-surface); }
  header { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
  h3, h4 { margin: 0; color: rgb(255 255 255 / 52%); font-size: 10px; font-weight: 600; letter-spacing: .6px; text-transform: uppercase; }
  .close { display: grid; place-items: center; width: 22px; height: 22px; padding: 0; border: 0; border-radius: 6px; color: rgb(255 255 255 / 60%); background: transparent; cursor: pointer; }
  .close:hover { color: #fff; background: rgb(255 255 255 / 10%); } .close svg { width: 11px; height: 11px; }
  dl { display: flex; flex-direction: column; gap: 2px; margin: 0; color: rgb(255 255 255 / 70%); font-size: 11.5px; font-variant-numeric: tabular-nums; } dd { margin: 0; }
  .tools { display: flex; gap: 6px; }
  .tool { flex: 1; height: 28px; border: 1px solid var(--sideb-surface-border); border-radius: 8px; color: #f3f3f6; background: var(--sideb-surface); font: inherit; font-size: 12px; font-weight: 600; cursor: pointer; }
  .tool:hover:not(:disabled) { background: var(--sideb-surface-hover); } .tool:disabled { opacity: .45; cursor: default; }
  .log { display: flex; flex-direction: column; gap: 2px; max-height: 150px; margin: 0; padding: 6px 8px; overflow: auto; list-style: none; border-radius: 8px; color: rgb(255 255 255 / 66%); background: rgb(0 0 0 / 26%); font: 11px/1.35 ui-monospace, Consolas, monospace; user-select: text; scrollbar-width: thin; }
  .log li { overflow-wrap: anywhere; } .log .empty { color: rgb(255 255 255 / 42%); font-family: inherit; }
  .sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
  button:focus-visible, .log:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 2px; }
</style>

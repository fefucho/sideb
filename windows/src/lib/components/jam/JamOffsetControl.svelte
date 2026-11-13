<script lang="ts">
  import { t } from '$lib/i18n';
  import { signedMs } from './view';
  /** Millisecond trim with step buttons and a reset (port of `JamOffsetControl`). */
  let { title, hint, value, onChange, steps = [10, 50], limit = 5000 }: { title: string; hint?: string; value: number; onChange: (ms: number) => void; steps?: number[]; limit?: number } = $props();
  const set = (next: number) => onChange(Math.max(-limit, Math.min(limit, next)));
</script>

<div class="control" role="group" aria-label={title}>
  <div class="head"><span class="title">{title}</span><button type="button" class="reset" disabled={value === 0} onclick={() => onChange(0)}>{$t('jam.sync.reset')}</button></div>
  <div class="row">
    {#each [...steps].reverse() as step (step)}<button type="button" class="step" data-step={-step} aria-label={$t('jam.sync.decrease', [step])} onclick={() => set(value - step)}>−{step}</button>{/each}
    <output class="value">{$t('jam.sync.value', [signedMs(value)])}</output>
    {#each steps as step (step)}<button type="button" class="step" data-step={step} aria-label={$t('jam.sync.increase', [step])} onclick={() => set(value + step)}>+{step}</button>{/each}
  </div>
  {#if hint}<p class="hint">{hint}</p>{/if}
</div>

<style>
  .control { display: flex; flex-direction: column; gap: 7px; }
  .head { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
  .title { color: #f3f3f6; font-size: 12px; font-weight: 600; }
  .reset { padding: 0; border: 0; color: var(--sideb-highlight); background: transparent; font: inherit; font-size: 11px; font-weight: 600; cursor: pointer; }
  .reset:disabled { opacity: .4; cursor: default; }
  .row { display: flex; align-items: center; gap: 5px; }
  .value { flex: 1; color: #f3f3f6; font-size: 12px; font-weight: 600; font-variant-numeric: tabular-nums; text-align: center; }
  .step { width: 36px; height: 24px; padding: 0; border: .5px solid var(--sideb-surface-border); border-radius: 7px; color: #f3f3f6; background: var(--sideb-surface); font: inherit; font-size: 11px; font-weight: 600; font-variant-numeric: tabular-nums; cursor: pointer; }
  .step:hover { background: var(--sideb-surface-hover); }
  .hint { margin: 0; color: rgb(255 255 255 / 52%); font-size: 11px; line-height: 1.35; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 2px; }
</style>

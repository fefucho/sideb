<script lang="ts" generics="Value extends string">
  import '$lib/styles/controls.css';
  import type { Snippet } from 'svelte';
  import { segmentKeyIndex } from './controls';
  type Option = { id: Value; label: string; disabled?: boolean };
  let { options, value, onChange, label, id, panelId, icon, iconOnly = false, collapseLabels = false, appearance = 'standard' }:
    { options: Option[]; value: Value; onChange: (value: Value) => void; label: string;
      id: string; panelId?: string; icon?: Snippet<[Value]>; iconOnly?: boolean; collapseLabels?: boolean; appearance?: 'standard' | 'toolbar' } = $props();
  let root: HTMLDivElement;
  const selected = $derived(options.find(item => item.id === value && !item.disabled)?.id ?? options.find(item => !item.disabled)?.id);
  function keydown(event: KeyboardEvent) {
    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey || !(event.target instanceof HTMLButtonElement)) return;
    const enabled = options.filter(item => !item.disabled);
    const next = segmentKeyIndex(event.key, enabled.findIndex(item => `${id}-${item.id}` === (event.target as HTMLElement).id), enabled.length, getComputedStyle(root).direction === 'rtl');
    if (next === null) return;
    event.preventDefault();
    const item = enabled[next];
    onChange(item.id);
    root.querySelector<HTMLButtonElement>(`[data-value="${CSS.escape(item.id)}"]`)?.focus();
  }
</script>
<div bind:this={root} class="sideb-control-group" data-appearance={appearance} data-icon-only={iconOnly} data-collapse-labels={collapseLabels && !!icon}
  role={panelId ? 'tablist' : 'group'} aria-label={label} onkeydown={keydown}>
  {#each options as option (option.id)}
    <button class="sideb-control" type="button" id={`${id}-${option.id}`} data-value={option.id} data-selected={selected === option.id}
      role={panelId ? 'tab' : undefined} aria-selected={panelId ? selected === option.id : undefined}
      aria-pressed={panelId ? undefined : selected === option.id} aria-controls={panelId}
      tabindex={panelId ? selected === option.id ? 0 : -1 : undefined} disabled={option.disabled}
      aria-label={option.label} title={option.label} onclick={() => onChange(option.id)}>
      <span class="sideb-control-content">{#if icon}{@render icon(option.id)}{/if}<span class="sideb-segment-label" hidden={iconOnly}>{option.label}</span></span>
    </button>
  {/each}
</div>

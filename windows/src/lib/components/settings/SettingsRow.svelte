<script lang="ts">
  import type { Snippet } from 'svelte';
  export interface SettingsRowIds { labelId: string; hintId: string | undefined }
  interface Props { title: string; subtitle?: string | null; children?: Snippet<[SettingsRowIds]> }
  let { title, subtitle, children }: Props = $props();
  const id = $props.id();
  const ids = $derived<SettingsRowIds>({ labelId: `${id}-label`, hintId: subtitle ? `${id}-hint` : undefined });
</script>
<div class="row">
  <div class="text">
    <span id={ids.labelId} class="title">{title}</span>
    {#if subtitle}<span id={ids.hintId} class="subtitle">{subtitle}</span>{/if}
  </div>
  {#if children}<div class="control">{@render children(ids)}</div>{/if}
</div>
<style>
  .row { display:flex; align-items:center; gap:16px; min-width:0; min-height:28px; }
  .text { display:flex; flex-direction:column; gap:2px; flex:1 1 auto; min-width:0; }
  .title { font-size:13px; line-height:18px; color:var(--control-foreground, #f3f3f6); }
  .subtitle { font-size:11.5px; line-height:16px; color:var(--control-muted, #c3c3cb); }
  .control { display:flex; align-items:center; gap:8px; flex:none; max-width:60%; }
</style>

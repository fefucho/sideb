<script lang="ts">
  import ControlButton from './ControlButton.svelte';
  import type { HTMLButtonAttributes } from 'svelte/elements';
  import type { Snippet } from 'svelte';
  let { selected, children, ...attributes }: HTMLButtonAttributes & { selected: boolean; children: Snippet } = $props();
</script>
<ControlButton {...attributes} size="category" {selected} aria-pressed={selected}>{@render children()}</ControlButton>

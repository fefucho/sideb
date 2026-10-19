<script lang="ts">
  import '$lib/styles/controls.css';
  import type { HTMLButtonAttributes } from 'svelte/elements';
  import type { Snippet } from 'svelte';

  type Props = HTMLButtonAttributes & {
    children?: Snippet;
    size?: 'category' | 'action' | 'utility';
    emphasis?: 'neutral' | 'prominent' | 'quiet';
    selected?: boolean;
    iconOnly?: boolean;
    loading?: boolean;
    loadingFeedback?: 'spinner' | 'subtle';
    element?: HTMLButtonElement;
  };
  let { children, size = 'action', emphasis = 'neutral', selected = false,
    iconOnly = false, loading = false, loadingFeedback = 'spinner', disabled = false, type = 'button',
    element = $bindable(), class: className = '', ...attributes }: Props = $props();
</script>
<button {...attributes} bind:this={element} {type} disabled={disabled || loading}
  class={`sideb-control ${className}`} data-size={size} data-emphasis={emphasis}
  data-selected={selected} data-icon={iconOnly} data-loading-feedback={loadingFeedback} aria-busy={loading || undefined}>
  <span class="sideb-control-content">{#if children}{@render children()}{/if}</span>
  {#if loading}<span class={loadingFeedback === 'subtle' ? 'sideb-control-pending' : 'sideb-control-spinner'} aria-hidden="true"></span>{/if}
</button>

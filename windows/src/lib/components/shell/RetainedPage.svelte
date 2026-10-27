<script lang="ts">
  import { tick, untrack, type Snippet } from 'svelte';

  interface Props {
    id: string;
    selected: boolean;
    covered?: boolean;
    scrollable?: boolean;
    element?: HTMLDivElement;
    children: Snippet<[boolean]>;
  }
  let { id, selected, covered = false, scrollable = true, element = $bindable(), children }: Props = $props();
  let visited = $state(untrack(() => selected));
  let scrollTop = 0;
  let revision = 0;
  const active = $derived(selected && !covered);

  // Run before hidden changes layout: a hidden element may report scrollTop=0.
  $effect.pre(() => {
    if (selected) visited = true;
    else if (element) scrollTop = element.scrollTop || scrollTop;
  });
  $effect(() => {
    const current = ++revision;
    if (!selected || !element) return;
    const host = element;
    void tick().then(() => {
      if (current === revision && selected && element === host) host.scrollTop = scrollTop;
    });
  });
</script>

{#if visited}
  <div bind:this={element} class="retained-page" class:scrollable data-retained-page={id}
    data-page-scroll={scrollable ? '' : undefined} data-page-active={active}
    hidden={!selected} inert={!active} aria-hidden={!active}
    onscroll={() => { if (selected && element) scrollTop = element.scrollTop; }}>
    {@render children(active)}
  </div>
{/if}

<style>
  .retained-page { box-sizing:border-box; width:100%; height:100%; min-width:0; min-height:0; overflow:hidden; }
  .retained-page[hidden] { display:none; }
  .scrollable { overflow:auto; overflow-anchor:none; }
  .retained-page[inert] :global(*) { animation-play-state:paused !important; }
</style>

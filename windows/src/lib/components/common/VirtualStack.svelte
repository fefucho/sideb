<script lang="ts" generics="T">
  import { onMount, type Snippet } from 'svelte';
  interface Props { items: T[]; height: (item: T, width: number) => number; key: (item: T) => string; children: Snippet<[T, number]>; scrollSelector?: string; active?: boolean }
  let { items, height, key, children, scrollSelector = '.content-column', active = true }: Props = $props();
  let host: HTMLDivElement; let width = $state(1000); let top = $state(0); let viewport = $state(800);
  let measure = () => {};
  $effect(() => { items; active; if(!active)return; const frame = requestAnimationFrame(() => measure()); return () => cancelAnimationFrame(frame); });
  const offsets = $derived.by(() => { const result = [0]; for (const item of items) result.push(result[result.length - 1] + height(item, width)); return result; });
  const range = $derived.by(() => {
    let start = 0; while (start < items.length && offsets[start + 1] < top - 320) start++;
    let end = start; while (end < items.length && offsets[end] < top + viewport + 320) end++;
    return { start, end };
  });
  onMount(() => {
    const root = host.closest<HTMLElement>(scrollSelector) ?? document.querySelector<HTMLElement>(scrollSelector);
    const sync = () => { if(!active)return; const rect = host.getBoundingClientRect(); const rootRect = root?.getBoundingClientRect(); width = rect.width; top = (rootRect?.top ?? 0) - rect.top; viewport = root?.clientHeight ?? window.innerHeight; };
    measure = sync;
    sync(); root?.addEventListener('scroll', sync, { passive: true }); window.addEventListener('resize', sync);
    const observer = new ResizeObserver(sync); observer.observe(host); if (root) observer.observe(root);
    return () => { observer.disconnect(); root?.removeEventListener('scroll', sync); window.removeEventListener('resize', sync); };
  });
</script>
<div bind:this={host}>
  <div style={`height:${offsets[range.start]}px`} aria-hidden="true"></div>
  {#each items.slice(range.start, range.end) as item, index (key(item))}
    <div style={`height:${height(item, width)}px`}>{@render children(item, index + range.start)}</div>
  {/each}
  <div style={`height:${offsets[items.length] - offsets[range.end]}px`} aria-hidden="true"></div>
</div>

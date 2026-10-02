<script lang="ts">
  import { onMount, tick } from 'svelte';
  import type { MenuAction, MenuItem } from '$lib/menu/types';
  import MenuIcon from './MenuIcon.svelte';

  interface Props {
    items: MenuItem[];
    x: number;
    y: number;
    onAction: (action: MenuAction) => void;
    onClose: () => void;
  }
  let { items, x, y, onAction, onClose }: Props = $props();
  let layer: HTMLDivElement;
  let left = $state(0);
  let top = $state(0);
  let expandedId = $state<string | null>(null);
  let submenuOnLeft = $state(false);
  let submenuLeft = $state(0);
  let submenuTop = $state(0);
  let activeIndex = $state(0);
  let closed = false;
  const enabled = (list: MenuItem[]) => list.filter((item) => !item.separator && !item.disabled);
  const rootEnabled = $derived(enabled(items));
  const submenu = $derived(items.find((item) => item.id === expandedId)?.children ?? []);
  const activeItems = $derived(expandedId ? enabled(submenu) : rootEnabled);

  function focusItem(index: number, list = activeItems) {
    if (!list.length) return;
    activeIndex = (index + list.length) % list.length;
    const id = list[activeIndex].id;
    void tick().then(() => {
      const button = Array.from(layer?.querySelectorAll<HTMLButtonElement>('[data-menu-id]') ?? []).find((item) => item.dataset.menuId === id);
      button?.focus();
    });
  }
  function close() {
    if (closed) return;
    closed = true;
    onClose();
  }
  function choose(item: MenuItem) {
    if (item.disabled || item.separator) return;
    if (item.children?.length) { expandedId = item.id; activeIndex = 0; focusItem(0, enabled(item.children)); placeSubmenu(); return; }
    if (!item.action) return;
    onAction(item.action);
    closed = true;
    onClose();
  }
  function onKeydown(event: KeyboardEvent) {
    if (event.key === 'Escape') { event.preventDefault(); close(); return; }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault(); focusItem(activeIndex + (event.key === 'ArrowDown' ? 1 : -1)); return;
    }
    if (event.key === 'Home' || event.key === 'End') {
      event.preventDefault(); focusItem(event.key === 'Home' ? 0 : activeItems.length - 1); return;
    }
    if (event.key === 'ArrowRight' && !expandedId) {
      const item = rootEnabled[activeIndex];
      if (item?.children?.length) { event.preventDefault(); expandedId = item.id; activeIndex = 0; focusItem(0, enabled(item.children)); placeSubmenu(); }
      return;
    }
    if (event.key === 'ArrowLeft' && expandedId) {
      event.preventDefault(); const parent = expandedId; expandedId = null;
      const parentIndex = rootEnabled.findIndex((item) => item.id === parent); focusItem(parentIndex, rootEnabled);
    }
    if (event.key === 'Enter' || event.key === ' ') {
      const item = activeItems[activeIndex];
      if (item) { event.preventDefault(); choose(item); }
    }
  }
  function outsideClick(event: MouseEvent) {
    if (event.target instanceof Node && !layer?.contains(event.target)) close();
  }
  function place() {
    if (!layer) return;
    const rect = layer.getBoundingClientRect();
    left = Math.max(8, Math.min(x, window.innerWidth - rect.width - 8));
    top = Math.max(8, Math.min(y, window.innerHeight - rect.height - 8));
  }
  function placeSubmenu() {
    void tick().then(() => {
      if (!layer || !expandedId) return;
      const trigger = Array.from(layer.querySelectorAll<HTMLButtonElement>('[data-menu-id]')).find((item) => item.dataset.menuId === expandedId);
      const submenuElement = layer?.querySelector<HTMLElement>('.submenu');
      if (!trigger || !submenuElement) return;
      const triggerRect = trigger.getBoundingClientRect();
      const submenuRect = submenuElement.getBoundingClientRect();
      submenuOnLeft = triggerRect.right + submenuRect.width + 5 > window.innerWidth - 8;
      submenuLeft = Math.max(8, Math.min(submenuOnLeft ? triggerRect.left - submenuRect.width - 5 : triggerRect.right + 5, window.innerWidth - submenuRect.width - 8));
      submenuTop = Math.max(8, Math.min(triggerRect.top, window.innerHeight - submenuRect.height - 8));
    });
  }

  onMount(() => {
    place();
    focusItem(0, rootEnabled);
    document.addEventListener('pointerdown', outsideClick, true);
    window.addEventListener('resize', place);
    return () => { document.removeEventListener('pointerdown', outsideClick, true); window.removeEventListener('resize', place); };
  });
  $effect(() => {
    const nextX = x; const nextY = y; items;
    left = nextX; top = nextY;
    void tick().then(place);
  });
</script>

<div class="menu-layer" bind:this={layer} style:left={`${left}px`} style:top={`${top}px`}>
  <ul class="menu" role="menu" aria-label="Acciones" onkeydown={onKeydown}>
    {#each items as item (item.id)}
      {#if item.separator}
        <li class="separator" role="separator"></li>
      {:else}
        <li class="menu-entry" role="none" onmouseenter={() => { if (item.children?.length) { expandedId = item.id; activeIndex = 0; placeSubmenu(); } }}>
          <button class="menu-item" type="button" role={item.checked === undefined ? 'menuitem' : 'menuitemradio'} aria-checked={item.checked} tabindex="-1" data-menu-id={item.id}
            aria-disabled={item.disabled || undefined} aria-haspopup={item.children?.length ? 'menu' : undefined}
            aria-expanded={item.children?.length ? expandedId === item.id : undefined}
            disabled={item.disabled} onclick={() => choose(item)}>
            <span class="item-content"><MenuIcon name={item.icon} /><span>{item.label}</span></span><span class="trail" aria-hidden="true">{item.children?.length ? '›' : item.checked ? '✓' : ''}</span>
          </button>
          {#if item.children?.length && expandedId === item.id}
            <ul class="menu submenu" style:left={`${submenuLeft}px`} style:top={`${submenuTop}px`} role="menu" aria-label={item.label}>
              {#each item.children as child (child.id)}
                {#if child.separator}<li class="separator" role="separator"></li>{:else}
                  <li role="none"><button class="menu-item" type="button" role={child.checked === undefined ? 'menuitem' : 'menuitemradio'} tabindex="-1" data-menu-id={child.id}
                    aria-disabled={child.disabled || undefined} aria-checked={child.checked === undefined ? undefined : child.checked}
                    disabled={child.disabled} onclick={() => choose(child)}>
                    <span class="item-content"><MenuIcon name={child.icon} /><span>{child.label}</span></span><span class="trail" aria-hidden="true">{child.checked ? '✓' : ''}</span>
                  </button></li>
                {/if}
              {/each}
            </ul>
          {/if}
        </li>
      {/if}
    {/each}
  </ul>
</div>

<style>
  .menu-layer { position: fixed; z-index: 1000; min-width: 208px; max-width: min(320px, calc(100vw - 16px)); }
  .menu { box-sizing: border-box; min-width: 208px; max-width: min(320px, calc(100vw - 16px)); max-height: min(420px, calc(100vh - 16px)); overflow: auto; margin: 0; padding: 5px; list-style: none; border: 1px solid rgb(255 255 255 / 12%); border-radius: 9px; color: #f3f1f2; background: #29292f; box-shadow: 0 10px 30px rgb(0 0 0 / 45%); font: 13px/1.35 system-ui, "Segoe UI", sans-serif; }
  .menu-entry { position: relative; }
  .menu-item { display: flex; width: 100%; min-height: 32px; align-items: center; justify-content: space-between; gap: 20px; padding: 6px 9px; border: 0; border-radius: 5px; color: inherit; background: transparent; text-align: left; font: inherit; cursor: pointer; white-space: nowrap; }
  .item-content { display: flex; min-width: 0; align-items: center; gap: 9px; }
  .menu-item:hover:not(:disabled), .menu-item:focus-visible { outline: 0; background: rgb(255 255 255 / 9%); }
  .menu-item:disabled { color: rgb(255 255 255 / 42%); cursor: default; }
  .trail { color: rgb(255 255 255 / 65%); }
  .separator { height: 1px; margin: 4px 6px; background: rgb(255 255 255 / 10%); }
  .submenu { position: fixed; z-index: 1; }
</style>

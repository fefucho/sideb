<script lang="ts">
  import { onMount, tick } from 'svelte';
  import type { AccountPlaylistDto as PlaylistDetailDto } from '$lib/account/types';

  interface Props { playlist: PlaylistDetailDto; onDelete: () => Promise<void>; onClose: () => void }
  let { playlist, onDelete, onClose }: Props = $props();
  let pending = $state(false);
  let error = $state<string | null>(null);
  let cancelButton: HTMLButtonElement;
  let previousFocus: HTMLElement | null = null;

  onMount(() => {
    previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    cancelButton?.focus();
    const keydown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !pending) { event.stopPropagation(); onClose(); }
      if (event.key !== 'Tab') return;
      const focusable = Array.from(document.querySelectorAll<HTMLElement>('[data-playlist-delete] button:not(:disabled)'));
      if (!focusable.length) { event.preventDefault(); return; }
      if (event.shiftKey && document.activeElement === focusable[0]) { event.preventDefault(); focusable.at(-1)?.focus(); }
      else if (!event.shiftKey && document.activeElement === focusable.at(-1)) { event.preventDefault(); focusable[0]?.focus(); }
    };
    document.addEventListener('keydown', keydown);
    return () => { document.removeEventListener('keydown', keydown); void tick().then(() => previousFocus?.focus()); };
  });

  async function confirmDelete() {
    if (pending) return;
    pending = true; error = null;
    try { await onDelete(); onClose(); }
    catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { pending = false; }
  }
</script>

<div class="scrim" role="presentation" onclick={(event) => { if (event.target === event.currentTarget && !pending) onClose(); }}>
  <div class="dialog" data-playlist-delete role="alertdialog" aria-modal="true" aria-labelledby="delete-title" aria-describedby="delete-description" aria-busy={pending}>
    <div class="icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16M10 11v6m4-6v6M5 7l1 14h12l1-14M9 7V4h6v3" /></svg></div>
    <h2 id="delete-title">¿Eliminar playlist?</h2>
    <p id="delete-description">Se eliminará “{playlist.title}”. Esta acción no se puede deshacer.</p>
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    <footer><button bind:this={cancelButton} class="cancel" type="button" disabled={pending} onclick={onClose}>Cancelar</button><button class="delete" type="button" disabled={pending} onclick={confirmDelete}>{pending ? 'Eliminando…' : 'Eliminar playlist'}</button></footer>
  </div>
</div>

<style>
  .scrim { position: fixed; inset: 0; z-index: 500; display: grid; place-items: center; padding: 24px; background: rgb(0 0 0 / 65%); }
  .dialog { box-sizing: border-box; width: min(430px, 100%); padding: 28px; border: 1px solid var(--sideb-surface-border); border-radius: 16px; color: #f7f7f8; background: #29292f; box-shadow: 0 24px 80px #0009; text-align: center; }
  .icon { display: grid; width: 42px; height: 42px; place-items: center; margin: 0 auto 15px; border-radius: 50%; color: #ffb7bb; background: rgb(192 55 65 / 18%); }.icon svg { width: 21px; height: 21px; }
  h2 { margin: 0 0 9px; font-size: 19px; } p { margin: 0; color: #b9b9c0; font-size: 13px; line-height: 1.5; }.error { margin-top: 14px; color: #ffb4b9; }
  footer { display: flex; justify-content: center; gap: 10px; margin-top: 24px; } footer button { min-height: 36px; padding: 7px 15px; border: 1px solid var(--sideb-surface-border); border-radius: 999px; color: white; background: var(--sideb-surface); font: inherit; font-size: 12px; font-weight: 600; cursor: pointer; }.delete { border-color: transparent; background: #a33d45; } button:disabled { opacity: .55; cursor: wait; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 3px; }
</style>

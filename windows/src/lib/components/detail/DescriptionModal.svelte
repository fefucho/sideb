<script lang="ts">
  import { onMount, tick } from "svelte";

  interface Props { title: string; description: string; onClose: () => void }
  let { title, description, onClose }: Props = $props();
  let closeButton: HTMLButtonElement;
  let previousFocus: HTMLElement | null = null;

  onMount(() => {
    previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    closeButton?.focus();
    const keydown = (event: KeyboardEvent) => {
      if (event.key === "Escape") { event.stopPropagation(); onClose(); }
      if (event.key === "Tab") {
        const focusable = Array.from(document.querySelectorAll<HTMLElement>("[role=dialog] button:not(:disabled)"));
        if (focusable.length === 0) { event.preventDefault(); return; }
        if (focusable.length === 1) { event.preventDefault(); focusable[0].focus(); return; }
        if (event.shiftKey && document.activeElement === focusable[0]) { event.preventDefault(); focusable.at(-1)?.focus(); }
        else if (!event.shiftKey && document.activeElement === focusable.at(-1)) { event.preventDefault(); focusable[0]?.focus(); }
      }
    };
    document.addEventListener("keydown", keydown);
    return () => { document.removeEventListener("keydown", keydown); void tick().then(() => previousFocus?.focus()); };
  });
</script>

<div class="scrim" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) onClose(); }}>
  <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="description-title">
    <header><div><p>DESCRIPCIÓN</p><h2 id="description-title">{title}</h2></div><button bind:this={closeButton} type="button" aria-label="Cerrar descripción" onclick={onClose}>×</button></header>
    <div class="body">{description}</div>
  </div>
</div>

<style>
  .scrim { position: fixed; inset: 0; z-index: 20; display: grid; place-items: center; padding: 24px; background: rgb(0 0 0 / 62%); }
  .dialog { width: min(620px, 100%); max-height: min(78vh, 720px); overflow: hidden; display: flex; flex-direction: column; border: 1px solid var(--sideb-surface-border); border-radius: 16px; color: #f7f7f8; background: #29292f; box-shadow: 0 24px 80px #0009; }
  header { display: flex; align-items: flex-start; justify-content: space-between; gap: 20px; padding: 22px 24px 16px; border-bottom: 1px solid var(--sideb-surface-border); }
  header p { margin: 0 0 5px; color: #a6a6ad; font-size: 10px; font-weight: 700; letter-spacing: .12em; }
  h2 { margin: 0; font-size: 20px; }
  button { flex: none; width: 32px; height: 32px; border: 0; border-radius: 50%; color: inherit; background: rgb(255 255 255 / 8%); font-size: 23px; line-height: 1; cursor: pointer; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 3px; }
  .body { overflow: auto; padding: 20px 24px 26px; color: #d2d2d8; font-size: 14px; line-height: 1.65; white-space: pre-wrap; }
</style>

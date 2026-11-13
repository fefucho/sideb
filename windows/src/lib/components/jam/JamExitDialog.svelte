<script lang="ts">
  import { tick } from 'svelte';
  import { t, language } from '$lib/i18n';
  import type { JamActions, JamPendingExit } from '$lib/jam/types';
  import { jamText } from './view';

  /** "Leave the Jam?" confirmation: something that would play other music was requested during a Jam. */
  let { pending, actions }: { pending: JamPendingExit | null; actions: Pick<JamActions, 'confirmExit' | 'cancelExit'> } = $props();
  let stay = $state<HTMLButtonElement>();
  let dialog = $state<HTMLDivElement>();
  let busy = $state(false);

  async function confirm() {
    if (busy) return;
    busy = true;
    try { await actions.confirmExit(); } finally { busy = false; }
  }
  // Focus goes to the safe choice ("stay") and returns to where it was when the dialog goes away.
  $effect(() => {
    if (!pending) return;
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    void tick().then(() => stay?.focus());
    const keydown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); actions.cancelExit(); return; }
      if (event.key !== 'Tab' || !dialog) return;
      const focusable = [...dialog.querySelectorAll<HTMLElement>('button:not(:disabled)')];
      const first = focusable[0], last = focusable.at(-1);
      if (!first || !last) { event.preventDefault(); return; }
      if (event.shiftKey && (document.activeElement === first || !dialog.contains(document.activeElement))) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && (document.activeElement === last || !dialog.contains(document.activeElement))) { event.preventDefault(); first.focus(); }
    };
    document.addEventListener('keydown', keydown, true);
    return () => { document.removeEventListener('keydown', keydown, true); void tick().then(() => { if (previous?.isConnected) previous.focus({ preventScroll: true }); }); };
  });
</script>

{#if pending}
  <div class="scrim" role="presentation" onclick={(event) => { if (event.target === event.currentTarget) actions.cancelExit(); }}>
    <div bind:this={dialog} class="dialog" data-jam-exit role="alertdialog" aria-modal="true" aria-labelledby="jam-exit-title" aria-describedby="jam-exit-message" aria-busy={busy}>
      <div class="icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" /></svg></div>
      <h2 id="jam-exit-title">{$t('jam.exit.title')}</h2>
      <p id="jam-exit-message" data-jam-exit-message>{jamText(pending.reasonKey, undefined, $language)}</p>
      <footer>
        <button bind:this={stay} type="button" class="stay" data-jam-exit-cancel onclick={() => actions.cancelExit()}>{$t('jam.exit.cancel')}</button>
        <button type="button" class="leave" data-jam-exit-confirm disabled={busy} onclick={confirm}>{$t('jam.exit.confirm')}</button>
      </footer>
    </div>
  </div>
{/if}

<style>
  .scrim { position: fixed; inset: 0; z-index: 900; display: grid; place-items: center; padding: 24px; background: rgb(0 0 0 / 65%); }
  .dialog { box-sizing: border-box; width: min(430px, 100%); padding: 28px; border: 1px solid var(--sideb-surface-border); border-radius: 16px; color: #f7f7f8; background: #29292f; box-shadow: 0 24px 80px #0009; text-align: center; }
  .icon { display: grid; width: 42px; height: 42px; place-items: center; margin: 0 auto 15px; border-radius: 50%; color: var(--sideb-highlight); background: rgb(163 61 69 / 22%); } .icon svg { width: 21px; height: 21px; }
  h2 { margin: 0 0 9px; font-size: 19px; } p { margin: 0; color: #b9b9c0; font-size: 13px; line-height: 1.5; }
  footer { display: flex; flex-wrap: wrap; justify-content: center; gap: 10px; margin-top: 24px; }
  footer button { min-height: 36px; padding: 7px 15px; border: 1px solid var(--sideb-surface-border); border-radius: 999px; color: white; background: var(--sideb-surface); font: inherit; font-size: 12px; font-weight: 600; cursor: pointer; }
  footer button:hover:not(:disabled) { background: var(--sideb-surface-hover); }
  .leave { border-color: transparent; background: var(--sideb-accent); } .leave:hover:not(:disabled) { background: var(--control-prominent-hover); } button:disabled { opacity: .55; cursor: wait; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 3px; }
</style>

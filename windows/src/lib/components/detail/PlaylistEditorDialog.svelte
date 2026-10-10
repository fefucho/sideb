<script lang="ts">
  import { t, language, resolveMessage, message, type AppMessage } from '$lib/i18n';
  import { onMount, tick } from 'svelte';
  import type { AccountPlaylistDto as PlaylistDetailDto } from '$lib/account/types';

  interface Props {
    playlist: PlaylistDetailDto;
    onSave: (details: { name: string; description: string; privacy: string }) => Promise<void>;
    onClose: () => void;
  }
  let { playlist, onSave, onClose }: Props = $props();
  const isNewPlaylist = $derived(!playlist.id);
  let name = $state('');
  let description = $state('');
  let privacy = $state('PRIVATE');
  let pending = $state(false);
  let error = $state<AppMessage | string | null>(null);
  let nameInput: HTMLInputElement;
  let dialog: HTMLDivElement;
  let previousFocus: HTMLElement | null = null;

  onMount(() => {
    name = playlist.title; description = playlist.description ?? ''; privacy = (playlist.privacy ?? 'PRIVATE').toUpperCase();
    previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    nameInput?.focus(); nameInput?.select();
    const keydown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !pending) { event.stopPropagation(); onClose(); }
      if (event.key !== 'Tab') return;
      const focusable = Array.from(dialog.querySelectorAll<HTMLElement>('button:not(:disabled), input:not(:disabled), textarea:not(:disabled), select:not(:disabled)'));
      if (!focusable.length) { event.preventDefault(); return; }
      if (event.shiftKey && document.activeElement === focusable[0]) { event.preventDefault(); focusable.at(-1)?.focus(); }
      else if (!event.shiftKey && document.activeElement === focusable.at(-1)) { event.preventDefault(); focusable[0]?.focus(); }
    };
    document.addEventListener('keydown', keydown);
    return () => { document.removeEventListener('keydown', keydown); void tick().then(() => previousFocus?.focus()); };
  });

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (pending) return;
    const cleanName = name.trim();
    if (!cleanName || cleanName.length > 150) { error = message('windows.ui.theNameMustContainBetween1And150Characters'); nameInput?.focus(); return; }
    if (description.trim().length > 5000) { error = message('windows.ui.theDescriptionCannotExceed5000Characters'); return; }
    if (!['PRIVATE', 'UNLISTED', 'PUBLIC'].includes(privacy)) { error = message('windows.ui.chooseAValidPrivacyOption'); return; }
    pending = true; error = null;
    try { await onSave({ name: cleanName, description: description.trim(), privacy }); onClose(); }
    catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { pending = false; }
  }
</script>

<div class="scrim" role="presentation" onclick={(event) => { if (event.target === event.currentTarget && !pending) onClose(); }}>
  <div class="dialog" bind:this={dialog} data-playlist-editor role="dialog" aria-modal="true" aria-labelledby="editor-title" aria-busy={pending}>
    <header><div><p>{$t('detail.kind.playlist')}</p><h2 id="editor-title">{isNewPlaylist ? $t('detail.playlistEditor.createTitle') : $t('menu.edit_details')}</h2></div><button type="button" aria-label={$t('windows.ui.closeEditor')} disabled={pending} onclick={onClose}>×</button></header>
    <form onsubmit={submit}>
      <label for="playlist-name">{$t('windows.ui.name')}</label>
      <input id="playlist-name" bind:this={nameInput} bind:value={name} maxlength="150" required autocomplete="off" disabled={pending} />
      <label for="playlist-description">{$t('detail.playlistEditor.description')}</label>
      <textarea id="playlist-description" bind:value={description} maxlength="5000" rows="4" disabled={pending}></textarea>
      <label for="playlist-privacy">{$t('windows.ui.privacy')}</label>
      <select id="playlist-privacy" bind:value={privacy} disabled={pending}>
        <option value="PRIVATE">{$t('detail.playlistEditor.private')}</option><option value="UNLISTED">{$t('detail.playlistEditor.unlisted')}</option><option value="PUBLIC">{$t('detail.playlistEditor.public')}</option>
      </select>
      {#if error}<p class="error" role="alert">{resolveMessage(error, $language)}</p>{/if}
      <footer><button class="cancel" type="button" disabled={pending} onclick={onClose}>{$t('update.cancel')}</button><button class="save" type="submit" disabled={pending}>{pending ? (isNewPlaylist ? $t('windows.ui.creating') : $t('windows.ui.saving')) : (isNewPlaylist ? $t('windows.ui.createPlaylist') : $t('windows.ui.saveChanges'))}</button></footer>
    </form>
  </div>
</div>

<style>
  .scrim { position: fixed; inset: 0; z-index: 500; display: grid; place-items: center; padding: 24px; background: rgb(0 0 0 / 65%); }
  .dialog { box-sizing: border-box; width: min(440px, 100%); max-height: min(88dvh, 760px); overflow: auto; border: 1px solid var(--sideb-surface-border); border-radius: 16px; color: #f7f7f8; background: #29292f; box-shadow: 0 24px 80px #0009; }
  header { display: flex; align-items: flex-start; justify-content: space-between; gap: 20px; padding: 22px 24px 16px; border-bottom: 1px solid var(--sideb-surface-border); }
  header p { margin: 0 0 5px; color: #a6a6ad; font-size: 10px; font-weight: 700; letter-spacing: .12em; } h2 { margin: 0; font-size: 20px; }
  header button { width: 32px; height: 32px; border: 0; border-radius: 50%; color: inherit; background: rgb(255 255 255 / 8%); font-size: 23px; line-height: 1; cursor: pointer; }
  form { display: flex; flex-direction: column; gap: 9px; padding: 20px 24px 24px; } label { margin-top: 5px; color: #dedee3; font-size: 12px; font-weight: 600; }
  input, textarea, select { box-sizing: border-box; width: 100%; padding: 10px 12px; border: 1px solid rgb(255 255 255 / 16%); border-radius: 8px; color: #f7f7f8; background: #1c1c20; font: inherit; font-size: 13px; }
  textarea { min-height: 88px; resize: vertical; } option { color: #f7f7f8; background: #29292f; }
  .error { margin: 2px 0; color: #ffb4b9; font-size: 12px; } footer { display: flex; justify-content: flex-end; gap: 10px; margin-top: 9px; }
  footer button { min-height: 36px; padding: 7px 14px; border: 1px solid var(--sideb-surface-border); border-radius: 999px; color: white; background: var(--sideb-surface); font: inherit; font-size: 12px; font-weight: 600; cursor: pointer; }
  footer .save { border-color: transparent; background: var(--sideb-accent); } button:disabled { opacity: .55; cursor: wait; }
  button:focus-visible, input:focus-visible, textarea:focus-visible, select:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 3px; }
</style>

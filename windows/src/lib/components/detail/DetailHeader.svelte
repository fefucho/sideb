<script lang="ts">
  import { t, language, count, resolveMessage  } from '$lib/i18n';
  import type { Snippet } from 'svelte';
  import CollectionHeader from './CollectionHeader.svelte';
  import MoreIcon from '$lib/components/common/MoreIcon.svelte';
  import type { AlbumDetailDto } from "$lib/types";
  import ArtistCredits from "$lib/components/ArtistCredits.svelte";
  import { createMenuHandlers } from "$lib/menu/hooks";
  interface Props {
    tools?:Snippet;
    album: AlbumDetailDto; loggedIn: boolean; onPlay: (index: number, shuffle?: boolean) => void;
    onOpenArtist: (id: string) => void; onToggleLibrary: () => Promise<void>;
    onDescription: () => void;
  }
  let { album, loggedIn, onPlay, onOpenArtist, onToggleLibrary, onDescription, tools }: Props = $props();
  const createMenu = createMenuHandlers();
  const menu = createMenu(() => ({ kind: 'album', card: { kind: 'album', id: album.browseId, title: album.title, subtitle: album.artist, thumbnail: album.thumbnail, duration: null }, detail: album }), () => ({ view: 'album_detail', currentId: album.browseId }));
  let saving = $state(false);
  let libraryError = $state("");
  const meta = $derived([album.subtitle, album.secondSubtitle ?? count('common.songCount', album.items.length, $language)].filter(Boolean));

  async function toggleLibrary() {
    if (!loggedIn || saving) return;
    saving = true; libraryError = "";
    try { await onToggleLibrary(); } catch (error) { libraryError = error instanceof Error ? error.message : $t('settings.libraryError'); }
    finally { saving = false; }
  }
</script>

<CollectionHeader identity={album.browseId} title={album.title} thumbnail={album.thumbnail} kind={$t('detail.kind.album')} summary={meta.join(' · ')} description={album.description} onDescription={onDescription} {tools}>
  {#snippet credit()}{#if album.artistRuns?.length || album.artist}<ArtistCredits artistRuns={album.artistRuns} artists={album.artist} artistId={album.artistId} {onOpenArtist} />{/if}{/snippet}
  {#snippet actions()}
      <button class="primary" type="button" disabled={!album.items.length} onclick={() => onPlay(0)}><span aria-hidden="true">▶</span> {$t('player.play')}</button>
      <button type="button" disabled={!album.items.length} onclick={() => onPlay(0, true)}><span aria-hidden="true">⤨</span> {$t('player.shuffle')}</button>
      {#if album.playlistId}
        <button type="button" disabled={!loggedIn || saving} title={loggedIn ? (album.inLibrary ? $t('windows.menu.removeFromLibrary') : $t('windows.menu.saveToLibrary')) : $t('windows.ui.signInToSave')} onclick={toggleLibrary}>
          {saving ? $t('windows.ui.saving') : album.inLibrary ? '▣ ' + $t('detail.collection.inLibrary') : '▢ ' + $t('detail.collection.save')}
        </button>
      {/if}
      <button type="button" class="more" aria-label={$t('menu.more_options')} title={$t('menu.more_options')} aria-haspopup="menu" onclick={menu.onContextMenu} onkeydown={menu.onKeyDown}><MoreIcon /></button>
{/snippet}
</CollectionHeader>
{#if libraryError}<p class="error" role="alert">{resolveMessage(libraryError, $language)}</p>{/if}
<style>
button {min-height:38px;padding:0 16px;border:1px solid #ffffff1a;color:#f3f3f5;background:#ffffff0f;font:inherit;font-size:14px;cursor:pointer;}button:hover:not(:disabled){background:#ffffff1f;}button:disabled{opacity:.45;cursor:wait;}.primary{background:var(--sideb-accent);border-color:transparent;}.primary span{margin-right:5px;}.more{display:grid;place-items:center;width:38px;padding:0;}.error{margin:5px 32px;color:#ff9d9d;font-size:12px;}button:focus-visible{outline:2px solid var(--sideb-highlight);outline-offset:3px;}
</style>

<script lang="ts">
  import ControlButton from '$lib/components/common/ControlButton.svelte';

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
      <ControlButton emphasis="prominent" type="button" disabled={!album.items.length} onclick={() => onPlay(0)}><span aria-hidden="true">▶</span> {$t('player.play')}</ControlButton>
      <ControlButton type="button" disabled={!album.items.length} onclick={() => onPlay(0, true)}><span aria-hidden="true">⤨</span> {$t('player.shuffle')}</ControlButton>
      {#if album.playlistId}
        <ControlButton type="button" disabled={!loggedIn} loading={saving} selected={Boolean(album.inLibrary)} aria-pressed={Boolean(album.inLibrary)} title={loggedIn ? (album.inLibrary ? $t('windows.menu.removeFromLibrary') : $t('windows.menu.saveToLibrary')) : $t('windows.ui.signInToSave')} onclick={toggleLibrary}>
          {album.inLibrary ? '▣ ' + $t('detail.collection.inLibrary') : '▢ ' + $t('detail.collection.save')}
        </ControlButton>
      {/if}
      <ControlButton type="button" iconOnly aria-label={$t('menu.more_options')} title={$t('menu.more_options')} aria-haspopup="menu" onclick={menu.onContextMenu} onkeydown={menu.onKeyDown}><MoreIcon /></ControlButton>
{/snippet}
</CollectionHeader>
{#if libraryError}<p class="error" role="alert">{resolveMessage(libraryError, $language)}</p>{/if}
<style>.error{margin:5px 32px;color:#ff9d9d;font-size:12px;}</style>

<script lang="ts">
  import { t , language, resolveMessage } from '$lib/i18n';
  import { providerHeading } from '$lib/i18n/presentation';
  import MoreIcon from '$lib/components/common/MoreIcon.svelte';
  import TrackTable from "./TrackTable.svelte";
  import MediaCard from "../common/MediaCard.svelte";
  import type { ArtistDetailDto, BrowseCardDto } from "$lib/types";
  import DescriptionModal from "./DescriptionModal.svelte";
  import { createMenuHandlers } from "$lib/menu/hooks";

  interface Props {
    artist: ArtistDetailDto | null;
    isLoading: boolean;
    error: string | null;
    currentTrackId: string | null;
    isPlaying: boolean;
    loggedIn: boolean;
    onRetry: () => void;
    onPlay: (index: number, shuffle?: boolean) => void;
    onStartRadio: () => Promise<void>;
    onToggleSubscription: () => Promise<void>;
    onOpenAlbum: (id: string) => void;
    onOpenPlaylist?: (id: string) => void;
    onPlaySong?: (item: BrowseCardDto) => void;
    onOpenArtist: (id: string) => void;
    onOpenCatalog: (id: string, params: string | null, title: string) => void;
  }

  let {
    artist,
    isLoading,
    error,
    currentTrackId,
    isPlaying,
    loggedIn,
    onRetry,
    onPlay,
    onStartRadio,
    onToggleSubscription,
    onOpenAlbum, onOpenPlaylist, onPlaySong,
    onOpenArtist,
    onOpenCatalog,
  }: Props = $props();

  let showDescription = $state(false);
  let radioPending = $state(false);
  let subscriptionPending = $state(false);
  let actionError = $state<string | null>(null);
  let avatarFailed = $state(false);
  const createMenu = createMenuHandlers();

  const visibleTopSongs = $derived(artist?.topSongs.slice(0, 5) ?? []);

  async function startRadio() {
    if (!artist?.radioPlaylistId || radioPending) return;
    actionError = null;
    radioPending = true;
    try {
      await onStartRadio();
    } catch (cause) {
      actionError = errorMessage(cause, $t('windows.ui.couldnTStartTheMix'));
    } finally {
      radioPending = false;
    }
  }

  async function toggleSubscription() {
    if (!loggedIn || !artist || subscriptionPending) return;
    actionError = null;
    subscriptionPending = true;
    try {
      await onToggleSubscription();
    } catch (cause) {
      actionError = errorMessage(cause, $t('windows.ui.couldnTUpdateTheSubscription'));
    } finally {
      subscriptionPending = false;
    }
  }

  function errorMessage(cause: unknown, fallback: string): string {
    return cause instanceof Error && cause.message ? cause.message : fallback;
  }



  function openCard(card: BrowseCardDto) {
    if (card.kind === "album") onOpenAlbum(card.id);
    if (card.kind === "artist") onOpenArtist(card.id);
    if (card.kind === "playlist" || card.kind === "mix") onOpenPlaylist?.(card.id);
    if (["song", "video"].includes(card.kind)) onPlaySong?.(card);
  }
</script>

<svelte:head>
  <title>{artist?.name ?? $t('menu.sort_artist')} · Side B</title>
</svelte:head>

<div class="artist-page">
  {#if isLoading}
    <div class="artist-content" aria-busy="true" aria-label={$t('windows.ui.loadingArtist')}>
      <div class="skeleton-header">
        <div class="skeleton-avatar"></div>
        <div class="skeleton-lines"><span></span><span></span><span></span></div>
      </div>
      <div class="loading"><span class="spinner"></span><span>{$t('windows.ui.loadingArtist')}</span></div>
    </div>
  {:else if error}
    <div class="state-card" role="alert">
      <span class="state-icon">⚠</span>
      <h2>{$t('detail.artist.loadFailed')}</h2>
      <p>{resolveMessage(error, $language)}</p>
      <button class="action-button primary" type="button" onclick={onRetry}>{$t('sidebar.retry')}</button>
    </div>
  {:else if artist}
    {@const artistCard = { kind: 'artist', id: artist.channelId, title: artist.name, subtitle: artist.subscribers, thumbnail: artist.thumbnail, duration: null }}
    {@const artistMenu = createMenu(() => ({ kind: 'artist', card: artistCard, detail: artist }), { view: 'artist_detail', currentId: artist.channelId })}
    <div class="artist-content">
      <header class="artist-header" role="group" oncontextmenu={artistMenu.onContextMenu}>
        {#if artist.thumbnail && !avatarFailed}
          <img class="avatar" src={artist.thumbnail} alt="" onerror={() => avatarFailed = true} />
        {:else}
          <div class="avatar avatar-fallback" aria-hidden="true">♬</div>
        {/if}

        <div class="artist-info">
          <div class="eyebrow">{$t('detail.kind.artist')}</div>
          <h1>{artist.name}</h1>
          {#if artist.subscribers || artist.monthlyListeners}
            <div class="stats">
              {#if artist.subscribers}<span>{artist.subscribers}</span>{/if}
              {#if artist.subscribers && artist.monthlyListeners}<span aria-hidden="true">•</span>{/if}
              {#if artist.monthlyListeners}<span>{artist.monthlyListeners}</span>{/if}
            </div>
          {/if}
          {#if artist.description}
            <button class="description-preview" type="button" onclick={() => (showDescription = true)} aria-label={$t('windows.ui.readFullBiography')}>
              <span>{artist.description}</span><b>{$t('detail.more')}</b>
            </button>
          {/if}
          <div class="actions">
            {#if artist.radioPlaylistId}
              <button class="action-button primary" type="button" onclick={startRadio} disabled={radioPending}>
                {radioPending ? $t('windows.ui.starting') : '◉ ' + $t('detail.artist.startMix')}
              </button>
            {/if}
            {#if artist.topSongs.length > 0}
              <button class="action-button" type="button" onclick={() => onPlay(0, true)}>⤨ {$t('player.shuffle')}</button>
            {/if}
            {#if loggedIn}
              <button class="action-button" type="button" onclick={toggleSubscription} disabled={subscriptionPending}>
                {subscriptionPending ? $t('windows.ui.refreshing') : artist.subscribed ? '♧ ' + $t('detail.artist.subscribed') : '♧ ' + $t('detail.artist.subscribe')}
              </button>
            {/if}
            <button class="more-menu-trigger" type="button" aria-label={$t('menu.more_options')} title={$t('menu.more_options')} aria-haspopup="menu" onclick={artistMenu.onContextMenu} onkeydown={artistMenu.onKeyDown}><MoreIcon /></button>
          </div>
          {#if actionError}<p class="action-error" role="alert">{resolveMessage(actionError, $language)}</p>{/if}
        </div>
      </header>

      <div class="divider"></div>

      {#if visibleTopSongs.length > 0}
        <section class="top-songs" aria-labelledby="top-songs-title">
          <div class="top-songs-heading"><h2 id="top-songs-title">{$t('detail.artist.topSongs')}</h2>
            {#if artist.topSongsId && onOpenPlaylist}<button class="see-all" type="button" onclick={() => onOpenPlaylist?.(artist!.topSongsId!)}>{$t('home.see_all')}</button>{/if}
          </div>
          <TrackTable items={visibleTopSongs} {currentTrackId} {isPlaying} onPlay={index=>onPlay(index)} {onOpenArtist} {onOpenAlbum} source={{kind:'artist',id:artist.channelId}} />
        </section>
      {/if}

      {#each artist.sections as section, sectionIndex (`${section.title}:${sectionIndex}`)}
        {#if section.items.length > 0}
          <section class="carousel-section" aria-label={providerHeading(section.title,$language)}>
            <div class="section-heading">
              <h2>{providerHeading(section.title,$language)}</h2>
              {#if section.moreBrowseId && !section.moreBrowseId.startsWith("FE")}
                <button class="see-all" type="button" onclick={() => onOpenCatalog(section.moreBrowseId!, section.moreParams, section.title)}>{$t('home.see_all')}</button>
              {/if}
            </div>
            <div class="carousel">
              {#each section.items as card, index (`${card.kind}:${card.id}:${index}`)}
                <div class="carousel-card"><MediaCard {card} onOpen={()=>openCard(card)} onPlay={()=>onPlaySong?.(card)} {onOpenArtist} {onOpenAlbum} /></div>
              {/each}
            </div>
          </section>
        {/if}
      {/each}
    </div>
  {:else}
    <div class="state-card">
      <h2>{$t('windows.ui.noArtistDataAvailable')}</h2>
    </div>
  {/if}
</div>



{#if showDescription && artist?.description}
  <DescriptionModal title={artist.name} description={artist.description} onClose={() => (showDescription = false)} />
{/if}

<style>.artist-page { min-height: 100%; padding: 14px 0 120px; color: var(--text-primary, #f5f5f6); }.artist-content { display: flex; flex-direction: column; gap: 32px; padding: 28px 32px 0; }.artist-header { display: flex; align-items: center; gap: 28px; min-height: 180px; }.avatar { width: 180px; height: 180px; flex: 0 0 180px; border-radius: 50%; object-fit: cover; box-shadow: 0 8px 24px rgb(0 0 0 / 35%); }.avatar-fallback { display: grid; place-items: center; color: #fff; font-size: 64px; background: linear-gradient(135deg, rgb(163 61 69 / 55%), #1f1013); }.artist-info { display: flex; flex-direction: column; align-items: flex-start; min-width: 0; min-height: 180px; flex: 1; gap: 8px; }.eyebrow { color: var(--text-secondary, #aaaab0); font-size: 11px; font-weight: 700; letter-spacing: 1.2px; }h1 { margin: 0; max-width: 100%; font-size: 34px; line-height: 1.12; font-weight: 700; overflow-wrap: anywhere; }.stats { display: flex; gap: 8px; color: var(--text-secondary, #aaaab0); font-size: 13px; font-weight: 500; }.description-preview { display: flex; align-items: flex-end; gap: 5px; max-width: 740px; max-height: 36px; overflow: hidden; padding: 2px 0 0; border: 0; background: transparent; color: var(--text-secondary, #aaaab0); text-align: left; font-size: 12px; line-height: 18px; cursor: pointer; }.description-preview span { display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; line-clamp: 2; overflow: hidden; }.description-preview b { flex: none; color: var(--text-primary, #eee); font-size: 11px; }.actions { display: flex; flex-wrap: wrap; align-items: center; gap: 10px 12px; margin-top: auto; }.action-button { min-height: 34px; padding: 7px 14px; border: 0; border-radius: 18px; background: rgb(255 255 255 / 10%); color: var(--text-primary, #f5f5f6); font-family: inherit; font-size: 13px; line-height: 20px; font-weight: 500; cursor: pointer; }.action-button:hover { background: rgb(255 255 255 / 16%); }.action-button.primary { padding-inline: 16px; background: rgb(255 255 255 / 16%); font-weight: 600; }.action-button:disabled { opacity: .6; cursor: wait; }.action-error { margin: 0; color: #f08a90; font-size: 12px; }.more-menu-trigger { display: grid; width: 34px; height: 34px; place-items: center; padding: 0; border: 0; border-radius: 50%; background: rgb(255 255 255 / 8%); color: #eee; font: inherit; font-weight: 700; letter-spacing: 1px; cursor: pointer; }.more-menu-trigger:hover { background: rgb(255 255 255 / 14%); }.divider { height: 1px; margin: 0 32px; background: rgb(255 255 255 / 12%); }.top-songs-heading { display: flex; align-items: center; justify-content: space-between; gap: 12px; }.top-songs { display: flex; flex-direction: column; gap: 12px; }h2 { margin: 0; font-size: 20px; font-weight: 700; }.carousel-section { display: flex; flex-direction: column; gap: 14px; margin-inline: -32px; }.section-heading { display: flex; align-items: center; justify-content: space-between; padding-inline: 32px; }.see-all { border: 0; background: transparent; color: var(--text-primary, #f3f3f5); font-family: inherit; font-size: 13px; font-weight: 600; cursor: pointer; }.see-all:hover { color: var(--sideb-highlight, #d06c70); }.carousel { display: flex; gap: 16px; overflow-x: auto; padding: 0 32px 4px; scrollbar-width: thin; }.carousel-card { display: flex; width: 144px; min-width: 144px; flex-direction: column; align-items: flex-start; gap: 6px; padding: 0; color: inherit; text-align: left; font: inherit; }.loading, .state-card { display: flex; min-height: 220px; flex-direction: column; align-items: center; justify-content: center; gap: 12px; color: var(--text-secondary, #aaaab0); text-align: center; }.state-card { margin: 0 32px; padding: 30px; }.state-card h2 { color: var(--text-primary, #eee); }.state-card p { max-width: 650px; margin: 0; font-size: 13px; }.state-icon { font-size: 32px; }.spinner { width: 18px; height: 18px; border: 2px solid rgb(255 255 255 / 22%); border-top-color: var(--sideb-highlight, #d06c70); border-radius: 50%; animation: spin .8s linear infinite; }.skeleton-header { display: flex; align-items: center; gap: 28px; }.skeleton-avatar { width: 180px; height: 180px; flex: 0 0 180px; border-radius: 50%; background: rgb(255 255 255 / 8%); }.skeleton-lines { display: flex; flex-direction: column; gap: 12px; }.skeleton-lines span { width: 260px; height: 18px; border-radius: 4px; background: rgb(255 255 255 / 7%); }.skeleton-lines span:first-child { width: 60px; height: 12px; }.skeleton-lines span:last-child { width: 160px; height: 14px; }
  @keyframes spin {to { transform: rotate(360deg); } }
  @media (max-width: 760px) {.artist-page { padding-top: 8px; }.artist-content { gap: 24px; padding-inline: 20px; }.artist-header { align-items: flex-start; gap: 18px; }.avatar { width: 112px; height: 112px; flex-basis: 112px; }.artist-info { min-height: 112px; }h1 { font-size: 27px; }.description-preview { max-height: 36px; }.description-preview span { -webkit-line-clamp: 2; line-clamp: 2; }.divider { margin-inline: 20px; }.carousel-section { margin-inline: -20px; }.section-heading, .carousel { padding-inline: 20px; }.skeleton-header { gap: 18px; }.skeleton-avatar { width: 112px; height: 112px; flex-basis: 112px; }.skeleton-lines span { width: 160px; } }
  @media (max-width: 520px) {.artist-header { flex-direction: column; align-items: flex-start; }.artist-info { min-height: 0; width: 100%; }.avatar { align-self: center; }.skeleton-header { align-items: flex-start; }.skeleton-avatar { width: 96px; height: 96px; flex-basis: 96px; }.skeleton-lines span { width: 120px; } }
</style>



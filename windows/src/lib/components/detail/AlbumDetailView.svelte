<script lang="ts" module>
  const presentations = new Map<string,string>();
</script>
<script lang="ts">
  import { untrack } from 'svelte';
  import { t , language, resolveMessage } from '$lib/i18n';
  import { providerHeading } from '$lib/i18n/presentation';
  import MediaCard from "../common/MediaCard.svelte";
  import type { AlbumDetailDto, BrowseCardDto } from "$lib/types";
  import DetailHeader from "./DetailHeader.svelte";
  import TrackTable from "./TrackTable.svelte";
  import DescriptionModal from "./DescriptionModal.svelte";
  import { createMenuHandlers } from "$lib/menu/hooks";
  import TrackFilter from './TrackFilter.svelte';
  import { projectTracks } from '$lib/detail/projection';
  import { albumTrackWithCredit } from '$lib/detail/metadata';

  interface Props {
    session?: string;
    album: AlbumDetailDto | null; isLoading: boolean; error: string | null;
    currentTrackId: string | null; isPlaying: boolean; loggedIn: boolean;
    onRetry: () => void; onPlay: (index: number, shuffle?: boolean) => void;
    onOpenArtist: (id: string) => void; onOpenAlbum: (id: string) => void;
    onOpenCatalog: (id: string, params: string | null, title: string) => void;
    onToggleLibrary: () => Promise<void>;
    onOpenPlaylist?: (id: string) => void; onPlaySong?: (item: BrowseCardDto) => void;
  }
  let {
    session = 'guest', album, isLoading, error, currentTrackId, isPlaying, loggedIn,
    onRetry, onPlay, onOpenArtist, onOpenAlbum, onOpenCatalog, onToggleLibrary, onOpenPlaylist, onPlaySong,
  }: Props = $props();
  let showDescription = $state(false);
  let query = $state('');
  $effect(()=>{
    const key=album?.browseId ? `${session}|${album.browseId}` : null;
    if(!key)return;
    untrack(()=>query=presentations.get(key)??'');
    return ()=>{presentations.delete(key);presentations.set(key,query);while(presentations.size>20)presentations.delete(presentations.keys().next().value!);};
  });
  const tracks = $derived(album ? album.items.map(song=>albumTrackWithCredit(song,album)) : []);
  const projection = $derived(projectTracks(tracks, query));
  const createMenu = createMenuHandlers();

  function openCard(card: BrowseCardDto) {
    if (card.kind === "artist") onOpenArtist(card.id);
    else if (card.kind === "album") onOpenAlbum(card.id);
    else if (card.kind === "playlist") onOpenPlaylist?.(card.id);
    else if (["song", "video"].includes(card.kind)) onPlaySong?.(card);
  }
  const showLoading = $derived(isLoading && !album);
  const showError = $derived(Boolean(error) && !album && !isLoading);
  const showEmpty = $derived(!album && !isLoading && !error);
</script>

<main class="album-page" aria-busy={isLoading}>
  {#if isLoading && album}<div class="topline"><span class="updating" role="status">{$t('windows.ui.refreshingAlbum')}</span></div>{/if}
  {#if showLoading}
    <div class="skeleton" role="status" aria-label={$t('windows.ui.loadingAlbum')}><div class="sk-art"></div><div class="sk-info"><i></i><i></i><i></i></div></div>
  {:else if showError}
    <section class="state" role="alert"><div class="state-icon">!</div><h2>{$t('detail.album.loadFailed')}</h2><p>{resolveMessage(error, $language)}</p><button type="button" class="retry" onclick={onRetry}>{$t('sidebar.retry')}</button></section>
  {:else if showEmpty}
    <section class="state"><div class="state-icon">♫</div><h2>{$t('windows.ui.albumUnavailable')}</h2><p>{$t('windows.ui.goBackOrTryLoadingItAgain')}</p><button type="button" class="retry" onclick={onRetry}>{$t('sidebar.retry')}</button></section>
  {:else if album}
    {@const albumCard = { kind: 'album', id: album.browseId, title: album.title, subtitle: album.artist, thumbnail: album.thumbnail, duration: null }}
    {@const albumMenu = createMenu(() => ({ kind: 'album', card: albumCard, detail: album }), { view: 'album_detail', currentId: album.browseId })}
    <div class="scroll-content">
      <div role="group" oncontextmenu={albumMenu.onContextMenu}>
        <DetailHeader {album} {loggedIn} {onPlay} {onOpenArtist} {onToggleLibrary} onDescription={() => showDescription = true}>
          {#snippet tools()}{#if album.items.length}<TrackFilter bind:query allowOrder={false} compact />{/if}{/snippet}
        </DetailHeader>
      </div>
      <div class="header-divider" aria-hidden="true"></div>
      {#if error}<div class="inline-error" role="status">{$t('windows.error.update', [resolveMessage(error, $language)])}<button type="button" onclick={onRetry}>{$t('sidebar.retry')}</button></div>{/if}
      {#if album.items.length}
        <TrackTable items={projection.map(entry=>entry.track)} occurrenceIndices={projection.map(entry=>entry.sourceIndex)} occurrenceKeys={projection.map(entry=>entry.key)} source={{kind:'album',id:album.browseId}} detail {currentTrackId} {isPlaying} onPlay={(index) => onPlay(projection[index].sourceIndex)} onOpenArtist={onOpenArtist} onOpenAlbum={onOpenAlbum} hideAlbumColumn origin={{ view: 'album_detail', currentId: album.browseId }} />
        {#if !projection.length}<p class="no-tracks">{$t('windows.ui.noSongsMatchYourSearch')}</p>{/if}
      {:else}<p class="no-tracks">{$t('windows.ui.thisAlbumHasNoSongsAvailableYet')}</p>{/if}
      {#if album.sections.length}
        <div class="sections">
          {#each album.sections as section, sectionIndex (`${section.title}-${sectionIndex}`)}
            {#if section.items.length}
              <section class="shelf" aria-label={providerHeading(section.title,$language)}>
                <div class="shelf-heading"><h2>{providerHeading(section.title,$language)}</h2>
                  {#if section.moreBrowseId && !section.moreBrowseId.startsWith("FE")}
                    <button type="button" class="see-more" onclick={() => onOpenCatalog(section.moreBrowseId!, section.moreParams, section.title)}>{$t('detail.viewAll')} <span aria-hidden="true">›</span></button>
                  {/if}
                </div>
                <div class="cards">
                  {#each section.items as card, cardIndex (`${card.kind}-${card.id}-${cardIndex}`)}
                    <div class="card"><MediaCard {card} onOpen={()=>openCard(card)} onPlay={()=>onPlaySong?.(card)} {onOpenArtist} {onOpenAlbum} /></div>
                  {/each}
                </div>
              </section>
            {/if}
          {/each}
        </div>
      {/if}
      <div class="bottom-space" aria-hidden="true"></div>
    </div>
  {/if}
  {#if showDescription && album?.description}<DescriptionModal title={album.title} description={album.description} onClose={() => showDescription = false} />{/if}
</main>

<style>.album-page { position: relative; box-sizing: border-box; min-width: 0; min-height: 100%; color: #f7f7f8; background: transparent; }.header-divider { height: 1px; margin: 0 32px 8px; background: rgb(255 255 255 / 12%); }.scroll-content { min-width: 0; padding-bottom: 0; }.topline { position: sticky; z-index: 2; top: 0; display: flex; min-height: 38px; align-items: center; justify-content: space-between; padding: 0 20px; background: linear-gradient(#1b1b1e 75%, transparent); }.updating { color: #aaaab1; font-size: 11px; }.skeleton { display: flex; gap: 24px; padding: 20px 32px 22px; }.sk-art { width: 180px; height: 180px; flex: none; border-radius: 10px; background: #ffffff12; animation: pulse 1.3s ease-in-out infinite alternate; }.sk-info { display: flex; flex-direction: column; gap: 14px; padding-top: 8px; }.sk-info i { width: 260px; height: 15px; border-radius: 5px; background: #ffffff12; }.sk-info i:first-child { width: 90px; height: 11px; }.sk-info i:nth-child(2) { width: min(420px, 45vw); height: 30px; }
  @keyframes pulse {to { opacity: .5; } }.state { display: flex; min-height: 300px; flex-direction: column; align-items: center; justify-content: center; gap: 11px; padding: 24px; color: #b9b9c0; text-align: center; }.state h2 { margin: 0; color: #f7f7f8; font-size: 19px; }.state p { max-width: 50ch; margin: 0; font-size: 13px; }.state-icon { display: grid; width: 48px; height: 48px; place-items: center; border-radius: 50%; color: #d0d0d6; background: #ffffff0d; font-size: 25px; }.retry { margin-top: 5px; padding: 8px 15px; border: 0; border-radius: 999px; color: white; background: var(--sideb-accent); font: inherit; font-size: 13px; cursor: pointer; }.inline-error { display: flex; align-items: center; gap: 10px; margin: 0 32px 8px; padding: 8px 12px; border-radius: 7px; color: #ffd5d5; background: #9d303033; font-size: 12px; }.inline-error button { margin-left: auto; border: 0; color: inherit; background: transparent; font: inherit; text-decoration: underline; cursor: pointer; }.no-tracks { padding: 20px 32px; color: #a6a6ad; font-size: 13px; }.sections { display: flex; flex-direction: column; gap: 24px; padding-top: 24px; }.shelf { min-width: 0; }.shelf-heading { display: flex; min-height: 36px; align-items: center; justify-content: space-between; gap: 12px; padding: 0 32px; }.shelf-heading h2 { margin: 0; font-size: 20px; font-weight: 700; }.see-more { border: 0; color: #b9b9c0; background: transparent; font: inherit; font-size: 12px; cursor: pointer; }.see-more:hover { color: white; }.cards { display: flex; gap: 16px; overflow-x: auto; padding: 10px 32px 16px; scrollbar-color: #ffffff2a transparent; }.card { display: flex; width: 160px; min-width: 0; flex: 0 0 160px; flex-direction: column; align-items: flex-start; gap: 5px; }.bottom-space { height: 120px; }button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 3px; }
  @media (max-width: 680px) {.skeleton { gap: 16px; padding: 16px 18px; }.sk-art { width: 128px; height: 128px; }.shelf-heading { padding: 0 18px; }.cards { padding-right: 18px; padding-left: 18px; } }
  @media (prefers-reduced-motion: reduce) {.sk-art { animation: none; } }
</style>

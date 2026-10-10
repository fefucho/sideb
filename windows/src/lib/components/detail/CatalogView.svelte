<script lang="ts">
  import { t , language, resolveMessage } from '$lib/i18n';
  import { providerHeading } from '$lib/i18n/presentation';
  import MediaCard from "../common/MediaCard.svelte";
  import type { BrowseCardDto } from "$lib/types";

  interface Props {
    title: string;
    items: BrowseCardDto[];
    isLoading: boolean;
    error: string | null;
    onRetry: () => void;
    onOpenAlbum: (id: string) => void;
    onOpenArtist: (id: string) => void;
    onOpenPlaylist?: (id: string) => void;
    onPlaySong?: (item: BrowseCardDto) => void;
  }

  let {
    title,
    items,
    isLoading,
    error,
    onRetry,
    onOpenAlbum,
    onOpenArtist,
    onPlaySong, onOpenPlaylist,
  }: Props = $props();




  function activate(item: BrowseCardDto) {
    if (item.kind === "album") onOpenAlbum(item.id);
    else if (item.kind === "artist") onOpenArtist(item.id);
    else if (["song", "video"].includes(item.kind)) onPlaySong?.(item);
    else if (item.kind === "playlist" || item.kind === "mix") onOpenPlaylist?.(item.id);
  }
</script>

<svelte:head><title>{providerHeading(title,$language)} · Side B</title></svelte:head>

<div class="catalog-page">
  <main>
    <h1>{providerHeading(title,$language)}</h1>
    {#if isLoading}
      <div class="state" aria-busy="true" aria-label={$t('windows.ui.loadingCatalog')}>
        <div class="spinner"></div><p>{$t('windows.ui.loadingCatalog')}</p>
      </div>
    {:else if error}
      <div class="state" role="alert">
        <div class="state-icon">⚠</div>
        <h2>{$t('detail.artistCatalog.loadFailed')}</h2>
        <p>{resolveMessage(error, $language)}</p>
        <button type="button" class="retry" onclick={onRetry}>{$t('sidebar.retry')}</button>
      </div>
    {:else if items.length === 0}
      <div class="state"><div class="state-icon">▤</div><h2>{$t('detail.artistCatalog.empty')}</h2></div>
    {:else}
      <div class="grid">
        {#each items as item, index (`${item.kind}:${item.id}:${index}`)}
          <MediaCard card={item} onOpen={()=>activate(item)} onPlay={()=>onPlaySong?.(item)} {onOpenArtist} {onOpenAlbum} />
        {/each}
      </div>
    {/if}
  </main>
</div>



<style>.catalog-page { min-height: 100%; padding: 14px 0 120px; color: var(--text-primary, #f5f5f6); }main { padding: 0 32px; }h1 { margin: 0 0 20px; font-size: 28px; line-height: 1.2; font-weight: 700; }.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 150px), 1fr)); align-items: start; gap: 24px 18px; }.state { display: flex; min-height: 200px; flex-direction: column; align-items: center; justify-content: center; gap: 10px; color: var(--text-secondary, #aaaab0); text-align: center; }.state h2 { margin: 0; color: var(--text-primary, #eee); font-size: 17px; }.state p { max-width: 640px; margin: 0; font-size: 13px; }.state-icon { font-size: 30px; }.spinner { width: 20px; height: 20px; border: 2px solid rgb(255 255 255 / 22%); border-top-color: var(--sideb-highlight, #d06c70); border-radius: 50%; animation: spin .8s linear infinite; }.retry { padding: 7px 15px; border: 0; border-radius: 18px; background: var(--sideb-accent, #a33d45); color: white; font: inherit; cursor: pointer; }
  @keyframes spin {to { transform: rotate(360deg); } }
  @media (max-width: 600px) {main { padding-inline: 20px; }.grid { grid-template-columns: repeat(auto-fill, minmax(min(100%, 136px), 1fr)); gap: 20px 14px; } }
</style>


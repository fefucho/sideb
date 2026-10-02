<script lang="ts">
  import type { BrowseCardDto } from "$lib/types";
  import ArtistCredits from "$lib/components/ArtistCredits.svelte";
  import { createMenuHandlers } from "$lib/menu/hooks";
  import { targetFromCard } from "$lib/menu/types";

  interface Props {
    title: string;
    items: BrowseCardDto[];
    isLoading: boolean;
    error: string | null;
    onBack: () => void;
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
    onBack,
    onRetry,
    onOpenAlbum,
    onOpenArtist,
    onPlaySong, onOpenPlaylist,
  }: Props = $props();

  let failedImages = $state(new Set<string>());
  const createMenu = createMenuHandlers();

  function canActivate(item: BrowseCardDto): boolean {
    return item.kind === "album" || item.kind === "artist" || (["song", "video"].includes(item.kind) && Boolean(onPlaySong)) || (item.kind === "playlist" && Boolean(onOpenPlaylist));
  }

  function activate(item: BrowseCardDto) {
    if (item.kind === "album") onOpenAlbum(item.id);
    else if (item.kind === "artist") onOpenArtist(item.id);
    else if (["song", "video"].includes(item.kind)) onPlaySong?.(item);
    else if (item.kind === "playlist") onOpenPlaylist?.(item.id);
  }
</script>

<svelte:head><title>{title} · Side B</title></svelte:head>

<div class="catalog-page">
  <button class="back-button" type="button" onclick={onBack} aria-label="Volver">← <span>Volver</span></button>
  <main>
    <h1>{title}</h1>
    {#if isLoading}
      <div class="state" aria-busy="true" aria-label="Cargando catálogo">
        <div class="spinner"></div><p>Cargando catálogo…</p>
      </div>
    {:else if error}
      <div class="state" role="alert">
        <div class="state-icon">⚠</div>
        <h2>No se pudo cargar el catálogo</h2>
        <p>{error}</p>
        <button type="button" class="retry" onclick={onRetry}>Reintentar</button>
      </div>
    {:else if items.length === 0}
      <div class="state"><div class="state-icon">▤</div><h2>No hay publicaciones</h2></div>
    {:else}
      <div class="grid">
        {#each items as item, index (`${item.kind}:${item.id}:${index}`)}
          {@const menu = createMenu(() => targetFromCard(item), { view: 'catalog' })}
          <article class="card" role="group" aria-label={item.title} oncontextmenu={menu.onContextMenu}>
            {#if canActivate(item)}
              <button class="card-main interactive" type="button" onclick={() => activate(item)} onkeydown={menu.onKeyDown} aria-label={`${item.title}${item.subtitle ? `, ${item.subtitle}` : ''}`}>
                {@render cardContent(item)}
              </button>
            {:else}
              <div class="card-main informational" role="group" aria-label={`${item.title}; acción no disponible`}>
                {@render cardContent(item)}
              </div>
            {/if}
            {#if item.kind === 'artist'}
              {#if item.subtitle}<span class="subtitle">{item.subtitle}</span>{/if}
            {:else if item.kind === 'album'}
              {#if item.artistRuns?.length || item.artists?.trim()}
                <div class="card-credits"><ArtistCredits artistRuns={item.artistRuns} artists={item.artists} artistId={item.artistId} onOpenArtist={onOpenArtist} wrap /></div>
              {:else if item.subtitle}<span class="subtitle">{item.subtitle}</span>{/if}
            {:else if ['song', 'video'].includes(item.kind) && (item.artistRuns?.length || item.artists?.trim())}
              <div class="card-credits"><ArtistCredits artistRuns={item.artistRuns} artists={item.artists} artistId={item.artistId} onOpenArtist={onOpenArtist} album={item.album} albumId={item.albumId} onOpenAlbum={onOpenAlbum} wrap /></div>
            {:else if item.subtitle}<span class="subtitle">{item.subtitle}</span>{/if}
          </article>
        {/each}
      </div>
    {/if}
  </main>
</div>

{#snippet cardContent(item: BrowseCardDto)}
  <span class="artwork">
    {#if item.thumbnail && !failedImages.has(item.thumbnail)}<img class:round={item.kind === "artist"} src={item.thumbnail} alt="" loading="lazy" onerror={() => failedImages = new Set(failedImages).add(item.thumbnail!)} />
    {:else}<span class="art-fallback" class:round={item.kind === "artist"}>♪</span>{/if}
  </span>
  <span class="title">{item.title}</span>
{/snippet}

<style>
  .catalog-page { min-height: 100%; padding: 14px 0 120px; color: var(--text-primary, #f5f5f6); }
  .back-button { margin: 0 32px 4px; padding: 6px 0; border: 0; background: transparent; color: var(--text-secondary, #b3b3b8); font: inherit; cursor: pointer; }
  .back-button:hover { color: white; }
  main { padding: 0 32px; }
  h1 { margin: 0 0 20px; font-size: 28px; line-height: 1.2; font-weight: 700; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 150px), 1fr)); align-items: start; gap: 24px 18px; }
  .card { display: flex; width: 100%; max-width: 190px; min-width: 0; flex-direction: column; align-items: flex-start; gap: 6px; padding: 0; color: inherit; text-align: left; font: inherit; }
  .card-main { display: flex; width: 100%; min-width: 0; flex-direction: column; align-items: flex-start; gap: 7px; padding: 0; border: 0; background: transparent; color: inherit; text-align: left; font: inherit; }
  .interactive { cursor: pointer; }
  .interactive:hover .artwork { filter: brightness(1.08); }
  .informational { cursor: default; }
  .artwork { display: block; width: 100%; aspect-ratio: 1; overflow: hidden; border-radius: 10px; background: rgb(255 255 255 / 8%); }
  .artwork img, .art-fallback { display: grid; width: 100%; height: 100%; place-items: center; object-fit: cover; color: #aaa; font-size: 32px; }
  .artwork img.round, .art-fallback.round { border-radius: 50%; }
  .art-fallback { background: rgb(255 255 255 / 8%); }
  .title { max-width: 100%; display: -webkit-box; overflow: hidden; color: var(--text-primary, #f3f3f5); font-size: 13px; font-weight: 600; line-height: 18px; -webkit-box-orient: vertical; -webkit-line-clamp: 2; line-clamp: 2; }
  .subtitle { max-width: 100%; overflow: hidden; color: var(--text-secondary, #aaaab0); font-size: 11px; text-overflow: ellipsis; white-space: nowrap; }
  .card-credits { min-width: 0; max-width: 100%; color: var(--text-secondary, #aaaab0); font-size: 11px; line-height: 15px; }
  .state { display: flex; min-height: 200px; flex-direction: column; align-items: center; justify-content: center; gap: 10px; color: var(--text-secondary, #aaaab0); text-align: center; }
  .state h2 { margin: 0; color: var(--text-primary, #eee); font-size: 17px; }
  .state p { max-width: 640px; margin: 0; font-size: 13px; }
  .state-icon { font-size: 30px; }
  .spinner { width: 20px; height: 20px; border: 2px solid rgb(255 255 255 / 22%); border-top-color: var(--sideb-highlight, #d06c70); border-radius: 50%; animation: spin .8s linear infinite; }
  .retry { padding: 7px 15px; border: 0; border-radius: 18px; background: var(--sideb-accent, #a33d45); color: white; font: inherit; cursor: pointer; }
  @keyframes spin { to { transform: rotate(360deg); } }
  @media (max-width: 600px) { main { padding-inline: 20px; } .back-button { margin-inline: 20px; } .grid { grid-template-columns: repeat(auto-fill, minmax(min(100%, 136px), 1fr)); gap: 20px 14px; } }
</style>


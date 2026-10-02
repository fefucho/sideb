<script lang="ts">
  import type { HomeChipDto, HomeItemDto, HomeSectionDto } from "$lib/types";
  import { onMount } from "svelte";
  import { homeSections } from "$lib/home/presentation";
  import HomeShelf from "./HomeShelf.svelte";

  interface Props {
    chips: HomeChipDto[];
    sections: HomeSectionDto[];
    selectedChipParams: string | null;
    isLoading: boolean;
    error: string | null;
    onSelectChip: (params: string | null) => void;
    onRetry: () => void;
    onOpenAlbum?: (browseId: string) => void;
    onPlaySong?: (item: HomeItemDto) => void;
    onOpenPlaylist?: (id: string) => void;
    onOpenArtist?: (id: string) => void;
    onOpenCatalog?: (id: string, params: string | null, title: string) => void;
    hasMore: boolean;
    isLoadingMore: boolean;
    moreError: string | null;
    onLoadMore: () => void;
  }

  let {
    chips,
    sections,
    selectedChipParams,
    isLoading,
    error,
    onSelectChip,
    onRetry,
    onOpenAlbum,
    onPlaySong,
    onOpenArtist, onOpenPlaylist, onOpenCatalog, hasMore, isLoadingMore, moreError, onLoadMore,
  }: Props = $props();

  let visibleSections = $derived(homeSections(sections, selectedChipParams));
  let sentinel: HTMLDivElement;
  onMount(() => {
    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting && hasMore && !isLoading && !isLoadingMore && !moreError) onLoadMore();
    }, { root: document.querySelector(".content-column"), rootMargin: "300px" });
    observer.observe(sentinel);
    return () => observer.disconnect();
  });
</script>

<section class="home" aria-label="Inicio" aria-busy={isLoading}>
  <header class="heading">
    <h1>Inicio</h1>
    <p>Escucha de nuevo y descubre algo nuevo</p>
  </header>

  {#if chips.length > 0}
    <nav class="chips" aria-label="Filtros de Inicio">
      <button
        type="button"
        class:active={selectedChipParams === null}
        aria-pressed={selectedChipParams === null}
        disabled={isLoading || selectedChipParams === null}
        onclick={() => onSelectChip(null)}
      >Todos</button>
      {#each chips as chip (chip.params)}
        <button
          type="button"
          class:active={selectedChipParams === chip.params}
          aria-pressed={selectedChipParams === chip.params}
          disabled={isLoading || selectedChipParams === chip.params}
          onclick={() => onSelectChip(chip.params)}
        >{chip.title}</button>
      {/each}
    </nav>
  {/if}

  {#if visibleSections.length === 0}
    {#if isLoading}
      <div class="state" role="status"><span class="spinner" aria-hidden="true"></span>Cargando recomendaciones…</div>
    {:else if error}
      <div class="state" role="alert">
        <h2>No se pudo cargar Inicio</h2>
        <p>{error}</p>
        <button type="button" class="retry" onclick={onRetry}>Reintentar</button>
      </div>
    {:else}
      <div class="state">
        <h2>Sin contenido por ahora</h2>
        <p>No hay recomendaciones para este filtro.</p>
      </div>
    {/if}
  {:else}
    {#if isLoading || error}
      <div class="status" role="status">
        {#if isLoading}
          <span class="spinner" aria-hidden="true"></span>
          <span>Actualizando recomendaciones…</span>
        {:else}
          <span>No se pudo actualizar: {error}</span>
          <button type="button" onclick={onRetry}>Reintentar</button>
        {/if}
      </div>
    {/if}

    <div class="feed">
      {#each visibleSections as section (section.id)}
        <HomeShelf {section} {onOpenAlbum} {onPlaySong} {onOpenArtist} {onOpenPlaylist} {onOpenCatalog} />
      {/each}
    </div>
  {/if}
  <div class="load-more" bind:this={sentinel}>
    {#if isLoadingMore}<span class="spinner" aria-hidden="true"></span><span role="status">Cargando más categorías…</span>
    {:else if moreError}<p role="alert">{moreError}</p><button type="button" class="retry" onclick={onLoadMore}>Reintentar</button>
    {:else if hasMore}<button type="button" class="retry" onclick={onLoadMore}>Cargar más categorías</button>{/if}
  </div>
</section>

<style>
  .home {
    container-type: inline-size;
    container-name: home-content;
    box-sizing: border-box;
    min-width: 0;
    min-height: 100%;
    color: #f7f7f8;
    background: var(--sideb-background, #1b1b1e);
  }
  .load-more { display: flex; align-items: center; justify-content: center; gap: 12px; padding: 0 28px 120px; min-height: 24px; color: #aaaab1; font-size: 13px; }

  .heading {
    padding: var(--home-header-inset-block-start, 24px) var(--home-header-inset-inline, 28px)
      var(--home-header-inset-block-end, 12px);
  }

  .heading h1 {
    margin: 0;
    font-size: 27px;
    line-height: 1.2;
    font-weight: 700;
  }

  .heading p {
    margin: 3px 0 0;
    color: var(--sideb-secondary-foreground, #a6a6ad);
    font-size: 13px;
    line-height: 1.25;
  }

  .chips {
    box-sizing: border-box;
    display: flex;
    align-items: center;
    gap: var(--home-chip-gap, 8px);
    height: var(--home-chip-band-height, 42px);
    margin-bottom: var(--home-chip-band-margin-block-end, 4px);
    padding: 0 var(--home-header-inset-inline, 28px);
    overflow-x: auto;
    scrollbar-width: none;
  }

  .chips::-webkit-scrollbar { display: none; }

  .chips button {
    flex: none;
    padding: var(--home-chip-padding-block, 7px) var(--home-chip-padding-inline, 14px);
    border: 1px solid transparent;
    border-radius: 999px;
    color: inherit;
    background: var(--sideb-surface, rgb(255 255 255 / 5%));
    font: inherit;
    font-size: 13px;
    line-height: 1.3;
    cursor: pointer;
  }

  .chips button.active {
    background: var(--sideb-accent, #a33d45);
    font-weight: 650;
  }

  .chips button:hover:not(:disabled) { background: rgb(255 255 255 / 12%); }
  .chips button.active:hover { background: var(--sideb-accent, #a33d45); }
  .chips button:disabled { cursor: default; }

  button:focus-visible {
    outline: 2px solid var(--sideb-highlight, #d06c70);
    outline-offset: 3px;
  }

  .feed {
    display: flex;
    flex-direction: column;
    gap: 0;
    min-width: 0;
    padding: var(--home-feed-inset-block-start, 10px) 0 0;
  }

  .state {
    box-sizing: border-box;
    display: flex;
    min-height: 230px;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    padding: 24px 28px 120px;
    color: #b9b9c0;
    text-align: center;
  }

  .state h2 { margin: 0; color: inherit; font-size: 18px; }
  .state p { max-width: 45ch; margin: 0; font-size: 13px; }

  .retry, .status button {
    border: 1px solid var(--sideb-highlight, #d06c70);
    border-radius: 7px;
    padding: 7px 12px;
    color: #fff;
    background: var(--sideb-accent, #a33d45);
    font: inherit;
    cursor: pointer;
  }

  .status {
    position: sticky;
    z-index: 1;
    top: 50px;
    box-sizing: border-box;
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 35px;
    margin: 0 28px;
    padding: 7px 12px;
    border-radius: 999px;
    color: #dedee2;
    background: rgb(48 48 54 / 94%);
    font-size: 12px;
  }

  .status button { margin-left: auto; padding: 4px 9px; }

  .spinner {
    display: inline-block;
    flex: none;
    width: 14px;
    height: 14px;
    border: 2px solid rgb(255 255 255 / 27%);
    border-top-color: var(--sideb-highlight, #d06c70);
    border-radius: 50%;
    animation: spin .8s linear infinite;
  }

  @keyframes spin { to { transform: rotate(360deg); } }
  @media (prefers-reduced-motion: reduce) { .spinner { animation: none; } }
</style>

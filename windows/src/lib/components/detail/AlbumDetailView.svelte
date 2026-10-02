<script lang="ts">
  import type { AlbumDetailDto, BrowseCardDto } from "$lib/types";
  import ArtistCredits from "$lib/components/ArtistCredits.svelte";
  import DetailHeader from "./DetailHeader.svelte";
  import TrackTable from "./TrackTable.svelte";
  import DescriptionModal from "./DescriptionModal.svelte";
  import { createMenuHandlers } from "$lib/menu/hooks";
  import { targetFromCard } from "$lib/menu/types";

  interface Props {
    album: AlbumDetailDto | null; isLoading: boolean; error: string | null;
    currentTrackId: string | null; isPlaying: boolean; loggedIn: boolean;
    onBack: () => void; onRetry: () => void; onPlay: (index: number, shuffle?: boolean) => void;
    onOpenArtist: (id: string) => void; onOpenAlbum: (id: string) => void;
    onOpenCatalog: (id: string, params: string | null, title: string) => void;
    onToggleLibrary: () => Promise<void>;
    onOpenPlaylist?: (id: string) => void; onPlaySong?: (item: BrowseCardDto) => void;
  }
  let {
    album, isLoading, error, currentTrackId, isPlaying, loggedIn,
    onBack, onRetry, onPlay, onOpenArtist, onOpenAlbum, onOpenCatalog, onToggleLibrary, onOpenPlaylist, onPlaySong,
  }: Props = $props();
  let showDescription = $state(false);
  let failedCardImages = $state(new Set<string>());
  const createMenu = createMenuHandlers();
  function canOpenCard(card: BrowseCardDto) {
    return ["artist", "album"].includes(card.kind) || (card.kind === "playlist" && Boolean(onOpenPlaylist)) || (["song", "video"].includes(card.kind) && Boolean(onPlaySong));
  }
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
  <div class="topline"><button type="button" class="back" onclick={onBack} aria-label="Volver">‹ <span>Volver</span></button>
    {#if isLoading && album}<span class="updating" role="status">Actualizando álbum…</span>{/if}</div>
  {#if showLoading}
    <div class="skeleton" role="status" aria-label="Cargando álbum"><div class="sk-art"></div><div class="sk-info"><i></i><i></i><i></i></div></div>
  {:else if showError}
    <section class="state" role="alert"><div class="state-icon">!</div><h2>No se pudo cargar el álbum</h2><p>{error}</p><button type="button" class="retry" onclick={onRetry}>Reintentar</button></section>
  {:else if showEmpty}
    <section class="state"><div class="state-icon">♫</div><h2>Álbum no disponible</h2><p>Vuelve atrás o intenta cargarlo de nuevo.</p><button type="button" class="retry" onclick={onRetry}>Reintentar</button></section>
  {:else if album}
    {@const albumCard = { kind: 'album', id: album.browseId, title: album.title, subtitle: album.artist, thumbnail: album.thumbnail, duration: null }}
    {@const albumMenu = createMenu(() => ({ kind: 'album', card: albumCard, detail: album }), { view: 'album_detail', currentId: album.browseId })}
    <div class="scroll-content">
      <div role="group" oncontextmenu={albumMenu.onContextMenu}>
        <DetailHeader {album} {loggedIn} {onPlay} {onOpenArtist} {onToggleLibrary} onDescription={() => showDescription = true} />
      </div>
      <div class="header-divider" aria-hidden="true"></div>
      {#if error}<div class="inline-error" role="status">No se pudo actualizar: {error}<button type="button" onclick={onRetry}>Reintentar</button></div>{/if}
      {#if album.items.length}
        <TrackTable items={album.items} {currentTrackId} {isPlaying} onPlay={(index) => onPlay(index)} onOpenArtist={onOpenArtist} onOpenAlbum={onOpenAlbum} hideAlbumColumn origin={{ view: 'album_detail', currentId: album.browseId }} />
      {:else}<p class="no-tracks">Este álbum todavía no tiene canciones disponibles.</p>{/if}
      {#if album.sections.length}
        <div class="sections">
          {#each album.sections as section, sectionIndex (`${section.title}-${sectionIndex}`)}
            {#if section.items.length}
              <section class="shelf" aria-label={section.title}>
                <div class="shelf-heading"><h2>{section.title}</h2>
                  {#if section.moreBrowseId && !section.moreBrowseId.startsWith("FE")}
                    <button type="button" class="see-more" onclick={() => onOpenCatalog(section.moreBrowseId!, section.moreParams, section.title)}>Ver más <span aria-hidden="true">›</span></button>
                  {/if}
                </div>
                <div class="cards">
                  {#each section.items as card, cardIndex (`${card.kind}-${card.id}-${cardIndex}`)}
                    {@const canNavigate = canOpenCard(card)}
                    {@const imageKey = `${card.kind}-${card.id}-${cardIndex}`}
                    {@const menu = createMenu(() => targetFromCard(card), { view: 'album_detail', currentId: album.browseId })}
                    <article class="card" role="group" aria-label={card.title} oncontextmenu={menu.onContextMenu}>
                      {#if canNavigate}
                        <button type="button" class="card-main" aria-label={`${card.kind === "artist" ? "Ver artista" : "Abrir álbum"}: ${card.title}${card.subtitle ? `, ${card.subtitle}` : ""}`} onclick={() => openCard(card)} onkeydown={menu.onKeyDown}>
                          {#if card.thumbnail && !failedCardImages.has(imageKey)}<img class:artist-art={card.kind === "artist"} src={card.thumbnail} alt="" loading="lazy" onerror={() => failedCardImages = new Set(failedCardImages).add(imageKey)} />{:else}<div class="card-placeholder" class:artist-art={card.kind === "artist"} aria-hidden="true">♫</div>{/if}
                          <span class="card-title">{card.title}</span>
                        </button>
                      {:else}
                        <div class="card-main informational" role="group" aria-label={`${card.title}${card.subtitle ? `, ${card.subtitle}` : ""}`}>
                          {#if card.thumbnail && !failedCardImages.has(imageKey)}<img src={card.thumbnail} alt="" loading="lazy" onerror={() => failedCardImages = new Set(failedCardImages).add(imageKey)} />{:else}<div class="card-placeholder" aria-hidden="true">♫</div>{/if}
                          <span class="card-title">{card.title}</span>
                        </div>
                      {/if}
                      {#if card.kind === 'artist'}
                        {#if card.subtitle}<span class="card-subtitle">{card.subtitle}</span>{/if}
                      {:else if card.kind === 'album'}
                        {#if card.artistRuns?.length || card.artists?.trim()}<div class="card-credits"><ArtistCredits artistRuns={card.artistRuns} artists={card.artists} artistId={card.artistId} {onOpenArtist} wrap /></div>
                        {:else if card.subtitle}<span class="card-subtitle">{card.subtitle}</span>{/if}
                      {:else if ['song', 'video'].includes(card.kind) && (card.artistRuns?.length || card.artists?.trim())}
                        <div class="card-credits"><ArtistCredits artistRuns={card.artistRuns} artists={card.artists} artistId={card.artistId} {onOpenArtist} album={card.album} albumId={card.albumId} {onOpenAlbum} wrap /></div>
                      {:else if card.subtitle}<span class="card-subtitle">{card.subtitle}</span>{/if}
                    </article>
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

<style>
  .album-page { position: relative; box-sizing: border-box; min-width: 0; min-height: 100%; color: #f7f7f8; background: var(--sideb-background, #1b1b1e); }
  .header-divider { height: 1px; margin: 0 32px 8px; background: rgb(255 255 255 / 12%); }
  .scroll-content { min-width: 0; padding-bottom: 0; }
  .topline { position: sticky; z-index: 2; top: 0; display: flex; min-height: 38px; align-items: center; justify-content: space-between; padding: 0 20px; background: linear-gradient(#1b1b1e 75%, transparent); }
  .back { padding: 4px 8px; border: 0; border-radius: 6px; color: #dddde2; background: transparent; font: inherit; font-size: 13px; cursor: pointer; }
  .back:hover { background: var(--sideb-surface); } .back:first-letter { font-size: 20px; vertical-align: -1px; }
  .updating { color: #aaaab1; font-size: 11px; }
  .skeleton { display: flex; gap: 24px; padding: 20px 32px 22px; }
  .sk-art { width: 180px; height: 180px; flex: none; border-radius: 10px; background: #ffffff12; animation: pulse 1.3s ease-in-out infinite alternate; }
  .sk-info { display: flex; flex-direction: column; gap: 14px; padding-top: 8px; }
  .sk-info i { width: 260px; height: 15px; border-radius: 5px; background: #ffffff12; } .sk-info i:first-child { width: 90px; height: 11px; } .sk-info i:nth-child(2) { width: min(420px, 45vw); height: 30px; }
  @keyframes pulse { to { opacity: .5; } }
  .state { display: flex; min-height: 300px; flex-direction: column; align-items: center; justify-content: center; gap: 11px; padding: 24px; color: #b9b9c0; text-align: center; }
  .state h2 { margin: 0; color: #f7f7f8; font-size: 19px; } .state p { max-width: 50ch; margin: 0; font-size: 13px; }
  .state-icon { display: grid; width: 48px; height: 48px; place-items: center; border-radius: 50%; color: #d0d0d6; background: #ffffff0d; font-size: 25px; }
  .retry { margin-top: 5px; padding: 8px 15px; border: 0; border-radius: 999px; color: white; background: var(--sideb-accent); font: inherit; font-size: 13px; cursor: pointer; }
  .inline-error { display: flex; align-items: center; gap: 10px; margin: 0 32px 8px; padding: 8px 12px; border-radius: 7px; color: #ffd5d5; background: #9d303033; font-size: 12px; }
  .inline-error button { margin-left: auto; border: 0; color: inherit; background: transparent; font: inherit; text-decoration: underline; cursor: pointer; }
  .no-tracks { padding: 20px 32px; color: #a6a6ad; font-size: 13px; }
  .sections { display: flex; flex-direction: column; gap: 24px; padding-top: 24px; }
  .shelf { min-width: 0; }
  .shelf-heading { display: flex; min-height: 36px; align-items: center; justify-content: space-between; gap: 12px; padding: 0 32px; }
  .shelf-heading h2 { margin: 0; font-size: 20px; font-weight: 700; }
  .see-more { border: 0; color: #b9b9c0; background: transparent; font: inherit; font-size: 12px; cursor: pointer; } .see-more:hover { color: white; }
  .cards { display: flex; gap: 16px; overflow-x: auto; padding: 10px 32px 16px; scrollbar-color: #ffffff2a transparent; }
  .card { display: flex; width: 160px; min-width: 0; flex: 0 0 160px; flex-direction: column; align-items: flex-start; gap: 5px; }
  .card-main { display: flex; width: 100%; flex-direction: column; align-items: flex-start; padding: 0; border: 0; border-radius: 8px; color: inherit; background: transparent; text-align: left; cursor: pointer; }
  .card-main:hover { background: var(--sideb-surface-hover); }
  .card-main:hover img, .card-main:hover .card-placeholder { filter: brightness(1.08); }
  .card-main img, .card-placeholder { box-sizing: border-box; width: 160px; height: 160px; object-fit: cover; border-radius: 12px; background: #303036; }
  .card-main img.artist-art, .card-placeholder.artist-art { border-radius: 50%; }
  .card-placeholder { display: grid; place-items: center; color: #c8c8ce; font-size: 42px; }
  .card-title { display: -webkit-box; overflow: hidden; margin-top: 9px; color: #f1f1f3; font-size: 14px; font-weight: 600; line-height: 18px; -webkit-box-orient: vertical; -webkit-line-clamp: 2; line-clamp: 2; }
  .card-subtitle { overflow: hidden; margin-top: 3px; color: #aaaab1; font-size: 12px; text-overflow: ellipsis; white-space: nowrap; }
  .card-credits { min-width: 0; max-width: 100%; color: #aaaab1; font-size: 12px; line-height: 16px; }
  .bottom-space { height: 120px; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 3px; }
  @media (max-width: 680px) { .skeleton { gap: 16px; padding: 16px 18px; } .sk-art { width: 128px; height: 128px; } .shelf-heading { padding: 0 18px; } .cards { padding-right: 18px; padding-left: 18px; } }
  @media (prefers-reduced-motion: reduce) { .sk-art { animation: none; } }
</style>

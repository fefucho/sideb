<script lang="ts">
  import type { ArtistDetailDto, BrowseCardDto } from "$lib/types";
  import ArtistCredits from "$lib/components/ArtistCredits.svelte";
  import DescriptionModal from "./DescriptionModal.svelte";
  import { createMenuHandlers } from "$lib/menu/hooks";
  import { targetFromCard } from "$lib/menu/types";

  interface Props {
    artist: ArtistDetailDto | null;
    isLoading: boolean;
    error: string | null;
    currentTrackId: string | null;
    isPlaying: boolean;
    loggedIn: boolean;
    onBack: () => void;
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
    onBack,
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
  let failedImages = $state(new Set<string>());
  const createMenu = createMenuHandlers();

  const visibleTopSongs = $derived(artist?.topSongs.slice(0, 5) ?? []);

  async function startRadio() {
    if (!artist?.radioPlaylistId || radioPending) return;
    actionError = null;
    radioPending = true;
    try {
      await onStartRadio();
    } catch (cause) {
      actionError = errorMessage(cause, "No se pudo iniciar el mix.");
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
      actionError = errorMessage(cause, "No se pudo actualizar la suscripción.");
    } finally {
      subscriptionPending = false;
    }
  }

  function errorMessage(cause: unknown, fallback: string): string {
    return cause instanceof Error && cause.message ? cause.message : fallback;
  }

  function canOpenCard(card: BrowseCardDto): boolean {
    return card.kind === "album" || card.kind === "artist" || (card.kind === "playlist" && Boolean(onOpenPlaylist)) || (["song", "video"].includes(card.kind) && Boolean(onPlaySong));
  }

  function openCard(card: BrowseCardDto) {
    if (card.kind === "album") onOpenAlbum(card.id);
    if (card.kind === "artist") onOpenArtist(card.id);
    if (card.kind === "playlist") onOpenPlaylist?.(card.id);
    if (["song", "video"].includes(card.kind)) onPlaySong?.(card);
  }
</script>

<svelte:head>
  <title>{artist?.name ?? "Artista"} · Side B</title>
</svelte:head>

<div class="artist-page">
  <button class="back-button" type="button" onclick={onBack} aria-label="Volver">← <span>Volver</span></button>

  {#if isLoading}
    <div class="artist-content" aria-busy="true" aria-label="Cargando artista">
      <div class="skeleton-header">
        <div class="skeleton-avatar"></div>
        <div class="skeleton-lines"><span></span><span></span><span></span></div>
      </div>
      <div class="loading"><span class="spinner"></span><span>Cargando artista…</span></div>
    </div>
  {:else if error}
    <div class="state-card" role="alert">
      <span class="state-icon">⚠</span>
      <h2>No se pudo cargar el artista</h2>
      <p>{error}</p>
      <button class="action-button primary" type="button" onclick={onRetry}>Reintentar</button>
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
          <div class="eyebrow">ARTISTA</div>
          <h1>{artist.name}</h1>
          {#if artist.subscribers || artist.monthlyListeners}
            <div class="stats">
              {#if artist.subscribers}<span>{artist.subscribers}</span>{/if}
              {#if artist.subscribers && artist.monthlyListeners}<span aria-hidden="true">•</span>{/if}
              {#if artist.monthlyListeners}<span>{artist.monthlyListeners}</span>{/if}
            </div>
          {/if}
          {#if artist.description}
            <button class="description-preview" type="button" onclick={() => (showDescription = true)} aria-label="Leer biografía completa">
              <span>{artist.description}</span><b>más</b>
            </button>
          {/if}
          <div class="actions">
            {#if artist.radioPlaylistId}
              <button class="action-button primary" type="button" onclick={startRadio} disabled={radioPending}>
                {radioPending ? "Iniciando…" : "◉ Iniciar mix"}
              </button>
            {/if}
            {#if artist.topSongs.length > 0}
              <button class="action-button" type="button" onclick={() => onPlay(0, true)}>⤨ Aleatorio</button>
            {/if}
            {#if loggedIn}
              <button class="action-button" type="button" onclick={toggleSubscription} disabled={subscriptionPending}>
                {subscriptionPending ? "Actualizando…" : artist.subscribed ? "♧ Suscrito" : "♧ Suscribirse"}
              </button>
            {/if}
            <button class="more-menu-trigger" type="button" aria-label="Más opciones" title="Más opciones" aria-haspopup="menu" onclick={artistMenu.onContextMenu} onkeydown={artistMenu.onKeyDown}>•••</button>
          </div>
          {#if actionError}<p class="action-error" role="alert">{actionError}</p>{/if}
        </div>
      </header>

      <div class="divider"></div>

      {#if visibleTopSongs.length > 0}
        <section class="top-songs" aria-labelledby="top-songs-title">
          <div class="top-songs-heading"><h2 id="top-songs-title">Canciones principales</h2>
            {#if artist.topSongsId && onOpenPlaylist}<button class="see-all" type="button" onclick={() => onOpenPlaylist?.(artist!.topSongsId!)}>Ver todo</button>{/if}
          </div>
          <div class="top-song-list">
            {#each visibleTopSongs as song, index (`${song.videoId}:${index}`)}
              {@const songMenu = createMenu(() => ({ kind: 'song', song }), { view: 'artist_detail', currentId: artist.channelId })}
              <div class="top-song" role="group" class:current={currentTrackId === song.videoId} oncontextmenu={songMenu.onContextMenu}>
                <button class="song-index" type="button" aria-label={`Reproducir ${song.title}`} onclick={() => onPlay(index)}>{currentTrackId === song.videoId && isPlaying ? "♫" : index + 1}</button>
                <button class="song-art" type="button" aria-label={`Reproducir ${song.title}`} onclick={() => onPlay(index)}>
                  {#if song.thumbnail && !failedImages.has(song.thumbnail)}<img src={song.thumbnail} alt="" loading="lazy" onerror={() => failedImages = new Set(failedImages).add(song.thumbnail!)} />{:else}<span aria-hidden="true">♫</span>{/if}
                </button>
                <div class="song-text"><button class="song-title" type="button" onclick={() => onPlay(index)} onkeydown={songMenu.onKeyDown}>{song.title}</button>
                  <div class="song-subtitle"><ArtistCredits artistRuns={song.artistRuns} artists={song.artists} artistId={song.artistId} {onOpenArtist} album={song.album} albumId={song.albumId} {onOpenAlbum} /></div>
                </div>
                <span class="song-duration">{song.duration ?? ""}</span>
              </div>
            {/each}
          </div>
        </section>
      {/if}

      {#each artist.sections as section, sectionIndex (`${section.title}:${sectionIndex}`)}
        {#if section.items.length > 0}
          <section class="carousel-section" aria-label={section.title}>
            <div class="section-heading">
              <h2>{section.title}</h2>
              {#if section.moreBrowseId && !section.moreBrowseId.startsWith("FE")}
                <button class="see-all" type="button" onclick={() => onOpenCatalog(section.moreBrowseId!, section.moreParams, section.title)}>Ver todo</button>
              {/if}
            </div>
            <div class="carousel">
              {#each section.items as card, index (`${card.kind}:${card.id}:${index}`)}
                {@const cardMenu = createMenu(() => targetFromCard(card), { view: 'artist_detail', currentId: artist.channelId })}
                <article class="carousel-card" role="group" aria-label={card.title} class:video={card.kind === "video"} oncontextmenu={cardMenu.onContextMenu}>
                  {#if canOpenCard(card)}
                    <button class="carousel-card-main interactive-card" type="button" onclick={() => openCard(card)} onkeydown={cardMenu.onKeyDown} aria-label={`${card.title}${card.subtitle ? `, ${card.subtitle}` : ''}`}>
                      {@render cardContent(card)}
                    </button>
                  {:else}
                    <div class="carousel-card-main informational" role="group" aria-label={`${card.title}; acción no disponible`}>
                      {@render cardContent(card)}
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
  {:else}
    <div class="state-card">
      <h2>No hay datos del artista</h2>
      <button class="action-button" type="button" onclick={onBack}>Volver</button>
    </div>
  {/if}
</div>

{#snippet cardContent(card: BrowseCardDto)}
  <span class="card-art-wrap" class:artist={card.kind === "artist"}>
    {#if card.thumbnail && !failedImages.has(card.thumbnail)}<img class:round={card.kind === "artist"} src={card.thumbnail} alt="" loading="lazy" onerror={() => failedImages = new Set(failedImages).add(card.thumbnail!)} />
    {:else}<span class="card-art-fallback" class:round={card.kind === "artist"}>♪</span>{/if}
  </span>
  <span class="card-title">{card.title}</span>
{/snippet}

{#if showDescription && artist?.description}
  <DescriptionModal title={artist.name} description={artist.description} onClose={() => (showDescription = false)} />
{/if}

<style>
  .artist-page { min-height: 100%; padding: 14px 0 120px; color: var(--text-primary, #f5f5f6); }
  .back-button { margin: 0 32px 8px; padding: 6px 0; border: 0; background: transparent; color: var(--text-secondary, #b3b3b8); font: inherit; cursor: pointer; }
  .back-button:hover { color: white; }
  .artist-content { display: flex; flex-direction: column; gap: 32px; padding: 28px 32px 0; }
  .artist-header { display: flex; align-items: center; gap: 28px; min-height: 180px; }
  .avatar { width: 180px; height: 180px; flex: 0 0 180px; border-radius: 50%; object-fit: cover; box-shadow: 0 8px 24px rgb(0 0 0 / 35%); }
  .avatar-fallback { display: grid; place-items: center; color: #fff; font-size: 64px; background: linear-gradient(135deg, rgb(163 61 69 / 55%), #1f1013); }
  .artist-info { display: flex; flex-direction: column; align-items: flex-start; min-width: 0; min-height: 180px; flex: 1; gap: 8px; }
  .eyebrow { color: var(--text-secondary, #aaaab0); font-size: 11px; font-weight: 700; letter-spacing: 1.2px; }
  h1 { margin: 0; max-width: 100%; font-size: 34px; line-height: 1.12; font-weight: 700; overflow-wrap: anywhere; }
  .stats { display: flex; gap: 8px; color: var(--text-secondary, #aaaab0); font-size: 13px; font-weight: 500; }
  .description-preview { display: flex; align-items: flex-end; gap: 5px; max-width: 740px; max-height: 36px; overflow: hidden; padding: 2px 0 0; border: 0; background: transparent; color: var(--text-secondary, #aaaab0); text-align: left; font-size: 12px; line-height: 18px; cursor: pointer; }
  .description-preview span { display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; line-clamp: 2; overflow: hidden; }
  .description-preview b { flex: none; color: var(--text-primary, #eee); font-size: 11px; }
  .actions { display: flex; flex-wrap: wrap; align-items: center; gap: 10px 12px; margin-top: auto; }
  .action-button { min-height: 34px; padding: 7px 14px; border: 0; border-radius: 18px; background: rgb(255 255 255 / 10%); color: var(--text-primary, #f5f5f6); font-family: inherit; font-size: 13px; line-height: 20px; font-weight: 500; cursor: pointer; }
  .action-button:hover { background: rgb(255 255 255 / 16%); }
  .action-button.primary { padding-inline: 16px; background: rgb(255 255 255 / 16%); font-weight: 600; }
  .action-button:disabled { opacity: .6; cursor: wait; }
  .action-error { margin: 0; color: #f08a90; font-size: 12px; }
  .more-menu-trigger { display: grid; width: 34px; height: 34px; place-items: center; padding: 0; border: 0; border-radius: 50%; background: rgb(255 255 255 / 8%); color: #eee; font: inherit; font-weight: 700; letter-spacing: 1px; cursor: pointer; }
  .more-menu-trigger:hover { background: rgb(255 255 255 / 14%); }
  .divider { height: 1px; margin: 0 32px; background: rgb(255 255 255 / 12%); }
  .top-songs-heading { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
  .top-song-list { display: flex; flex-direction: column; gap: 4px; }
  .top-song { display: flex; align-items: center; gap: 14px; padding: 8px 10px; border-radius: 8px; }
  .top-song:hover { background: rgb(255 255 255 / 5%); }
  .top-song button { padding: 0; border: 0; background: transparent; color: inherit; font: inherit; cursor: pointer; }
  .song-index { flex: 0 0 24px; width: 24px; text-align: center; color: #aaaab1; font-size: 13px; }
  .song-art { flex: none; width: 44px; height: 44px; overflow: hidden; border-radius: 7px; background: #ffffff15 !important; }
  .song-art img { width: 100%; height: 100%; object-fit: cover; }
  .song-text { display: flex; flex-direction: column; gap: 2px; min-width: 0; flex: 1; }
  .top-song .song-title { overflow: hidden; color: #f2f2f4; text-align: left; text-overflow: ellipsis; white-space: nowrap; font-size: 13px; font-weight: 500; }
  .top-song.current .song-title { font-weight: 650; color: var(--sideb-highlight); }
  .top-song .song-subtitle { overflow: hidden; color: #aaaab1; text-align: left; text-overflow: ellipsis; white-space: nowrap; font-size: 12px; }
  .song-duration { flex: none; color: #aaaab1; font-size: 12px; font-variant-numeric: tabular-nums; }
  .carousel-card.video { width: 200px; min-width: 200px; }
  .carousel-card.video .card-art-wrap { width: 200px; height: 112px; }
  .card-art-wrap.artist { border-radius: 50%; }
  .top-songs { display: flex; flex-direction: column; gap: 12px; }
  h2 { margin: 0; font-size: 20px; font-weight: 700; }
  .carousel-section { display: flex; flex-direction: column; gap: 14px; margin-inline: -32px; }
  .section-heading { display: flex; align-items: center; justify-content: space-between; padding-inline: 32px; }
  .see-all { border: 0; background: transparent; color: var(--text-primary, #f3f3f5); font-family: inherit; font-size: 13px; font-weight: 600; cursor: pointer; }
  .see-all:hover { color: var(--sideb-highlight, #d06c70); }
  .carousel { display: flex; gap: 16px; overflow-x: auto; padding: 0 32px 4px; scrollbar-width: thin; }
  .carousel-card { display: flex; width: 144px; min-width: 144px; flex-direction: column; align-items: flex-start; gap: 6px; padding: 0; color: inherit; text-align: left; font: inherit; }
  .carousel-card-main { display: flex; width: 100%; min-width: 0; flex-direction: column; align-items: flex-start; gap: 7px; padding: 0; border: 0; background: transparent; color: inherit; text-align: left; font: inherit; }
  .interactive-card { cursor: pointer; }.interactive-card:hover .card-art-wrap { filter: brightness(1.08); }
  .informational { cursor: default; }
  .card-art-wrap { position: relative; display: block; width: 144px; height: 144px; overflow: hidden; border-radius: 10px; background: rgb(255 255 255 / 8%); }
  .card-art-wrap img, .card-art-fallback { display: grid; width: 100%; height: 100%; place-items: center; object-fit: cover; font-size: 32px; color: #aaa; }
  .card-art-wrap img.round, .card-art-fallback.round { border-radius: 50%; }
  .card-art-fallback { background: rgb(255 255 255 / 8%); }
  .card-title { max-width: 100%; overflow: hidden; color: var(--text-primary, #f3f3f5); font-size: 13px; font-weight: 600; text-overflow: ellipsis; white-space: nowrap; }
  .card-subtitle { max-width: 100%; overflow: hidden; color: var(--text-secondary, #aaaab0); font-size: 11px; text-overflow: ellipsis; white-space: nowrap; }
  .card-credits { min-width: 0; max-width: 100%; color: var(--text-secondary, #aaaab0); font-size: 11px; line-height: 15px; }
  .loading, .state-card { display: flex; min-height: 220px; flex-direction: column; align-items: center; justify-content: center; gap: 12px; color: var(--text-secondary, #aaaab0); text-align: center; }
  .state-card { margin: 0 32px; padding: 30px; }
  .state-card h2 { color: var(--text-primary, #eee); }
  .state-card p { max-width: 650px; margin: 0; font-size: 13px; }
  .state-icon { font-size: 32px; }
  .spinner { width: 18px; height: 18px; border: 2px solid rgb(255 255 255 / 22%); border-top-color: var(--sideb-highlight, #d06c70); border-radius: 50%; animation: spin .8s linear infinite; }
  .skeleton-header { display: flex; align-items: center; gap: 28px; }
  .skeleton-avatar { width: 180px; height: 180px; flex: 0 0 180px; border-radius: 50%; background: rgb(255 255 255 / 8%); }
  .skeleton-lines { display: flex; flex-direction: column; gap: 12px; }
  .skeleton-lines span { width: 260px; height: 18px; border-radius: 4px; background: rgb(255 255 255 / 7%); }
  .skeleton-lines span:first-child { width: 60px; height: 12px; }
  .skeleton-lines span:last-child { width: 160px; height: 14px; }
  @keyframes spin { to { transform: rotate(360deg); } }
  @media (max-width: 760px) { .artist-page { padding-top: 8px; } .back-button { margin-inline: 20px; } .artist-content { gap: 24px; padding-inline: 20px; } .artist-header { align-items: flex-start; gap: 18px; } .avatar { width: 112px; height: 112px; flex-basis: 112px; } .artist-info { min-height: 112px; } h1 { font-size: 27px; } .description-preview { max-height: 36px; } .description-preview span { -webkit-line-clamp: 2; line-clamp: 2; } .divider { margin-inline: 20px; } .carousel-section { margin-inline: -20px; } .section-heading, .carousel { padding-inline: 20px; } .skeleton-header { gap: 18px; } .skeleton-avatar { width: 112px; height: 112px; flex-basis: 112px; } .skeleton-lines span { width: 160px; } }
  @media (max-width: 520px) { .artist-header { flex-direction: column; align-items: flex-start; } .artist-info { min-height: 0; width: 100%; } .avatar { align-self: center; } .skeleton-header { align-items: flex-start; } .skeleton-avatar { width: 96px; height: 96px; flex-basis: 96px; } .skeleton-lines span { width: 120px; } }
</style>



<script lang="ts">
  import PlayerIcon from "../player/PlayerIcon.svelte";
  import type { PlaybackStateDto, QueueEntryDto, SongDto, BrowseCardDto } from "$lib/types";
  import ArtistCredits from "$lib/components/ArtistCredits.svelte";
  import QueuePanel from './QueuePanel.svelte';
  import LyricsPanel from './LyricsPanel.svelte';
  import RecommendedPanel from './RecommendedPanel.svelte';
  import type { LyricsState } from '$lib/player/lyrics';
  import type { RecommendationsSnapshot } from '$lib/player/recommendations';

  type Panel = "queue" | "lyrics" | "related";
  interface Props {
    playback: PlaybackStateDto;
    onSelectQueue: (index: number) => void;
    onMoveQueue: (entryId: string, beforeEntryId: string | null) => Promise<void>;
    lyricsState: LyricsState;
    recommendationsState: RecommendationsSnapshot;
    onSeek: (seconds: number) => void;
    onRetryLyrics: () => void;
    onRefreshRecommendations: () => void;
    onPlayRecommendation: (song: SongDto) => void;
    onEnqueueRecommendation: (song: SongDto) => void;
    onSongContextMenu: (event: MouseEvent, song: SongDto) => void;
    onArtistContextMenu: (event: MouseEvent, artist: BrowseCardDto) => void;
    onClose: () => void;
    selectedPanel?: Panel;
    onSelectPanel?: (panel: Panel) => void;
    onOpenArtist?: (id: string) => void;
    onOpenAlbum?: (id: string) => void;
    onOpenMenu?: (event: MouseEvent) => void;
    onQueueContextMenu?: (event: MouseEvent, entry: QueueEntryDto) => void;
    loggedIn?: boolean;
    liked?: boolean;
    likePending?: boolean;
    onToggleLike?: () => void;
    onRetryRadio?: () => void;
    likedIds?: Set<string>;
    pendingIds?: Set<string>;
    likesLoading?: boolean;
    onToggleQueueLike?: (entry: QueueEntryDto) => void;
    onDislikeQueueEntry?: (entry: QueueEntryDto) => void;
  }

  let {
    playback, onSelectQueue, onClose, selectedPanel, onSelectPanel, onOpenArtist, onOpenAlbum,
    onOpenMenu, onQueueContextMenu, loggedIn = false, liked = false, likePending = false,
    onToggleLike, onRetryRadio, likedIds = new Set<string>(), pendingIds = new Set<string>(), likesLoading = false,
    onToggleQueueLike, onDislikeQueueEntry,
    onMoveQueue, lyricsState, recommendationsState, onSeek, onRetryLyrics,
    onRefreshRecommendations, onPlayRecommendation, onEnqueueRecommendation,
    onSongContextMenu, onArtistContextMenu,
  }: Props = $props();
  let localPanel = $state<Panel>("queue");
  let failedArtworkUrl = $state<string | null>(null);
  const panel = $derived(selectedPanel ?? localPanel);
  const currentTrack = $derived(playback.currentTrack);

  const panels: { id: Panel; label: string }[] = [
    { id: "queue", label: "Cola" },
    { id: "lyrics", label: "Letras" },
    { id: "related", label: "Relacionado" },
  ];

  function selectPanel(value: Panel) {
    localPanel = value;
    onSelectPanel?.(value);
  }
</script>

<svelte:head><title>{currentTrack?.title ? `${currentTrack.title} · Side B` : "Reproducción · Side B"}</title></svelte:head>

<section id="fullscreen-now-playing" class="fullscreen" aria-label="Pantalla completa de reproducción">
  {#if currentTrack?.thumbnail && failedArtworkUrl !== currentTrack.thumbnail}
    <div class="backdrop-art" style={`background-image: url("${currentTrack.thumbnail}")`} aria-hidden="true"></div>
  {/if}
  <div class="backdrop-shade" aria-hidden="true"></div>

  <button type="button" class="close-button" onclick={onClose} aria-label="Cerrar pantalla completa" title="Cerrar pantalla completa">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 6 18 18M18 6 6 18" /></svg>
  </button>

  <div class="layout">
    <div class="art-column">
      <div class="art-block">
        <div class="artwork">
          {#if currentTrack?.thumbnail && failedArtworkUrl !== currentTrack.thumbnail}
            <img src={currentTrack.thumbnail} alt={`Portada de ${currentTrack.title}`} onerror={() => failedArtworkUrl = currentTrack?.thumbnail ?? null} />
          {:else}
            <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>
          {/if}
        </div>
        <div class="track-info" role="group" aria-label="Canción actual" oncontextmenu={(event) => { if (onOpenMenu && currentTrack) { event.preventDefault(); onOpenMenu(event); } }}>
          <div class="title-line">
            <h1 title={currentTrack?.title ?? "Sin reproducción"}>{currentTrack?.title ?? "Sin reproducción"}</h1>
            {#if loggedIn && onToggleLike && currentTrack}
              <button class="like-button" type="button" class:liked disabled={likePending || playback.isLoading} aria-pressed={liked} aria-label={liked ? "Quitar de Me Gusta" : "Me Gusta"} title={liked ? "Quitar de Me Gusta" : "Me Gusta"} onclick={onToggleLike}>
                <svg viewBox="0 0 24 24" aria-hidden="true" fill={liked ? "currentColor" : "none"} stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 8.7c0 4.2-6.4 9.1-8.8 11-2.4-1.9-8.8-6.8-8.8-11a4.9 4.9 0 0 1 8.8-3.1 4.9 4.9 0 0 1 8.8 3.1Z" /></svg>
              </button>
            {/if}
            {#if onOpenMenu && currentTrack}<button class="more-button" type="button" aria-label="Más opciones de la canción" title="Más opciones" onclick={onOpenMenu}><svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg></button>{/if}
          </div>
          <div class="artist-line">
            <ArtistCredits artistRuns={currentTrack?.artistRuns} artists={currentTrack?.artists ?? "Seleccioná una canción"} artistId={currentTrack?.artistId} {onOpenArtist} album={currentTrack?.album} albumId={currentTrack?.albumId} {onOpenAlbum} />
          </div>
        </div>
      </div>
    </div>

    <div class="side-column">
      <div class="tablist" role="tablist" aria-label="Panel de reproducción">
        {#each panels as item (item.id)}
          <button type="button" id={`fullscreen-tab-${item.id}`} role="tab" aria-selected={panel === item.id} aria-controls="fullscreen-panel" class:active={panel === item.id} onclick={() => selectPanel(item.id)}>
            <PlayerIcon name={item.id} size={14} />
            {item.label}
          </button>
        {/each}
      </div>

      <div id="fullscreen-panel" class="panel" role="tabpanel" aria-labelledby={`fullscreen-tab-${panel}`}>
        {#if panel === "queue"}
          <QueuePanel {playback} {onSelectQueue} {onMoveQueue} {onQueueContextMenu} {onRetryRadio} {loggedIn} {likedIds} {pendingIds} {likesLoading} onToggleLike={onToggleQueueLike} onDislike={onDislikeQueueEntry} />
        {:else if panel === "lyrics"}
          <LyricsPanel state={lyricsState} position={playback.position} duration={playback.duration} {onSeek} onRetry={onRetryLyrics} />
        {:else}
          <RecommendedPanel snapshot={recommendationsState} {currentTrack} isPlaying={playback.isPlaying}
            onRefresh={onRefreshRecommendations} onPlaySong={onPlayRecommendation} onPlayNext={onEnqueueRecommendation}
            {onOpenArtist} {onOpenAlbum} {onSongContextMenu} {onArtistContextMenu} />
        {/if}
      </div>
    </div>
  </div>
</section>

<style>
  .fullscreen { position: fixed; inset: 0 0 0 var(--sidebar-width, 0px); z-index: 80; box-sizing: border-box; container-type: inline-size; height: 100dvh; max-height: 100dvh; overflow: hidden; isolation: isolate; color: #fff; background: #1b1b1e; }
  .backdrop-art { position: absolute; inset: -12%; z-index: -2; background-size: cover; background-position: center; filter: blur(75px) brightness(.55); transform: scale(1.08); pointer-events: none; }
  .backdrop-shade { position: absolute; inset: 0; z-index: -1; background: linear-gradient(180deg, rgb(12 12 15 / 70%), rgb(17 17 20 / 83%)); pointer-events: none; }
  .close-button { position: absolute; top: 44px; right: 12px; z-index: 2; display: grid; place-items: center; width: 32px; height: 32px; padding: 6px; border: 0; border-radius: 8px; color: rgb(255 255 255 / 75%); background: rgb(255 255 255 / 9%); cursor: pointer; }
  .close-button:hover { color: #fff; background: rgb(255 255 255 / 16%); }.close-button svg { width: 18px; height: 18px; }
  .layout {
    --inset: clamp(24px, 3.5cqw, 48px);
    --column-gap: clamp(24px, 2.8cqw, 40px);
    --available-width: calc(100cqw - var(--inset) * 2 - var(--column-gap));
    --max-art: max(100px, calc(100dvh - 264px));
    /* Preserve the Mac 600/686 panel/artwork balance on taller, wider windows. */
    --panel-cap: max(600px, calc(var(--max-art) * .875));
    --panel-max: max(300px, calc(var(--available-width) * .56));
    --panel-width: min(var(--panel-max), max(min(340px, var(--panel-max)), min(var(--panel-cap), calc(var(--available-width) * .52))));
    /* Once artwork reaches its height limit, its column stops accumulating empty space. */
    --art-column-width: max(100px, min(calc(var(--available-width) - var(--panel-width)), calc(var(--max-art) / .9)));
    box-sizing: border-box;
    display: grid;
    grid-template-columns: var(--art-column-width) var(--panel-width);
    align-items: stretch;
    gap: var(--column-gap);
    width: calc(var(--art-column-width) + var(--panel-width) + var(--column-gap) + var(--inset) * 2);
    max-width: 100%;
    height: 100dvh;
    max-height: 100dvh;
    min-width: 0;
    min-height: 0;
    margin-inline: auto;
    padding: 52px var(--inset) 112px;
    overflow: hidden;
  }
  .art-column { display: grid; place-items: center; min-width: 0; min-height: 0; overflow: hidden; }
  .art-block { width: min(90%, max(100px, calc(100dvh - 264px))); max-width: 100%; min-width: 0; max-height: 100%; }
  .artwork { display: grid; place-items: center; width: 100%; aspect-ratio: 1; max-height: calc(100dvh - 264px); overflow: hidden; border-radius: 16px; color: rgb(255 255 255 / 42%); background: rgb(255 255 255 / 8%); box-shadow: 0 10px 30px rgb(0 0 0 / 42%); }
  .artwork img { display: block; width: 100%; height: 100%; object-fit: cover; }.artwork svg { width: 22%; max-width: 80px; }
  .track-info { box-sizing: border-box; display: flex; width: 100%; height: 68px; flex-direction: column; justify-content: center; gap: 4px; margin-top: 16px; }
  .title-line { display: flex; min-width: 0; align-items: center; gap: 8px; }.title-line h1 { flex: 1; min-width: 0; overflow: hidden; margin: 0; font-size: 28px; font-weight: 700; line-height: 1.2; text-overflow: ellipsis; white-space: nowrap; }
  .artist-line { display: flex; min-width: 0; align-items: center; overflow: hidden; color: rgb(255 255 255 / 76%); font-size: 17.5px; font-weight: 500; white-space: nowrap; }
  .like-button, .more-button { display: grid; flex: 0 0 30px; place-items: center; width: 30px; height: 30px; padding: 6px; border: 0; border-radius: 50%; color: rgb(255 255 255 / 70%); background: transparent; cursor: pointer; }.like-button svg, .more-button svg { width: 18px; height: 18px; }.like-button:hover, .more-button:hover { color: white; background: rgb(255 255 255 / 10%); }.like-button.liked { color: #d06c70; }.like-button:disabled { opacity: .5; cursor: wait; }
  .side-column { display: flex; min-width: 0; min-height: 0; height: 100%; flex-direction: column; align-items: center; gap: 14px; overflow: hidden; }
  .tablist { box-sizing: border-box; display: flex; flex: 0 0 40px; height: 40px; align-items: center; gap: 0; max-width: 100%; padding: 4px; border-radius: 999px; background: #343437; box-shadow: inset 0 0 0 1px rgb(255 255 255 / 12%); }
  .tablist button { display: inline-flex; flex: none; align-items: center; justify-content: center; gap: 7px; height: 32px; padding: 8px 16px; border: 0; border-radius: 999px; color: rgb(255 255 255 / 65%); background: transparent; font: inherit; font-size: 13px; font-weight: 500; line-height: 16px; white-space: nowrap; cursor: pointer; }.tablist button.active { color: #fff; background: #a33d45; font-weight: 650; }.tablist button:hover:not(.active) { color: #fff; }
  .panel { box-sizing: border-box; display: flex; width: 100%; min-width: 0; min-height: 0; flex: 1; overflow: hidden; }
  button:focus-visible { outline: 2px solid #d06c70; outline-offset: 3px; }

</style>

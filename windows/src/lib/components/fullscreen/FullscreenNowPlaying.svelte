<script lang="ts">
  import { fade } from 'svelte/transition';
  import { onMount } from 'svelte';
  import { t } from '$lib/i18n';
  import GeniusPanel from './GeniusPanel.svelte';
  import TrackInformation from './TrackInformation.svelte';
  import type { GeniusState } from '$lib/genius/types';
  import type { GeniusController } from '$lib/genius/controller';
  import PlayerIcon from "../player/PlayerIcon.svelte";
  import type { PlaybackStateDto, QueueEntryDto, SongDto, BrowseCardDto } from "$lib/types";
  import ArtistCredits from "$lib/components/ArtistCredits.svelte";
  import QueuePanel from './QueuePanel.svelte';
  import LyricsPanel from './LyricsPanel.svelte';
  import RecommendedPanel from './RecommendedPanel.svelte';
  import FullscreenBackdrop from './FullscreenBackdrop.svelte';
  import { artworkCandidates, nextArtworkUrl } from '$lib/images/artwork';
  import type { LyricsState } from '$lib/player/lyrics';
  import type { RecommendationsSnapshot } from '$lib/player/recommendations';

  type Panel = "queue" | "lyrics" | "related";
  interface Props {
    pullDistance?:number; pulling?:boolean;
    playback: PlaybackStateDto; geniusState:GeniusState;geniusController:GeniusController;onOpenExternal:(url:string)=>void;
    onSelectQueue: (index: number) => void;
    onTogglePlayback: () => void;
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
    lyricsMode?: 'synced' | 'genius';
    onShowGenius?: () => void;
    onSelectPanel?: (panel: Panel) => void;
    onOpenArtist?: (id: string, title?: string) => void;
    onOpenAlbum?: (id: string) => void;
    onOpenMenu?: (event: MouseEvent | KeyboardEvent) => void;
    onQueueContextMenu?: (event: MouseEvent, entry: QueueEntryDto) => void;
    loggedIn?: boolean;
    liked?: boolean;
    likePending?: boolean;
    onToggleLike?: () => void;
    onRetryRadio?: () => void;
    onRetrySource?: () => void;
    likedIds?: Set<string>;
    pendingIds?: Set<string>;
    likesLoading?: boolean;
    onToggleQueueLike?: (entry: QueueEntryDto) => void;
    onDislikeQueueEntry?: (entry: QueueEntryDto) => void;
  }

  let {
    pullDistance=0,pulling=false,geniusState,geniusController,onOpenExternal,playback, onSelectQueue, onTogglePlayback, onClose, selectedPanel, lyricsMode='synced', onShowGenius, onSelectPanel, onOpenArtist, onOpenAlbum,
    onOpenMenu, onQueueContextMenu, loggedIn = false, liked = false, likePending = false,
    onToggleLike, onRetryRadio, onRetrySource, likedIds = new Set<string>(), pendingIds = new Set<string>(), likesLoading = false,
    onToggleQueueLike, onDislikeQueueEntry,
    onMoveQueue, lyricsState, recommendationsState, onSeek, onRetryLyrics,
    onRefreshRecommendations, onPlayRecommendation, onEnqueueRecommendation,
    onSongContextMenu, onArtistContextMenu,
  }: Props = $props();
  let showInformation=$state(false);
  let informationButton: HTMLButtonElement;
  function closeInformation() { showInformation=false; informationButton?.focus({preventScroll:true}); }
  let reduced=$state(false);
  onMount(()=>{const media=window.matchMedia('(prefers-reduced-motion:reduce)');const sync=()=>reduced=media.matches;sync();media.addEventListener('change',sync);return()=>media.removeEventListener('change',sync);});
  const informationTrackKey=$derived(JSON.stringify([playback.currentTrack?.videoId,playback.generation]));
  $effect(()=>{informationTrackKey;showInformation=false;});
  let localPanel = $state<Panel>("queue");
  let failedArtworkTrackKey = $state<string | null>(null);
  const panel = $derived(selectedPanel ?? localPanel);
  const currentTrack = $derived(playback.currentTrack);
  const artworkTrackKey = $derived(currentTrack ? `${currentTrack.videoId}\u0000${currentTrack.thumbnail ?? ''}` : '');
  let failedArtworkUrls = $state<string[]>([]);
  const activeFailedArtworkUrls = $derived(failedArtworkTrackKey === artworkTrackKey ? failedArtworkUrls : []);
  const currentArtworkCandidates = $derived(artworkCandidates(currentTrack?.thumbnail));
  const selectedArtworkUrl = $derived(nextArtworkUrl(currentArtworkCandidates, activeFailedArtworkUrls));

  const panels = $derived<{id:Panel;label:string}[]>([
    { id: "queue", label: $t("queue.title") },
    { id: "lyrics", label: $t("fullscreen.lyrics") },
    { id: "related", label: $t("fullscreen.related") },
  ]);

  function selectPanel(value: Panel) {
    localPanel = value;
    onSelectPanel?.(value);
  }

  function trackMenuKey(event: KeyboardEvent) {
    if (currentTrack && onOpenMenu && (event.key === 'ContextMenu' || event.key === 'F10' && event.shiftKey)) {
      event.preventDefault(); event.stopPropagation(); onOpenMenu(event);
    }
  }

  function handleArtworkError(trackKey: string, url: string) {
    if (trackKey !== artworkTrackKey || url !== selectedArtworkUrl) return;
    const previousFailures = failedArtworkTrackKey === trackKey ? failedArtworkUrls : [];
    failedArtworkTrackKey = trackKey;
    failedArtworkUrls = [...new Set([...previousFailures, url])];
  }
</script>

<svelte:head><title>{currentTrack?.title ? `${currentTrack.title} · Side B` : $t('windows.fullscreen.title')}</title></svelte:head>

{#snippet artworkImage(trackKey: string, url: string, title: string)}
  <img src={url} alt={$t('windows.fullscreen.artwork', [title])} onerror={() => handleArtworkError(trackKey, url)} />
{/snippet}

<section id="fullscreen-now-playing" class="fullscreen" class:pulling style:transform={`translateY(${reduced?0:Math.max(0,pullDistance)}px)`} transition:fade={{duration:reduced?0:160}} aria-label={$t('windows.fullscreen.region')}>
  <FullscreenBackdrop thumbnail={currentTrack?.thumbnail} trackKey={artworkTrackKey} />

  <button type="button" class="close-button" onclick={onClose} aria-label={$t('player.closeFullscreen')} title={$t('player.closeFullscreen')}>
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 6 18 18M18 6 6 18" /></svg>
  </button>

  <div class="pull-surface" data-gesture-pull aria-hidden="true"></div>
  <div class="layout">
    <div class="art-column">
      <div class="art-block">
        <div class="artwork-flip" class:flipped={showInformation}>
          <div class="artwork-front" inert={showInformation} aria-hidden={showInformation} oncontextmenu={(event)=>{if(onOpenMenu&&currentTrack){event.preventDefault();onOpenMenu(event);}}} role="group">
        <button type="button" class="artwork" onkeydown={trackMenuKey} disabled={!currentTrack || playback.isLoading}
          aria-label={`${playback.isPlaying ? $t('player.pause') : $t('player.play')} ${currentTrack?.title ?? 'canción'}`}
          title={playback.isPlaying ? $t('player.pause') : $t('player.play')} onclick={onTogglePlayback}>
          {#if selectedArtworkUrl && currentTrack}
            {#key `${artworkTrackKey}\u0000${selectedArtworkUrl}`}
              {@render artworkImage(artworkTrackKey, selectedArtworkUrl, currentTrack.title)}
            {/key}
          {:else}
            <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>
          {/if}
          <span class="artwork-shade" aria-hidden="true"></span>
          <span class="artwork-control" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="currentColor">{#if playback.isPlaying}<path d="M6 4h4v16H6zM14 4h4v16h-4z"/>{:else}<path d="m7 3 15 9-15 9z"/>{/if}</svg>
          </span>
        </button>
          </div>
          <div id="track-information-card" class="information artwork-back" inert={!showInformation} aria-hidden={!showInformation}>
            <TrackInformation song={geniusState.resolution?.song??null} title={currentTrack?.title??''} artists={currentTrack?.artists??''} album={currentTrack?.album??''} loading={geniusState.phase==='loading'} onClose={closeInformation} {onShowGenius} {onOpenExternal} />
          </div>
        </div>
        <div class="track-info" role="group" aria-label={$t('windows.ui.currentSong')} oncontextmenu={(event) => { if (onOpenMenu && currentTrack) { event.preventDefault(); onOpenMenu(event); } }}>
          <div class="title-line">
            <h1 title={currentTrack?.title ?? $t('player.noPlayback')}>{currentTrack?.title ?? $t('player.noPlayback')}</h1>
            {#if loggedIn && onToggleLike && currentTrack}
              <button class="like-button" onkeydown={trackMenuKey} type="button" class:liked disabled={likePending || playback.isLoading} aria-pressed={liked} aria-label={$t(liked ? 'detail.track.unlike' : 'detail.track.like')} title={$t(liked ? 'detail.track.unlike' : 'detail.track.like')} onclick={onToggleLike}>
                <svg viewBox="2 1.68 20 20" aria-hidden="true" fill={liked ? "currentColor" : "none"} stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 8.7c0 4.2-6.4 9.1-8.8 11-2.4-1.9-8.8-6.8-8.8-11a4.9 4.9 0 0 1 8.8-3.1 4.9 4.9 0 0 1 8.8 3.1Z" /></svg>
              </button>
            {/if}
            <button bind:this={informationButton} class="information-button" onkeydown={trackMenuKey} type="button" disabled={!currentTrack} aria-pressed={showInformation} aria-controls="track-information-card" aria-label={$t(showInformation ? 'fullscreen.backToArtwork' : 'fullscreen.songInformation')} title={$t(showInformation ? 'fullscreen.backToArtwork' : 'fullscreen.songInformation')} onclick={()=>{showInformation=!showInformation;if(showInformation)void geniusController.ensureNow();}}>
              <svg viewBox="1.5 1.5 21 21" aria-hidden="true" fill="none"><circle cx="12" cy="12" r="9.3" stroke="currentColor" stroke-width="1.8" fill={showInformation?'currentColor':'none'}/><path d="M12 10.5v6.2" stroke={showInformation?'#1a1a1f':'currentColor'} stroke-width="1.9" stroke-linecap="round"/><circle cx="12" cy="7.3" r="1.15" fill={showInformation?'#1a1a1f':'currentColor'}/></svg>
            </button>
          </div>
          <div class="artist-line">
            <ArtistCredits artistRuns={currentTrack?.artistRuns} artists={currentTrack?.artists ?? $t('player.selectTrack')} artistId={currentTrack?.artistId} {onOpenArtist} album={currentTrack?.album} albumId={currentTrack?.albumId} {onOpenAlbum} />
          </div>
        </div>
      </div>
    </div>

    <div class="side-column">
      <div class="tablist" role="tablist" aria-label={$t('windows.fullscreen.panel')}>
        {#each panels as item (item.id)}
          <button type="button" id={`fullscreen-tab-${item.id}`} role="tab" aria-selected={panel === item.id} aria-controls="fullscreen-panel" class:active={panel === item.id} onclick={() => selectPanel(item.id)}>
            <PlayerIcon name={item.id} size={14} />
            {item.label}
          </button>
        {/each}
      </div>

      <div id="fullscreen-panel" class="panel" role="tabpanel" aria-labelledby={`fullscreen-tab-${panel}`}>
        {#if panel === "queue"}
          <QueuePanel {playback} {onSelectQueue} {onTogglePlayback} {onOpenArtist} {onOpenAlbum} {onMoveQueue} {onQueueContextMenu} {onRetryRadio} {onRetrySource} {loggedIn} {likedIds} {pendingIds} {likesLoading} onToggleLike={onToggleQueueLike} onDislike={onDislikeQueueEntry} />
        {:else if panel === "lyrics"}
          {#if lyricsMode==='genius'}
            <GeniusPanel state={geniusState} controller={geniusController} title={currentTrack?.title??''} artists={currentTrack?.artists??''} artwork={selectedArtworkUrl} {onOpenExternal} />
          {:else}
            <LyricsPanel state={lyricsState} position={playback.position} duration={playback.duration} {onSeek} onRetry={onRetryLyrics} />
          {/if}
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
  .fullscreen {transition:transform 180ms ease-out;} .fullscreen.pulling {transition:none;} @media(prefers-reduced-motion:reduce){.fullscreen{transition:none;}}
  .pull-surface { position: absolute; top: 4px; left: 20%; right: 20%; height: 30px; z-index: 1; touch-action: none; }
  .artwork-flip {position:relative;width:100%;aspect-ratio:1;perspective:1200px;filter:drop-shadow(0 10px 22px #0006);}
  .artwork-front,.artwork-back {position:absolute;inset:0;width:100%;height:100%;backface-visibility:hidden;transition:transform .48s ease-in-out,opacity .48s ease-in-out;border-radius:8px;}
  .artwork-front {transform:rotateY(0);opacity:1;}
  .artwork-back {transform:rotateY(-180deg);opacity:0;background:#1a1a1f;overflow:hidden;}
  .flipped .artwork-front {transform:rotateY(180deg);opacity:0;pointer-events:none;}
  .flipped .artwork-back {transform:rotateY(0);opacity:1;}
  @media(prefers-reduced-motion:reduce){.artwork-front,.artwork-back{transition:none;}}

  .fullscreen { position: fixed; inset: 0 0 0 var(--sidebar-width, 0px); z-index: 80; box-sizing: border-box; container-type: inline-size; height: 100dvh; max-height: 100dvh; overflow: hidden; isolation: isolate; color: #fff; background: #1b1b1e; }
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
  .art-block { container-type:inline-size; width: min(90%, max(100px, calc(100dvh - 264px))); max-width: 100%; min-width: 0; max-height: 100%; }
  .artwork { display:grid; position:relative; container-type:inline-size; place-items:center; width:100%; aspect-ratio:1; max-height:calc(100dvh - 264px); padding:0; border:0; overflow:hidden; border-radius:8px; color:rgb(255 255 255 / 42%); background:rgb(255 255 255 / 8%); box-shadow:0 10px 30px rgb(0 0 0 / 42%); cursor:pointer; }
  .artwork:disabled { cursor:default; }
  .artwork img { display:block; width:100%; height:100%; object-fit:cover; }.artwork > svg { width:22%; max-width:80px; }
  .artwork-shade { position:absolute; inset:0; background:rgb(0 0 0 / 22%); opacity:0; pointer-events:none; transition:opacity 180ms ease-in-out; }
  .artwork-control { position:absolute; inset:0; display:grid; place-items:center; color:rgb(255 255 255 / 92%); opacity:0; pointer-events:none; transition:opacity 180ms ease-in-out; }
  .artwork-control svg { width:max(28px,14cqw); height:max(28px,14cqw); filter:drop-shadow(0 2px 8px rgb(0 0 0 / 50%)); }
  .artwork:is(:hover,:focus-visible):not(:disabled) .artwork-shade,.artwork:is(:hover,:focus-visible):not(:disabled) .artwork-control { opacity:1; }
  .artwork:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:3px; }
  @media (prefers-reduced-motion:reduce) { .artwork-shade,.artwork-control { transition:none; } }
  .track-info { box-sizing: border-box; display: flex; width: 100%; height: 68px; flex-direction: column; justify-content: flex-start; gap: 4px; margin-top: 16px; }
  .title-line { display: flex; min-width: 0; align-items: center; gap: 8px; }.title-line h1 { flex: 1; min-width: 0; overflow: hidden; margin: 0; font-size: 28px; font-weight: 700; line-height: 1.2; text-overflow: ellipsis; white-space: nowrap; }
  .artist-line { display: flex; min-width: 0; align-items: center; overflow: hidden; color: rgb(255 255 255 / 78%); font-size: 17.5px; font-weight: 500; line-height: normal; white-space: nowrap;
    --credit-artist-weight: 600;
    --credit-album-size: calc(1em - .5px);
    --credit-album-weight: 500;
    --credit-album-color: rgb(255 255 255 / 60%);
    --credit-separator-size: 13px;
    --credit-separator-weight: 400;
    --credit-separator-color: rgb(255 255 255 / 40%);
  }
  /* Apple action typography follows artwork width: 20→22 at 300→500 logical pixels.
     The enclosing art-block is the query container. SVG viewBoxes center the visible ink,
     including the heart's asymmetric vertical extent, instead of its unused 24px canvas. */
  .like-button, .information-button { display: grid; box-sizing: border-box; flex: 0 0 36px; place-items: center; width: 36px; height: 36px; padding: 0; border: 0; border-radius: 50%; color: rgb(255 255 255 / 70%); background: transparent; cursor: pointer; }
  .like-button svg, .information-button svg { display:block; width:clamp(20px,calc(20px + (100cqw - 300px) * .01),22px); height:clamp(20px,calc(20px + (100cqw - 300px) * .01),22px); }
  .information-button[aria-pressed=true] {color:white;} .information-button:disabled{opacity:.5;cursor:default;}.like-button:hover, .information-button:hover { color: white; background: rgb(255 255 255 / 10%); }.like-button.liked { color: #d06c70; }.like-button:disabled { opacity: .5; cursor: wait; }
  .side-column { display: flex; min-width: 0; min-height: 0; height: 100%; flex-direction: column; align-items: center; gap: 14px; overflow: hidden; }
  .tablist { box-sizing: border-box; display: flex; flex: 0 0 40px; height: 40px; align-items: center; gap: 0; max-width: 100%; padding: 4px; border-radius: 999px; background: #343437; box-shadow: inset 0 0 0 1px rgb(255 255 255 / 12%); }
  .tablist button { display: inline-flex; flex: none; align-items: center; justify-content: center; gap: 7px; height: 32px; padding: 8px 16px; border: 0; border-radius: 999px; color: rgb(255 255 255 / 65%); background: transparent; font: inherit; font-size: 13px; font-weight: 500; line-height: 16px; white-space: nowrap; cursor: pointer; }.tablist button.active { color: #fff; background: #a33d45; font-weight: 650; }.tablist button:hover:not(.active) { color: #fff; }
  .panel { box-sizing: border-box; display: flex; width: 100%; min-width: 0; min-height: 0; flex: 1; overflow: hidden; }
  button:focus-visible { outline: 2px solid #d06c70; outline-offset: 3px; }

  .title-line h1 {font-size:clamp(21px,calc(21px + (100cqw - 300px) * .035),28px);}
  .artist-line {font-size:clamp(14.5px,calc(14.5px + (100cqw - 300px) * .015),17.5px);}
  @container(max-width:700px){.tablist button{gap:4px;padding:8px 9px;font-size:12px;}.side-column{gap:10px;}}

</style>

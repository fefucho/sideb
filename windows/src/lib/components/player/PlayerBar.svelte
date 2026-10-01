<script lang="ts">
  import { tick } from "svelte";
  import PlayerIcon from "./PlayerIcon.svelte";
  import type { PlaybackStateDto } from "$lib/types";
  import ArtistCredits from "$lib/components/ArtistCredits.svelte";
  type Panel = "queue" | "lyrics" | "related";

  interface Props {
    playback: PlaybackStateDto;
    onTogglePlayback: () => void;
    onRetryPlayback: () => void;
    onPrevious: () => void;
    onNext: () => void;
    onSeek: (seconds: number) => void;
    onVolumeChange: (volume: number) => void;
    fullscreenOpen: boolean;
    onToggleFullscreen: () => void;
    loggedIn?: boolean;
    liked?: boolean;
    likePending?: boolean;
    onToggleLike?: () => void;
    likeError?: string | null;
    selectedPanel?: Panel;
    onSelectPanel?: (panel: Panel) => void;
    onOpenArtist?: (id: string) => void;
    onOpenAlbum?: (id: string) => void;
    onOpenMenu?: (event: MouseEvent) => void;
  }

  let { playback, onTogglePlayback, onRetryPlayback, onPrevious, onNext, onSeek, onVolumeChange, fullscreenOpen, onToggleFullscreen, loggedIn = false, liked = false, likePending = false, onToggleLike, likeError = null, selectedPanel, onSelectPanel, onOpenArtist, onOpenAlbum, onOpenMenu }: Props = $props();
  let seekDraft = $state<{ generation: number; value: number } | null>(null);
  let failedArtworkUrl = $state<string | null>(null);
  let volumeOpen = $state(false);
  let volumeDragging = false;
  let volumeHovered = false;
  let lastAudibleVolume = 100;
  let volumeRoot: HTMLDivElement;
  let volumeButton: HTMLButtonElement;
  let volumeSlider = $state<HTMLInputElement>();

  async function toggleVolume() {
    volumeOpen = !volumeOpen;
    if (volumeOpen) { await tick(); volumeSlider?.focus(); }
  }
  function closeVolume(restoreFocus = false) {
    volumeOpen = false;
    if (restoreFocus) volumeButton?.focus({ preventScroll: true });
  }
  function leaveVolume() {
    volumeHovered = false;
    if (!volumeDragging) closeVolume(volumeRoot?.contains(document.activeElement));
  }
  function finishVolumeDrag() {
    if (!volumeDragging) return;
    volumeDragging = false;
    if (!volumeHovered) closeVolume(volumeRoot?.contains(document.activeElement));
  }
  function handleVolumeFocusOut(event: FocusEvent) {
    if (!volumeDragging && !(event.relatedTarget instanceof Node && volumeRoot?.contains(event.relatedTarget))) closeVolume();
  }
  function toggleMute() {
    if (volume > 0) { lastAudibleVolume = volume; onVolumeChange(0); }
    else onVolumeChange(lastAudibleVolume);
  }
  function dismissVolume(event: PointerEvent) {
    if (volumeOpen && !volumeDragging && event.target instanceof Node && !volumeRoot?.contains(event.target)) closeVolume();
  }
  function handleVolumeKeydown(event: KeyboardEvent) {
    if (event.key === "Escape" && volumeOpen) {
      event.preventDefault();
      volumeDragging = false;
      closeVolume(true);
    }
  }

  const duration = $derived(finitePositive(playback.duration));
  const position = $derived(clamp(seekDraft?.generation === playback.generation ? seekDraft.value : playback.position, 0, duration));
  const volume = $derived(clamp(playback.volume, 0, 100));
  const hasTrack = $derived(playback.currentTrack !== null);
  const playLabel = $derived(
    playback.error
      ? "Reintentar reproducción"
      : playback.isEnded
        ? "Reiniciar canción"
        : playback.isPlaying
          ? "Pausar"
          : "Reproducir"
  );

  function finitePositive(value: number): number {
    return Number.isFinite(value) ? Math.max(0, value) : 0;
  }

  function clamp(value: number, min: number, max: number): number {
    return Number.isFinite(value) ? Math.min(max, Math.max(min, value)) : min;
  }

  function formatTime(value: number): string {
    const total = Math.floor(finitePositive(value));
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
  }

  function handleSeekInput(event: Event) {
    seekDraft = { generation: playback.generation, value: clamp(Number((event.currentTarget as HTMLInputElement).value), 0, duration) };
  }

  function handleSeekChange(event: Event) {
    const seconds = clamp(Number((event.currentTarget as HTMLInputElement).value), 0, duration);
    const draft = seekDraft;
    seekDraft = null;
    if (draft && draft.generation !== playback.generation) return;
    onSeek(seconds);
  }

  function handleVolumeInput(event: Event) {
    onVolumeChange(clamp(Number((event.currentTarget as HTMLInputElement).value), 0, 100));
  }
</script>

<svelte:window onpointerdown={dismissVolume} onpointerup={finishVolumeDrag} onpointercancel={finishVolumeDrag} onkeydown={handleVolumeKeydown} onblur={() => { volumeDragging = false; closeVolume(); }} />

<footer class="player-bar" aria-label="Reproductor de audio">
  <div class="progress">
    <span class="time" aria-label={`Tiempo transcurrido ${formatTime(position)}`}>
      {formatTime(position)}
    </span>
    <input
      class="seek"
      type="range"
      min="0"
      max={duration || 1}
      step="0.25"
      value={position}
      style={`--fill:${duration ? (position / duration) * 100 : 0}%`}
      disabled={!hasTrack || playback.isLoading || duration === 0}
      oninput={handleSeekInput}
      onchange={handleSeekChange}
      aria-label="Posición de reproducción"
    />
    <span class="time time-end" aria-label={`Duración ${formatTime(duration)}`}>
      {formatTime(duration)}
    </span>
  </div>

  <div class="main-row">
    <div class="transport">
      <button type="button" class="mode-toggle" disabled aria-label="Aleatorio no disponible todavía" title="Aleatorio: todavía no disponible en Windows"><PlayerIcon name="shuffle" size={17} /></button>
      <button type="button" class="skip" onclick={onPrevious} disabled={!hasTrack} aria-label="Pista anterior" title="Pista anterior">
        <PlayerIcon name="backward" size={20} />
      </button>
      <button
        type="button"
        class="play-toggle"
        class:errored={!!playback.error}
        disabled={!hasTrack || playback.isLoading}
        onclick={playback.error ? onRetryPlayback : onTogglePlayback}
        aria-label={playLabel}
        title={playLabel}
      >
        {#if playback.isLoading}
          <span class="spinner" aria-hidden="true"></span>
        {:else if playback.error}
          <svg viewBox="0 0 24 24" aria-hidden="true" fill="none"><path d="M20 11a8 8 0 1 1-2.36-5.66M20 4v5h-5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" /></svg>
        {:else if playback.isPlaying}
          <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><rect x="5" y="3" width="5" height="18" rx="1" /><rect x="14" y="3" width="5" height="18" rx="1" /></svg>
        {:else}
          <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M6 3.5a1 1 0 0 1 1.51-.86l13 8.5a1 1 0 0 1 0 1.72l-13 8.5A1 1 0 0 1 6 20.5z" /></svg>
        {/if}
      </button>
      <button type="button" class="skip" onclick={onNext} disabled={!hasTrack || playback.queue.currentIndex === null || playback.queue.currentIndex + 1 >= playback.queue.items.length} aria-label="Pista siguiente" title="Pista siguiente">
        <PlayerIcon name="forward" size={20} />
      </button>
      <button type="button" class="mode-toggle" disabled aria-label="Repetir no disponible todavía" title="Repetir: todavía no disponible en Windows"><PlayerIcon name="repeat" size={17} /></button>
    </div>

    <div class="track" role="group" aria-label="Canción actual" oncontextmenu={(event) => { if (onOpenMenu && hasTrack) { event.preventDefault(); onOpenMenu(event); } }}>
      <div class="artwork">
        {#if playback.currentTrack?.thumbnail && failedArtworkUrl !== playback.currentTrack.thumbnail}
          <img src={playback.currentTrack.thumbnail} alt="" onerror={() => failedArtworkUrl = playback.currentTrack?.thumbnail ?? null} />
        {:else}
          <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M10 5v12.1a4 4 0 1 1-2-3.46V3l12-2v14.1a4 4 0 1 1-2-3.46V4.4z" /></svg>
        {/if}
      </div>
      <div class="metadata">
        <div class="title-line">
        <span class="title" title={playback.currentTrack?.title ?? "Sin reproducción"}>
          {playback.currentTrack?.title ?? "Sin reproducción"}
        </span>
        <button class="like-toggle" type="button" class:liked disabled={!loggedIn || !hasTrack || !onToggleLike || likePending || playback.isLoading} onclick={onToggleLike} aria-pressed={liked} aria-label={liked ? "Quitar de Me Gusta" : "Me Gusta"} title={!loggedIn ? "Iniciá sesión para usar Me Gusta" : likeError ?? (likePending ? "Actualizando Me Gusta…" : liked ? "Quitar de Me Gusta" : "Me Gusta")}>
          {#if likePending}<span class="like-spinner" aria-hidden="true"></span>{:else}<svg viewBox="0 0 24 24" aria-hidden="true" fill={liked ? "currentColor" : "none"} stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 8.7c0 4.2-6.4 9.1-8.8 11-2.4-1.9-8.8-6.8-8.8-11a4.9 4.9 0 0 1 8.8-3.1 4.9 4.9 0 0 1 8.8 3.1Z" /></svg>{/if}
        </button>
        </div>
        {#if playback.error}
          <span class="status error" role="status" title={playback.error}>{playback.error}</span>
        {:else if playback.isLoading}
          <span class="status" role="status">Cargando audio…</span>
        {:else}
          <div class="artist-line">
            {#if playback.currentTrack}
              <ArtistCredits artistRuns={playback.currentTrack.artistRuns} artists={playback.currentTrack.artists} artistId={playback.currentTrack.artistId} {onOpenArtist} album={playback.currentTrack.album} albumId={playback.currentTrack.albumId} {onOpenAlbum} />
            {:else}<span class="artist">Seleccioná una canción</span>{/if}
          </div>
        {/if}
        {#if likeError}
          <span class="status like-error" role="alert" title={likeError}>{likeError}</span>
        {/if}
      </div>
        <button class="more-toggle" type="button" disabled={!onOpenMenu || !hasTrack} aria-label="Más opciones de la canción" title="Más opciones" onclick={onOpenMenu}>
          <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><circle cx="5" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="19" cy="12" r="1.7"/></svg>
        </button>
    </div>

    <div class="control-spacer" aria-hidden="true"></div>
    <div class="end-controls">
      <div class="panel-shortcuts" class:obscured={volumeOpen} inert={volumeOpen}>
      {#if onSelectPanel}
        <button type="button" class="panel-shortcut" class:panel-active={fullscreenOpen && selectedPanel === "lyrics"} aria-label="Abrir letras" title="Letras" aria-pressed={fullscreenOpen && selectedPanel === "lyrics"} onclick={() => onSelectPanel?.("lyrics")}>
          <PlayerIcon name="lyrics" />
        </button>
        <button type="button" class="panel-shortcut" disabled aria-label="Genius no disponible todavía" title="Letras y anotaciones de Genius: todavía no disponibles en Windows"><PlayerIcon name="annotations" /></button>
        <button type="button" class="panel-shortcut" class:panel-active={fullscreenOpen && selectedPanel === "queue"} aria-label="Abrir cola" title="Cola de reproducción" aria-pressed={fullscreenOpen && selectedPanel === "queue"} onclick={() => onSelectPanel?.("queue")}>
          <PlayerIcon name="queue" />
        </button>
      {/if}
      </div>
      <div class="volume" class:open={volumeOpen} bind:this={volumeRoot} role="group" aria-label="Volumen" onpointerenter={() => volumeHovered = true} onpointerleave={leaveVolume} onfocusout={handleVolumeFocusOut}>
        <button bind:this={volumeButton} type="button" class="volume-toggle" aria-label="Mostrar volumen" title={`Volumen: ${Math.round(volume)}%`} aria-expanded={volumeOpen} aria-controls="player-volume" aria-hidden={volumeOpen} tabindex={volumeOpen ? -1 : 0} onclick={toggleVolume}>
          <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M3 9v6h4l5 5V4L7 9zm12.5 3a4 4 0 0 0-2-3.46v6.92a4 4 0 0 0 2-3.46" /></svg>
        </button>
        <div id="player-volume" class="volume-popover" data-volume-popover={volumeOpen ? '' : undefined} inert={!volumeOpen} aria-hidden={!volumeOpen} role="group" aria-label="Control de volumen">
        <input bind:this={volumeSlider}
          type="range"
          min="0"
          max="100"
          step="1"
          value={volume}
          style={`--fill:${volume}%`}
          oninput={handleVolumeInput}
          onpointerdown={() => volumeDragging = true}
          aria-label="Volumen"
          aria-valuetext={`${Math.round(volume)}%`}
        />
        <button type="button" class="volume-mute" aria-label={volume > 0 ? 'Silenciar' : 'Activar sonido'} title={`${volume > 0 ? 'Silenciar' : 'Activar sonido'} · ${Math.round(volume)}%`} onclick={toggleMute}>
          <svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M3 9v6h4l5 5V4L7 9" />
            {#if volume === 0}<path d="m16 9 5 6m0-6-5 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" />
            {:else}<path d="M15.5 12a4 4 0 0 0-2-3.46v6.92a4 4 0 0 0 2-3.46" />{/if}
          </svg>
        </button>
        </div>
      </div>
      <button
        type="button"
        class="fullscreen-toggle"
        aria-label={fullscreenOpen ? "Cerrar pantalla completa" : "Abrir pantalla completa"}
        title={fullscreenOpen ? "Cerrar pantalla completa" : "Abrir pantalla completa"}
        aria-expanded={fullscreenOpen}
        aria-controls="fullscreen-now-playing"
        onclick={onToggleFullscreen}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" class:flipped={fullscreenOpen}>
          <path d="m6 14 6-6 6 6" />
        </svg>
      </button>
    </div>
  </div>
</footer>

<style>
  .player-bar {
    position: relative;
    box-sizing: border-box;
    width: min(100%, 820px);
    min-width: 0;
    height: 74px;
    min-height: 74px;
    max-height: 74px;
    padding: 0;
    color: #f5f5f6;
    background: var(--sideb-acrylic-fallback, #353538);
    border: 1px solid var(--sideb-acrylic-border, rgb(255 255 255 / 20%));
    border-radius: 38px;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.34);
  }

  @supports ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
    .player-bar {
      background: var(--sideb-acrylic-surface);
      backdrop-filter: var(--sideb-acrylic-blur);
      -webkit-backdrop-filter: var(--sideb-acrylic-blur);
    }
  }

  .progress {
    position: absolute;
    top: 7px;
    left: 32px;
    right: 32px;
    display: grid;
    grid-template-columns: 40px minmax(0, 1fr) 40px;
    align-items: center;
    gap: 8px;
    height: 14px;
  }

  .time {
    color: rgba(255, 255, 255, 0.62);
    font-size: 10.5px;
    font-variant-numeric: tabular-nums;
    text-align: left;
  }

  .time-end { text-align: right; }

  input[type="range"] {
    appearance: none;
    -webkit-appearance: none;
    width: 100%;
    min-width: 0;
    margin: 0;
    border: 0;
    cursor: pointer;
    background: linear-gradient(to right, #d06c70 0 var(--fill), rgba(255, 255, 255, 0.18) var(--fill) 100%);
  }

  input[type="range"]:disabled { cursor: default; opacity: 0.45; }

  .seek { height: 2.5px; border-radius: 3px; }

  input[type="range"]::-webkit-slider-thumb {
    appearance: none;
    -webkit-appearance: none;
    width: 2.5px;
    height: 9px;
    border: 0;
    border-radius: 3px;
    background: #fff;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.5);
  }

  input[type="range"]::-moz-range-thumb {
    width: 2.5px;
    height: 9px;
    border: 0;
    border-radius: 3px;
    background: #fff;
  }

  .main-row {
    position: absolute;
    left: 20px;
    right: 20px;
    bottom: 4px;
    display: grid;
    grid-template-columns: 208px minmax(0, 1fr) 16px 232px;
    align-items: center;
    gap: 14px;
    height: 46px;
  }

  .transport { display: flex; align-items: center; justify-content: center; gap: 10px; }
  .skip, .mode-toggle { display: grid; flex: none; place-items: center; width: 32px; height: 32px; padding: 0; border: 0; border-radius: 6px; color: #dedee3; background: transparent; cursor: pointer; }
  .mode-toggle:disabled { color: rgb(255 255 255 / 45%); cursor: default; }
  .skip:hover:not(:disabled) { color: #fff; background: rgb(255 255 255 / 10%); }
  .skip:disabled { opacity: .38; cursor: default; }

  .play-toggle {
    display: grid;
    place-items: center;
    box-sizing: border-box;
    width: 40px;
    flex: 0 0 40px;
    height: 40px;
    padding: 9px;
    border: 1px solid transparent;
    border-radius: 50%;
    color: #fff;
    background: #a33d45;
    background-clip: padding-box;
    cursor: pointer;
  }

  .play-toggle:hover:not(:disabled) { background-color: #b85058; }
  .play-toggle:disabled { opacity: 0.48; cursor: default; }
  .play-toggle.errored { color: #ffd37a; }
  .play-toggle svg { width: 20px; height: 20px; }

  .spinner {
    box-sizing: border-box;
    width: 18px;
    height: 18px;
    border: 2px solid rgba(255, 255, 255, 0.35);
    border-top-color: #fff;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin { to { transform: rotate(360deg); } }

  .track {
    position: relative;
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
    padding-left: 14px;
  }
  .track::before { content: ''; position: absolute; left: 0; top: 50%; width: 1px; height: 22px; transform: translateY(-50%); background: rgb(255 255 255 / 13%); }

  .artwork {
    display: grid;
    flex: 0 0 46px;
    place-items: center;
    width: 46px;
    height: 46px;
    overflow: hidden;
    color: #aaaab2;
    background: rgba(255, 255, 255, 0.08);
    border-radius: 8px;
  }

  .artwork img { width: 100%; height: 100%; object-fit: cover; }
  .artwork svg { width: 18px; height: 18px; }
  .metadata { display: flex; flex: 1; flex-direction: column; gap: 2px; min-width: 0; }
  .title-line { display: flex; min-width: 0; align-items: center; gap: 7px; }
  .title, .artist, .status { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .title { flex: 1; min-width: 0; font-size: 13px; font-weight: 650; line-height: 16px; }
  .artist, .status { color: #a4a4a8; font-size: 11.5px; font-weight: 500; line-height: 14px; }
  .artist-line { display: flex; min-width: 0; align-items: center; overflow: hidden; color: #a4a4a8; font-size: 11.5px; font-weight: 500; line-height: 14px; }
  .status.error { color: #ffd37a; }
  .status.like-error { color: #ff9ba1; }
  .like-toggle { display: grid; flex: 0 0 22px; place-items: center; width: 22px; height: 22px; padding: 4px; border: 0; border-radius: 50%; color: rgb(255 255 255 / 62%); background: transparent; cursor: pointer; }
  .like-toggle:hover:not(:disabled) { color: #fff; background: rgb(255 255 255 / 9%); }
  .like-toggle.liked { color: #d06c70; }
  .like-toggle:disabled { opacity: .55; cursor: wait; }
  .like-toggle svg { width: 14px; height: 14px; }
  .like-spinner { width: 13px; height: 13px; border: 2px solid rgb(255 255 255 / 30%); border-top-color: #d06c70; border-radius: 50%; animation: spin .8s linear infinite; }

  .end-controls { display: flex; align-items: center; justify-content: flex-end; gap: 8px; min-width: 0; }
  .panel-shortcuts { display: flex; flex: none; align-items: center; gap: 8px; opacity: 1; transition: opacity 280ms ease; }
  .panel-shortcuts.obscured { opacity: 0; pointer-events: none; }
  .panel-shortcut, .more-toggle { display: grid; flex: 0 0 32px; place-items: center; width: 32px; height: 32px; padding: 0; border: 0; border-radius: 7px; color: rgb(255 255 255 / 65%); background: transparent; cursor: pointer; }
  .more-toggle { width: 28px; height: 28px; flex-basis: 28px; }
  .more-toggle svg { width: 16px; height: 16px; }
  .panel-shortcut:disabled, .more-toggle:disabled { color: rgb(255 255 255 / 40%); cursor: default; }
  .panel-shortcut:hover:not(:disabled), .more-toggle:hover:not(:disabled) { color: #fff; background: rgb(255 255 255 / 10%); }
  .panel-shortcut.panel-active { color: #d06c70; }
  .volume { position: relative; flex: 0 0 32px; width: 32px; height: 32px; }
  .volume-toggle { display: grid; place-items: center; width: 32px; height: 32px; padding: 7px; border: 0; border-radius: 7px; color: #c6c6cd; background: transparent; cursor: pointer; transition: opacity 280ms ease; }
  .volume.open .volume-toggle { opacity: 0; pointer-events: none; }
  .volume-toggle:hover, .volume-toggle[aria-expanded="true"] { color: #fff; background: rgb(255 255 255 / 10%); }
  .volume svg { width: 18px; height: 18px; }
  .volume-popover { position: absolute; right: 0; top: -2px; z-index: 2; box-sizing: border-box; display: flex; align-items: center; gap: 10px; width: 152px; height: 36px; padding: 0 10px 0 14px; border: 1px solid var(--sideb-acrylic-border, rgb(255 255 255 / 20%)); border-radius: 999px; background: var(--sideb-acrylic-fallback, #29292f); box-shadow: 0 4px 10px rgb(0 0 0 / 35%); opacity: 0; transform: scale(.92); transform-origin: right center; visibility: hidden; pointer-events: none; transition: opacity 280ms ease, transform 280ms cubic-bezier(.2,.8,.2,1), visibility 0s linear 280ms; }
  @supports ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
    .volume-popover { background: var(--sideb-acrylic-surface); backdrop-filter: var(--sideb-acrylic-blur); -webkit-backdrop-filter: var(--sideb-acrylic-blur); }
  }
  .volume.open .volume-popover { opacity: 1; transform: scale(1); visibility: visible; pointer-events: auto; transition-delay: 0s; }
  .volume input { flex: 1; height: 11px; border-radius: 999px; background: linear-gradient(to right, #fff 0 var(--fill), rgb(255 255 255 / 16%) var(--fill) 100%); }
  .volume input::-webkit-slider-thumb { width: 1px; height: 18px; border-radius: 0; background: transparent; box-shadow: none; }
  .volume input::-moz-range-thumb { width: 1px; height: 18px; border-radius: 0; background: transparent; }
  .volume-mute { display: grid; flex: 0 0 22px; place-items: center; width: 22px; height: 32px; padding: 0; border: 0; border-radius: 6px; color: #fff; background: transparent; cursor: pointer; }
  .volume-mute:hover { color: #fff; background: rgb(255 255 255 / 8%); }
  .fullscreen-toggle { display: grid; flex: 0 0 32px; place-items: center; width: 32px; height: 32px; padding: 5px; border: 0; border-radius: 7px; color: rgb(255 255 255 / 75%); background: transparent; cursor: pointer; }
  .fullscreen-toggle:hover { color: #fff; background: rgb(255 255 255 / 10%); }
  .fullscreen-toggle svg { width: 20px; height: 20px; transition: transform 180ms ease; }
  .fullscreen-toggle svg.flipped { transform: rotate(180deg); }

  button:focus-visible, input:focus-visible {
    outline: 2px solid #d06c70;
    outline-offset: 3px;
  }

  @media (prefers-reduced-motion: reduce) {
    .spinner { animation-duration: 2s; }
    .panel-shortcuts, .volume-toggle, .volume-popover { transition: none; }
  }

  @media (forced-colors: active) {
    .player-bar, .volume-popover { background: Canvas; border-color: CanvasText; color: CanvasText; backdrop-filter: none; -webkit-backdrop-filter: none; }
  }
</style>

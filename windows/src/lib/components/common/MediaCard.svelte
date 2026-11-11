<script lang="ts">
  import { t } from '$lib/i18n';
  import { albumCollectionType } from '$lib/home/collectionMetadata';
  import { getContext } from 'svelte';
  import type { BrowseCardDto } from '$lib/types';
  import { MEDIA_CONTEXT, mediaKey, sourceActive, type MediaService } from '$lib/player/media';
  import { createMenuHandlers } from '$lib/menu/hooks';
  import { targetFromCard } from '$lib/menu/types';
  import ArtistCredits from '$lib/components/ArtistCredits.svelte';
  import FeaturedTrackTitle from '$lib/components/FeaturedTrackTitle.svelte';
  import MediaArtwork from './MediaArtwork.svelte';
  import MoreIcon from './MoreIcon.svelte';
  import { coverColor, cssColor } from '$lib/home/coverColor';
  import { fallbackArtworkUrl } from '$lib/images/artwork';
  interface Props { card: BrowseCardDto; layout?: 'vertical' | 'panel' | 'mosaic' | 'compact'; size?: 'small' | 'wide' | 'large'; panelStyle?: 'white' | 'tinted'; coverSession?: string; onOpen?: () => void; onPlay?: () => void; onOpenArtist?: (id: string) => void; onOpenAlbum?: (id: string) => void; summary?: string | null }
  let { card, layout = 'vertical', size = 'small', panelStyle = 'tinted', coverSession, onOpen, onPlay, onOpenArtist, onOpenAlbum, summary }: Props = $props();
  const media = getContext<MediaService | undefined>(MEDIA_CONTEXT);
  const menu = createMenuHandlers()(() => targetFromCard(card));
  const song = $derived(['song', 'video'].includes(card.kind));
  const creditTrack = $derived(song ? {videoId:card.id,title:card.title,artists:card.artists??'',artistRuns:card.artistRuns,artistId:card.artistId,album:card.album,contentRating:card.contentRating,explicit:card.explicit} : undefined);
  const active = $derived(media && card.kind !== 'artist' ? sourceActive(media.state(), card.kind, card.id) : false);
  const pending = $derived(media?.pending() === mediaKey(card));
  const releaseType = $derived(albumCollectionType(card, summary ? { subtitle: summary } : null));
  // Acabado «tinted»: la carátula en miniatura, espejada y desenfocada, detrás del texto.
  const wash = $derived.by(() => {
    const url = layout === 'panel' && panelStyle === 'tinted' ? card.thumbnail : null;
    return url ? `url("${(fallbackArtworkUrl(url, 32) ?? url).replace(/"/g, '%22').replace(/\\/g, '%5C')}")` : undefined;
  });
  let cover = $state<string | null>(null);
  // Color de la carátula para tintar el degradado del mosaico; se descarta si cambió la carátula o la sesión antes de resolver.
  $effect(() => {
    const url = card.thumbnail, session = coverSession;
    cover = null;
    if (layout !== 'mosaic' || !session || !url) return;
    let current = true;
    coverColor(url, session).then(rgb => { if (current) cover = cssColor(rgb); });
    return () => { current = false; };
  });
  function play() { if (media) media.activate(card); else onPlay?.(); }
  function primary() { if (song) play(); else onOpen?.(); }
</script>
<article class="media-card" class:panel={layout === 'panel'} class:tinted={layout === 'panel' && panelStyle === 'tinted'} class:compact={layout === 'compact'} class:mosaic={layout === 'mosaic'} class:small={layout === 'mosaic' && size === 'small'} class:wide={layout === 'mosaic' && size === 'wide'} class:large={layout === 'mosaic' && size === 'large'} class:active class:vertical={layout === 'vertical'} style:--cover-color={cover} aria-label={card.title} oncontextmenu={menu.onContextMenu}>
  <button type="button" class="primary" data-search-primary aria-label={`${song ? active && media?.state().isPlaying ? $t('player.pause') : $t('player.play') : $t('home.open')} ${card.title}`} onclick={primary} onkeydown={menu.onKeyDown}></button>
  <div class="art"><MediaArtwork thumbnail={card.thumbnail} title={card.title} {active} playing={media?.state().isPlaying ?? false} {pending} {song} round={card.kind === 'artist'} onPlay={card.kind !== 'artist' && (media || onPlay) ? play : undefined} onMenu={menu.onContextMenu} /></div>
  <div class="copy">{#if wash}<span class="wash" style:background-image={wash} aria-hidden="true"></span>{/if}{#if layout === 'panel'}<p class="badge">{card.kind === 'album' ? releaseType === 'single' ? $t('metadata.single') : releaseType === 'ep' ? 'EP' : $t('detail.kind.album') : $t('detail.kind.playlist')}</p>{/if}<div class="title-row"><h3>{#if creditTrack}<FeaturedTrackTitle track={creditTrack} {onOpenArtist} onPlay={primary} />{:else}{card.title}{/if}</h3></div>
    <div class="metadata-line"><div class="credits"><ArtistCredits content={song || card.kind==='album' ? card : undefined} track={creditTrack} artistRuns={card.artistRuns} artists={card.artists ?? card.subtitle ?? ''} artistId={card.artistId} {onOpenArtist} album={song && layout !== 'mosaic' ? card.album : null} albumId={song && layout !== 'mosaic' ? card.albumId : null} {onOpenAlbum} /></div></div>
    {#if summary}<p class="summary">{summary}</p>{/if}
  </div>
  {#if layout==='compact'}<button type="button" class="compact-menu" aria-label={$t('common.moreOptionsFor', [card.title])} onclick={menu.onContextMenu}><MoreIcon /></button>{/if}
</article>
<style>
  .media-card { position:relative; isolation:isolate; min-width:0; width:100%; color:inherit; border-radius:10px; }
  .primary { position:absolute; inset:0; z-index:-1; width:100%; border:0; border-radius:10px; background:transparent; cursor:pointer; }
  .primary:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:3px; }
  .art { pointer-events:none; aspect-ratio:1; width:100%; }
  .copy { pointer-events:none; min-width:0; padding-top:9px; } .copy :global(.featured-link),.copy :global(.title-text),.credits :global(button), .credits :global(a) { pointer-events:auto; }
  h3 { margin:0; font-size:14px; line-height:19px; font-weight:600; display:-webkit-box; -webkit-box-orient:vertical; -webkit-line-clamp:2; line-clamp:2; overflow:hidden; }
  p,.credits { margin:4px 0 0; font-size:12px; line-height:17px; color:#b6b6bf; overflow:hidden; } p { display:-webkit-box; -webkit-box-orient:vertical; -webkit-line-clamp:2; line-clamp:2; }
  .metadata-line {display:flex;align-items:center;gap:6px;min-width:0;margin-top:4px;} .metadata-line .credits {margin-top:0;min-width:0;}
  .title-row { display:flex; align-items:center; gap:6px; min-width:0; } .title-row h3 { min-width:0; flex:1; }
  .compact { display:flex; align-items:center; gap:10px; height:56px; } .compact .art { width:44px; height:44px; flex:none; } .compact .copy { padding:0; padding-right:32px; } .compact h3 { font-size:13px; -webkit-line-clamp:1; line-clamp:1; }
  .compact :global(.play) { width:28px; height:28px; } .compact :global(.menu) { display:none; }
  .compact :global(.artwork) { overflow:visible; } .compact :global(.artwork img) { border-radius:6px; } .compact-menu { display:grid; place-items:center; padding:0; position:absolute; right:3px; top:14px; width:28px; height:28px; border:0; border-radius:6px; background:#0008; color:white; cursor:pointer; opacity:0; } .media-card:hover .compact-menu,.compact-menu:focus-visible { opacity:1; }
  /* Mosaico de Inicio: portada a sangre, degradado inferior teñido con el color de la carátula y texto directo encima. Play, menú y ecualizador de MediaArtwork se reposicionan. */
  .mosaic { --inset:10px; --bottom:9px; --title:13px; --title-lh:16px; --title-w:600; --title-ls:0; --artist:11.5px; --artist-lh:15px; --play:30px; --pgap:8px; --grad:72%; --bar-h:11px; --bar-w:2.5px; --bar-gap:2px; --bars-w:17.5px;
    height:100%; }
  .mosaic.wide { --inset:12px; --bottom:11px; --title:16px; --title-lh:20px; --title-w:700; --artist:12.5px; --artist-lh:16px; --play:32px; --pgap:10px; --bar-h:13px; --bar-w:3px; --bars-w:19px; }
  .mosaic.large { --inset:16px; --bottom:14px; --title:22px; --title-lh:27px; --title-w:700; --title-ls:-.2px; --artist:14px; --artist-lh:19px; --play:40px; --pgap:14px; --grad:52%; --bar-h:16px; --bar-w:3.5px; --bar-gap:2.5px; --bars-w:21.5px; }
  .mosaic .art { position:absolute; inset:0; width:100%; height:100%; aspect-ratio:auto; }
  .mosaic .art::after { content:""; position:absolute; left:0; right:0; bottom:0; height:var(--grad); border-radius:0 0 10px 10px; pointer-events:none;
    --scrim:color-mix(in srgb,var(--cover-color,#101014) 30%,#0b0b0f);
    background:linear-gradient(to top,color-mix(in srgb,var(--scrim) 94%,transparent) 0,color-mix(in srgb,var(--scrim) 80%,transparent) 20%,color-mix(in srgb,var(--scrim) 48%,transparent) 42%,color-mix(in srgb,var(--scrim) 14%,transparent) 66%,transparent); }
  .mosaic .copy { position:absolute; z-index:1; left:var(--inset); right:var(--inset); bottom:var(--bottom); box-sizing:border-box; padding:0; transition:padding .18s cubic-bezier(.2,.8,.2,1); }
  .mosaic h3 { display:block; font-size:var(--title); line-height:var(--title-lh); font-weight:var(--title-w); letter-spacing:var(--title-ls); color:#fff; white-space:nowrap; text-overflow:ellipsis; text-shadow:0 1px 2px rgb(0 0 0 / 35%);
    /* El título con botones no admite puntos suspensivos: si no entra, se desvanece en el borde. */
    mask-image:linear-gradient(to right,#000 calc(100% - 18px),transparent); }
  .mosaic .metadata-line { margin-top:0; }
  .mosaic .credits { min-height:var(--artist-lh); font-size:var(--artist); line-height:var(--artist-lh); color:rgb(255 255 255 / 72%); white-space:nowrap; text-overflow:ellipsis; text-shadow:0 1px 2px rgb(0 0 0 / 35%); } .mosaic .credits :global(.artist-credits) { vertical-align:top; }
  .media-card.mosaic :global(.artwork .play) { z-index:2; top:auto; left:auto; transform:none; right:var(--pgap); bottom:var(--pgap); width:var(--play); height:var(--play); background:#fff; color:#111; }
  .media-card.mosaic :global(.artwork .play:hover) { background:#fff; } .media-card.mosaic :global(.artwork .play:focus-visible) { outline-color:#111; }
  .media-card.mosaic :global(.artwork .play .spinner) { border-color:rgb(0 0 0 / 25%); border-top-color:#111; }
  .media-card.mosaic :global(.artwork .menu) { z-index:2; }
  .media-card.mosaic.large :global(.artwork .play) { opacity:1; pointer-events:auto; } .media-card.mosaic.large :global(.artwork .play:disabled) { pointer-events:none; }
  .mosaic.large .copy,.mosaic:hover .copy,.mosaic:focus-within .copy { padding-right:calc(var(--play) + 14px); }
  .media-card.mosaic :global(.artwork .bars) { z-index:2; inset:auto; left:var(--inset); bottom:calc(var(--bottom) + var(--artist-lh) + (var(--title-lh) - var(--bar-h)) / 2); width:auto; height:var(--bar-h); gap:var(--bar-gap); background:none; opacity:1; }
  .media-card.mosaic :global(.artwork .bars i) { width:var(--bar-w); height:100%; max-height:none; transform-origin:bottom; } .media-card.mosaic :global(.artwork .bars i:nth-child(n+4)) { display:none; }
  .media-card.mosaic :global(.artwork .bars.paused) { opacity:.5; }
  .mosaic.active h3 { padding-left:var(--bars-w); }
  .media-card.mosaic :global(.artwork img) { transition:transform .25s cubic-bezier(.2,.8,.2,1); }
  .media-card.mosaic:has(:focus-visible) :global(.artwork img) { transform:scale(1.04); }
  @media (hover:hover) { .media-card.mosaic:hover :global(.artwork img) { transform:scale(1.04); } }
  @media (prefers-reduced-motion:reduce) { .mosaic .copy,.media-card.mosaic :global(.artwork img) { transition:none; } .media-card.mosaic:has(:focus-visible) :global(.artwork img),.media-card.mosaic:hover :global(.artwork img) { transform:none; } }
  /* Tarjeta de colección: portada cuadrada y panel claro debajo. Play y menú de MediaArtwork se reposicionan sobre la portada. */
  .panel { display:flex; flex-direction:column; height:100%; overflow:hidden; border-radius:14px; background:#f5f5f7; box-shadow:0 12px 30px -16px #000;
    --panel-title:#1d1d1f; --panel-artist:#3a3a3c; --panel-muted:#6e6e73; transition:transform .18s cubic-bezier(.2,.8,.2,1),box-shadow .18s cubic-bezier(.2,.8,.2,1); }
  .panel.tinted { --panel-artist:rgb(0 0 0 / 79%); --panel-muted:rgb(0 0 0 / 58%); }
  .panel .primary { border-radius:14px; } .panel .primary:focus-visible { outline:none; }
  .panel:has(.primary:focus-visible) { outline:2px solid var(--sideb-highlight); outline-offset:3px; }
  .panel .art { flex:none; position:relative; } .panel :global(.artwork) { border-radius:0; }
  .panel .art::after { content:""; position:absolute; inset:0; background:#000; opacity:0; pointer-events:none; transition:opacity .15s; }
  .panel:focus-within .art::after { opacity:.3; }
  .panel .copy { position:relative; isolation:isolate; overflow:hidden; flex:1; box-sizing:border-box; padding:12px 14px 14px; background:#f5f5f7; }
  .panel .wash { position:absolute; inset:-34px; z-index:-1; pointer-events:none; background-size:cover; background-position:center; transform:scaleY(-1); filter:blur(26px) saturate(1.5); }
  .panel .wash::after { content:""; position:absolute; inset:0; background:rgb(255 255 255 / 78%); }
  .panel .badge { margin:0 0 2px; color:var(--panel-muted); font-size:10px; line-height:14px; font-weight:700; letter-spacing:1.2px; }
  .panel h3 { display:block; font-size:17px; line-height:22px; font-weight:700; color:var(--panel-title); white-space:nowrap; text-overflow:ellipsis; }
  .panel .metadata-line { margin-top:0; }
  .panel .credits { margin-top:0; font-size:14px; line-height:19px; font-weight:500; color:var(--panel-artist); white-space:nowrap; text-overflow:ellipsis; }
  .panel .credits :global(.credit-link:hover),.panel .credits :global(.featured-link:hover) { color:#000; text-decoration:underline; }
  .panel .credits :global(.credit-link:focus-visible),.panel .credits :global(.featured-link:focus-visible) { outline-color:#0a5fd0; }
  .panel .summary { margin-top:6px; font-size:12px; line-height:16px; color:var(--panel-muted); -webkit-line-clamp:2; line-clamp:2; }
  .media-card.panel :global(.artwork .play),.media-card.panel :global(.artwork .menu) { z-index:2; width:38px; height:38px; bottom:12px; background:rgb(255 255 255 / 22%); backdrop-filter:blur(12px); }
  .media-card.panel :global(.artwork .play) { left:12px; right:auto; } .media-card.panel :global(.artwork .menu) { top:auto; right:12px; border-radius:50%; }
  .media-card.panel :global(.artwork .play:hover),.media-card.panel :global(.artwork .menu:hover) { background:rgb(255 255 255 / 34%); }
  .media-card.panel :global(.artwork .play svg) { width:20px; height:20px; }
  .panel:focus-within { z-index:1; }
  @media (hover:hover) { .panel:hover { z-index:2; transform:translateY(-4px); box-shadow:0 20px 34px -18px rgb(0 0 0 / 80%); } .panel:hover .art::after { opacity:.3; } }
  @media (prefers-reduced-transparency:reduce) { .media-card.panel :global(.artwork .play),.media-card.panel :global(.artwork .menu) { background:rgb(0 0 0 / 60%); backdrop-filter:none; } }
  @media (prefers-reduced-motion:reduce) { .panel,.panel .art::after { transition:none; } }
  @media (hover:hover) { .compact:hover { background:var(--sideb-surface); } }
</style>

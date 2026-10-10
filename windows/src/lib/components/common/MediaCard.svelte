<script lang="ts">
  import { t } from '$lib/i18n';
  import { albumCollectionType } from '$lib/home/collectionMetadata';
  import { getContext } from 'svelte';
  import type { BrowseCardDto } from '$lib/types';
  import { MEDIA_CONTEXT, mediaKey, sourceActive, type MediaService } from '$lib/player/media';
  import { createMenuHandlers } from '$lib/menu/hooks';
  import { targetFromCard } from '$lib/menu/types';
  import ArtistCredits from '$lib/components/ArtistCredits.svelte';
  import MediaArtwork from './MediaArtwork.svelte';
  import ExplicitBadge from './ExplicitBadge.svelte';
  import MoreIcon from './MoreIcon.svelte';
  interface Props { card: BrowseCardDto; layout?: 'vertical' | 'horizontal' | 'tile' | 'compact'; featured?: boolean; onOpen?: () => void; onPlay?: () => void; onOpenArtist?: (id: string) => void; onOpenAlbum?: (id: string) => void; summary?: string | null }
  let { card, layout = 'vertical', featured = false, onOpen, onPlay, onOpenArtist, onOpenAlbum, summary }: Props = $props();
  const media = getContext<MediaService | undefined>(MEDIA_CONTEXT);
  const menu = createMenuHandlers()(() => targetFromCard(card));
  const song = $derived(['song', 'video'].includes(card.kind));
  const active = $derived(media && card.kind !== 'artist' ? sourceActive(media.state(), card.kind, card.id) : false);
  const pending = $derived(media?.pending() === mediaKey(card));
  const releaseType = $derived(albumCollectionType(card, summary ? { subtitle: summary } : null));
  function play() { if (media) media.activate(card); else onPlay?.(); }
  function primary() { if (song) play(); else onOpen?.(); }
</script>
<article class="media-card" class:featured class:horizontal={layout === 'horizontal'} class:compact={layout === 'compact'} class:tile={layout === 'tile'} class:vertical={layout === 'vertical'} aria-label={card.title} oncontextmenu={menu.onContextMenu}>
  <button type="button" class="primary" aria-label={`${song ? active && media?.state().isPlaying ? $t('player.pause') : $t('player.play') : $t('home.open')} ${card.title}`} onclick={primary} onkeydown={menu.onKeyDown}></button>
  <div class="art"><MediaArtwork thumbnail={card.thumbnail} title={card.title} {active} playing={media?.state().isPlaying ?? false} {pending} {song} round={card.kind === 'artist'} onPlay={card.kind !== 'artist' && (media || onPlay) ? play : undefined} onMenu={menu.onContextMenu} /></div>
  <div class="copy">{#if featured}<p class="badge">{card.kind === 'album' ? releaseType === 'single' ? $t('metadata.single') : releaseType === 'ep' ? 'EP' : $t('detail.kind.album') : $t('detail.kind.playlist')}</p>{/if}<div class="title-row"><h3>{card.title}</h3>{#if card.explicit}<ExplicitBadge />{/if}</div>
    {#if card.artistRuns?.length || card.artists}<div class="credits"><ArtistCredits artistRuns={card.artistRuns} artists={card.artists ?? ''} artistId={card.artistId} {onOpenArtist} album={song && layout !== 'tile' ? card.album : null} albumId={song && layout !== 'tile' ? card.albumId : null} {onOpenAlbum} /></div>{:else if card.subtitle}<p>{card.subtitle}</p>{/if}
    {#if summary}<p class="summary">{summary}</p>{/if}
  </div>
  {#if layout==='compact'}<button type="button" class="compact-menu" aria-label={$t('common.moreOptionsFor', [card.title])} onclick={menu.onContextMenu}><MoreIcon /></button>{/if}
</article>
<style>
  .media-card { position:relative; isolation:isolate; min-width:0; width:100%; color:inherit; border-radius:10px; }
  .primary { position:absolute; inset:0; z-index:-1; width:100%; border:0; border-radius:10px; background:transparent; cursor:pointer; }
  .primary:focus-visible { outline:2px solid var(--sideb-highlight); outline-offset:3px; }
  .art { pointer-events:none; aspect-ratio:1; width:100%; }
  .copy { pointer-events:none; min-width:0; padding-top:9px; } .credits :global(button), .credits :global(a) { pointer-events:auto; }
  h3 { margin:0; font-size:14px; line-height:19px; font-weight:600; display:-webkit-box; -webkit-box-orient:vertical; -webkit-line-clamp:2; line-clamp:2; overflow:hidden; }
  p,.credits { margin:4px 0 0; font-size:12px; line-height:17px; color:#b6b6bf; overflow:hidden; } p { display:-webkit-box; -webkit-box-orient:vertical; -webkit-line-clamp:2; line-clamp:2; }
  .title-row { display:flex; align-items:center; gap:6px; min-width:0; } .title-row h3 { min-width:0; }
  .horizontal { display:flex; align-items:center; gap:18px; height:100%; } .horizontal .art { flex:none; height:100%; width:auto; } .horizontal .copy { padding:0; } .horizontal h3 { font-size:19px; line-height:24px; }
  .compact { display:flex; align-items:center; gap:10px; height:56px; } .compact .art { width:44px; height:44px; flex:none; } .compact .copy { padding:0; padding-right:32px; } .compact h3 { font-size:13px; -webkit-line-clamp:1; line-clamp:1; }
  .compact :global(.play) { width:28px; height:28px; } .compact :global(.menu) { display:none; }
  .compact :global(.artwork) { overflow:visible; } .compact :global(.artwork img) { border-radius:6px; } .compact-menu { display:grid; place-items:center; padding:0; position:absolute; right:3px; top:14px; width:28px; height:28px; border:0; border-radius:6px; background:#0008; color:white; cursor:pointer; opacity:0; } .media-card:hover .compact-menu,.compact-menu:focus-visible { opacity:1; }
  .tile { container-type:inline-size; border-radius:5px; } .tile .copy { position:absolute; bottom:0; left:0; right:0; padding:26px 8px 7px; background:linear-gradient(transparent,#000000c7); border-radius:0 0 5px 5px; } .tile h3 { font-size:12px; line-height:15px; -webkit-line-clamp:1; line-clamp:1; } .tile p,.tile .credits { margin:2px 0 0; font-size:10px; line-height:13px; color:#ffffffc2; white-space:nowrap; text-overflow:ellipsis; } .tile .credits :global(.artist-credits) { vertical-align:top; }
  @container (width < 110px) { .tile .credits,.tile p { display:none; } }
  .horizontal.featured { align-items:flex-start; gap:16px; container-type:inline-size; }
  .tile :global(.artwork),.featured :global(.artwork) { border-radius:5px; }
  .featured .copy { padding-top:0; } .featured .badge { margin:0 0 7px; color:#ffffff99; font-size:10px; line-height:14px; font-weight:700; letter-spacing:1.3px; }
  .featured h3 { font-size:25px; line-height:30px; font-weight:700; -webkit-line-clamp:1; line-clamp:1; }
  .featured .credits { margin-top:7px; font-size:15px; line-height:20px; font-weight:600; color:#f7f7f8; }
  .featured .summary { margin-top:7px; font-size:12px; line-height:17px; color:#ffffff99; }
  @media (hover:hover) { .compact:hover { background:var(--sideb-surface); } }
</style>

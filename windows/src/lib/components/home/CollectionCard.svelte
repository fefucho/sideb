<script lang="ts">
  import { language } from '$lib/i18n';
  import { collectionSummary } from '$lib/i18n/presentation';
  import type { HomeItemDto } from '$lib/types';
  import type { FeaturedMetadata } from '$lib/home/metadata';
  import { FEATURED } from '$lib/home/rail';
  import MediaCard from '../common/MediaCard.svelte';

  /**
   * Album/playlist card of the Home rails and the «Ver todo» sheet: square rounded artwork with
   * title, creator and one detail line underneath. No frame and no tinted footer; the text block
   * has a fixed height so the row never changes with the length of the metadata.
   */
  interface Props {
    item: HomeItemDto;
    detail: FeaturedMetadata;
    width?: number;
    onOpen: (item: HomeItemDto) => void;
    onOpenArtist?: (id: string) => void;
    onOpenAlbum?: (id: string) => void;
  }
  let { item, detail, width = FEATURED.albumWidth, onOpen, onOpenArtist, onOpenAlbum }: Props = $props();
  const card = $derived({ ...item, title: detail.title, subtitle: null, artists: detail.artists, artistId: detail.artistId, artistRuns: [] });
</script>
<div class="collection-card" data-collection-card={`${item.kind}|${item.id}`} style:width={`${width}px`} style:height={`${width + FEATURED.albumTextHeight}px`}>
  <MediaCard {card} layout="vertical" onOpen={() => onOpen(item)} {onOpenArtist} {onOpenAlbum} summary={collectionSummary(detail.summary, $language)} />
</div>

<style>
  .collection-card { flex:none; min-width:0; }
  .collection-card :global(.media-card) { height:100%; }
  .collection-card :global(.art) { height:auto; }
  /* A hairline keeps pale covers from dissolving into the page. */
  .collection-card :global(.artwork) { border-radius:10px; }
  .collection-card :global(.artwork)::after { content:""; position:absolute; inset:0; border:.5px solid #ffffff1a; border-radius:inherit; pointer-events:none; }
  .collection-card :global(.copy) { padding-top:10px; }
  .collection-card :global(h3) { font-size:13px; line-height:16px; font-weight:600; -webkit-line-clamp:1; line-clamp:1; }
  .collection-card :global(.metadata-line) { margin-top:2px; height:15px; }
  .collection-card :global(.credits) { height:15px; font-size:12px; line-height:15px; white-space:nowrap; text-overflow:ellipsis; }
  .collection-card :global(.summary) { margin:2px 0 0; height:14px; font-size:11px; line-height:14px; color:#ffffff73; -webkit-line-clamp:1; line-clamp:1; }
</style>

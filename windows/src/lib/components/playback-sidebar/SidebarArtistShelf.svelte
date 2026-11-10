<script lang="ts">
  /*
   * PLAN-023 W5 - "Fans also like" shelf of the playback sidebar (macOS: NativeSidebarArtistShelfCell).
   * Internal piece of SidebarRecommendations; W3 does NOT compose it directly.
   *
   * Props:
   *   session: number                              account session (resets the horizontal offset)
   *   cards: BrowseCardDto[]                       already limited by the projection (max 10)
   *   label: string                                accessible name of the shelf
   *   contextKey: string                           song/account occurrence; a change returns to the first card
   *   offset?: number / onOffset?: (n) => void     horizontal offset kept by the parent while the row is recycled
   *   onOpenArtist?: (browseId) => void            card click
   *   onArtistContextMenu?: (event, card) => void  override of the shared menu (default: MENU_CONTEXT)
   *
   * Cards are virtualized by RecommendedViewport (x axis). Vertical wheel gestures are not consumed by the
   * horizontal scroller, so they keep scrolling the sidebar; the arrows cover mice without horizontal wheel.
   */
  import RecommendedViewport from '../fullscreen/RecommendedViewport.svelte';
  import MediaCard from '../common/MediaCard.svelte';
  import { SIDEBAR_ARTIST_CARD_GAP, SIDEBAR_ARTIST_CARD_WIDTH } from '$lib/player/sidebarRecommendations';
  import type { BrowseCardDto } from '$lib/types';

  interface Props {
    session: number;
    cards: BrowseCardDto[];
    label: string;
    contextKey: string;
    offset?: number;
    onOffset?: (offset: number) => void;
    onOpenArtist?: (id: string) => void;
    onArtistContextMenu?: (event: MouseEvent, artist: BrowseCardDto) => void;
  }
  let { session, cards, label, contextKey, offset = 0, onOffset, onOpenArtist, onArtistContextMenu }: Props = $props();
  const columns = $derived(cards.map((artist, index) => ({ key: `${index}:${artist.id}`, artist })));
</script>

<div class="artist-shelf" data-sidebar-artist-shelf data-session={session}>
  <RecommendedViewport items={columns} size={() => SIDEBAR_ARTIST_CARD_WIDTH} axis="x" gap={SIDEBAR_ARTIST_CARD_GAP} contextKey={`${session}:${contextKey}`} initialOffset={offset} {onOffset} {label} arrowCenter="40px">
    {#snippet children(column)}
      {@const artist = column.artist}
      <article class="artist-card" data-sidebar-artist={artist.id} oncontextmenu={event => { if (!event.defaultPrevented) onArtistContextMenu?.(event, artist); }}>
        <MediaCard card={{ ...artist, kind: 'artist' }} onOpen={() => onOpenArtist?.(artist.id)} />
      </article>
    {/snippet}
  </RecommendedViewport>
</div>

<style>
  .artist-shelf { height: 140px; min-width: 0; box-sizing: border-box; padding-top: 4px; }
  /* The shared viewport reserves 44 px for the arrows; the sidebar uses the 16 px inset of the macOS shelf. */
  .artist-shelf :global(.recommended-viewport.horizontal) { padding-inline: 14px; }
  .artist-card { width: 92px; height: 130px; display: flex; flex-direction: column; align-items: center; text-align: center; background: transparent; color: #fff; }
  .artist-card :global(.media-card) { width: 92px; }
  .artist-card :global(.art) { width: 72px; height: 72px; margin-inline: auto; }
  .artist-card :global(.copy) { padding-top: 6px; }
  .artist-card :global(h3) { font-size: 12px; line-height: 15px; font-weight: 500; color: #fff; }
  .artist-card :global(.credits), .artist-card :global(p) { display: none; }
</style>

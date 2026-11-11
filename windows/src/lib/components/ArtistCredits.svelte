<script lang="ts">
  import ExplicitBadge from './common/ExplicitBadge.svelte';
  import { contentRating, type ContentMetadata } from '$lib/contentRating';
  import FeaturedArtistLink from './FeaturedArtistLink.svelte';
  import type { FeaturedTrack } from '$lib/featured/artists';
  import type { HomeArtistRunDto } from '$lib/types';
  import { titleMotion, type TitleMotionOptions } from '$lib/player/title-motion';

  interface Props {
    track?: FeaturedTrack;
    content?: ContentMetadata;
    artistRuns?: HomeArtistRunDto[] | null;
    artists?: string | null;
    artistId?: string | null;
    onOpenArtist?: (id: string) => void;
    album?: string | null;
    albumId?: string | null;
    onOpenAlbum?: (id: string) => void;
    wrap?: boolean;
    showContentRating?: boolean;
    /** Opt-in marquee for an overflowing artist • album line (shared `titleMotion` action; links stay interactive). */
    scroll?: boolean;
  }

  let {
    track,
    content,
    artistRuns: suppliedRuns,
    artists = null,
    artistId = null,
    onOpenArtist,
    album = null,
    albumId = null,
    onOpenAlbum,
    wrap = false,
    showContentRating = true,
    scroll = false,
  }: Props = $props();

  const runs = $derived(
    suppliedRuns?.length
      ? suppliedRuns.filter((run) => {
          const text = run.text.trim();
          // InnerTube also supplies punctuation runs between linked artist names.
          return text && (run.id || !/^(?:[,&;/·•]+|and|y)$/i.test(text));
        })
      : artists?.trim()
        ? [{ text: artists.trim(), id: artistId }]
        : []
  );
  const albumText = $derived(album?.trim() ?? '');
  let interactionPaused = $state(false);
  function motion(node: HTMLElement, options: TitleMotionOptions) { return titleMotion(node, options); }
</script>

{#if runs.length || albumText || (showContentRating && contentRating(content ?? track) !== 'unknown')}
  <span class="artist-credits" class:wrap class:scroll>
    {#if showContentRating}<ExplicitBadge item={content ?? track} />{/if}
    {#snippet creditParts()}
    {#if runs.length}<span class="artist-group">
      {#each runs as run, index (`${run.text}:${run.id ?? ''}:${index}`)}
        {#if index > 0}<span class="artist-separator" aria-hidden="true">{', '}</span>{/if}
        {#if track && onOpenArtist}
          <FeaturedArtistLink {track} name={run.text} id={run.id} {onOpenArtist} portal={scroll} onInteractionChange={scroll ? (value) => interactionPaused = value : undefined} />
        {:else if run.id && onOpenArtist}
          <button class="credit-link artist-name" type="button" title={run.text} onclick={() => onOpenArtist?.(run.id!)}>{run.text}</button>
        {:else}
          <span class="artist-name" title={run.text}>{run.text}</span>
        {/if}
      {/each}
    </span>{/if}
    {#if runs.length && albumText}<span class="album-separator" aria-hidden="true">•</span>{/if}
    {#if albumText}
      {#if albumId && onOpenAlbum}
        <button class="credit-link album-name" type="button" title={albumText} onclick={() => onOpenAlbum?.(albumId!)}>{albumText}</button>
      {:else}
        <span class="album-name" title={albumText}>{albumText}</span>
      {/if}
    {/if}
    {/snippet}
    {#if runs.length || albumText}
      {#if scroll}
        <span class="credit-viewport" use:motion={{ enabled: true, selector: '.credit-content', key: JSON.stringify([runs, albumText]), paused: interactionPaused }}><span class="credit-content">{@render creditParts()}</span></span>
      {:else}<span class="credit-content">{@render creditParts()}</span>{/if}
    {/if}
  </span>
{/if}

<style>
  .artist-credits { display: inline-flex; min-width: 0; max-width: 100%; align-items: center; gap: 4px; overflow: hidden; color: inherit; font: inherit; line-height: inherit; white-space: nowrap; vertical-align: baseline; }
  .credit-content { display:inline-flex; min-width:0; max-width:100%; align-items:baseline; gap:7px; overflow:hidden; }
  .artist-credits.wrap .credit-content { flex-wrap:wrap; overflow:visible; }
  .artist-credits.wrap { flex-wrap: wrap; overflow: visible; white-space: normal; }
  .artist-group { display: inline-flex; min-width: 0; align-items: baseline; overflow: hidden; }
  .artist-credits.wrap .artist-group { flex-wrap: wrap; overflow: visible; }
  .artist-name, .album-name { min-width: 0; max-width: 100%; flex: 0 1 auto; overflow: hidden; color: inherit; text-overflow: ellipsis; white-space: nowrap; }
  .artist-separator { flex: none; white-space: pre; }
  .album-separator { flex: none; color: currentColor; font-size: 1.05em; font-weight: 650; }
  .credit-link { padding: 0; border: 0; background: transparent; font: inherit; text-align: left; cursor: pointer; }
  /* Optional presentation tokens keep other callers unchanged. */
  .artist-name { font-weight: var(--credit-artist-weight, inherit); }
  .album-name { font-size: var(--credit-album-size, inherit); font-weight: var(--credit-album-weight, inherit); color: var(--credit-album-color, inherit); }
  .album-separator { font-size: var(--credit-separator-size, 1.05em); font-weight: var(--credit-separator-weight, 650); color: var(--credit-separator-color, currentColor); }
  /* Marquee mode: only the artist • album text moves; the rating badge stays put. Reduce Motion restores ellipsis. */
  .credit-viewport { display:block; flex:0 1 auto; min-width:0; overflow:clip; }
  .scroll .credit-content { display:flex; flex:none; width:max-content; max-width:none; overflow:visible; }
  .scroll .artist-group { overflow:visible; }
  .scroll .artist-name, .scroll .album-name { flex:none; max-width:none; overflow:visible; text-overflow:clip; }
  @media (prefers-reduced-motion: reduce) {
    .credit-viewport { overflow:hidden; }
    .scroll .credit-content { display:flex; width:auto; max-width:100%; overflow:hidden; }
    .scroll .artist-group { overflow:hidden; }
    .scroll .artist-name, .scroll .album-name { flex:0 1 auto; max-width:100%; overflow:hidden; text-overflow:ellipsis; }
  }
  .credit-link:hover { color: #fff; }
  .credit-link:focus-visible { outline: 2px solid var(--sideb-highlight, #d06c70); outline-offset: 2px; border-radius: 2px; }
</style>

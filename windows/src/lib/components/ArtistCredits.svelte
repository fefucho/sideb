<script lang="ts">
  import type { HomeArtistRunDto } from '$lib/types';

  interface Props {
    artistRuns?: HomeArtistRunDto[] | null;
    artists?: string | null;
    artistId?: string | null;
    onOpenArtist?: (id: string) => void;
    album?: string | null;
    albumId?: string | null;
    onOpenAlbum?: (id: string) => void;
    wrap?: boolean;
  }

  let {
    artistRuns: suppliedRuns,
    artists = null,
    artistId = null,
    onOpenArtist,
    album = null,
    albumId = null,
    onOpenAlbum,
    wrap = false,
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
</script>

{#if runs.length || albumText}
  <span class="artist-credits" class:wrap>
    {#if runs.length}<span class="artist-group">
      {#each runs as run, index (`${run.text}:${run.id ?? ''}:${index}`)}
        {#if index > 0}<span class="artist-separator" aria-hidden="true">, </span>{/if}
        {#if run.id && onOpenArtist}
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
  </span>
{/if}

<style>
  .artist-credits { display: inline-flex; min-width: 0; max-width: 100%; align-items: baseline; gap: 7px; overflow: hidden; color: inherit; font: inherit; line-height: inherit; white-space: nowrap; vertical-align: baseline; }
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
  .credit-link:hover { color: #fff; }
  .credit-link:focus-visible { outline: 2px solid var(--sideb-highlight, #d06c70); outline-offset: 2px; border-radius: 2px; }
</style>

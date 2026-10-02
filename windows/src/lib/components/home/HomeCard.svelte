<script lang="ts">
  import type { HomeItemDto } from '$lib/types';
  import ArtistCredits from '$lib/components/ArtistCredits.svelte';
  import { createMenuHandlers, targetFromHome } from '$lib/menu/hooks';

  export let item: HomeItemDto;
  export let onOpenAlbum: ((id: string) => void) | undefined = undefined;
  export let onOpenPlaylist: ((id: string) => void) | undefined = undefined;
  export let onOpenArtist: ((id: string) => void) | undefined = undefined;
  export let onPlaySong: ((item: HomeItemDto) => void) | undefined = undefined;
  const menu = createMenuHandlers()(() => targetFromHome(item), { view: 'home' });

  let imageFailed = false;
  let lastThumbnail = item.thumbnail;
  $: if (lastThumbnail !== item.thumbnail) {
    lastThumbnail = item.thumbnail;
    imageFailed = false;
  }
  $: typeLabel = ({
    album: 'Álbum', song: 'Canción', artist: 'Artista', playlist: 'Playlist',
    radio: 'Radio', mix: 'Mix', video: 'Video'
  } as Record<string, string>)[item.kind] ?? 'Recomendación';
  $: mainAction = item.id.trim() && item.kind === 'song' && onPlaySong
    ? () => onPlaySong?.(item)
    : item.id.trim() && item.kind === 'album' && onOpenAlbum
      ? () => onOpenAlbum?.(item.id)
      : item.id.trim() && item.kind === 'artist' && onOpenArtist
        ? () => onOpenArtist?.(item.id)
        : item.id.trim() && item.kind === 'playlist' && onOpenPlaylist
          ? () => onOpenPlaylist?.(item.id) : undefined;
  $: subtitleParts = (item.subtitle ?? '').split(/\s*[•·]\s*/).map((part) => part.trim()).filter(Boolean);
  $: expectedPrefix = ({
    album: ['album', 'álbum', 'single', 'sencillo', 'ep'],
    playlist: ['playlist', 'lista', 'mix'], song: ['song', 'canción', 'video', 'vídeo']
  } as Record<string, string[]>)[item.kind] ?? [];
  $: subtitleDetail = expectedPrefix.includes((subtitleParts[0] ?? '').toLocaleLowerCase())
    ? subtitleParts.slice(1).join(' • ')
    : subtitleParts.join(' • ');
  $: showsCredits = item.artistRuns.length > 0 || Boolean(item.artists) || item.kind === 'song' || item.kind === 'video';
  $: artistDetail = (item.artists ?? item.artistRuns.map((run) => run.text).join(', ')) || subtitleDetail;
</script>

<article class="card" aria-label={`${typeLabel}: ${item.title}`} oncontextmenu={menu.onContextMenu}>
  {#if mainAction}
    <button class="primary-action" type="button" onclick={mainAction} onkeydown={menu.onKeyDown} aria-label={`${typeLabel}: ${item.title}`}>
      <span class="cover-frame" class:artist={item.kind === 'artist'}>
        {#if item.thumbnail && !imageFailed}
          <img src={item.thumbnail} alt="" loading="lazy" onerror={() => (imageFailed = true)} />
        {:else}
          <span class="fallback" aria-hidden="true">{item.kind === 'artist' ? '♙' : '♫'}</span>
        {/if}
      </span>
      <span class="title">{item.title}</span>
    </button>
  {:else}
    <div class="primary-action">
      <span class="cover-frame" class:artist={item.kind === 'artist'}>
        {#if item.thumbnail && !imageFailed}
          <img src={item.thumbnail} alt="" loading="lazy" onerror={() => (imageFailed = true)} />
        {:else}
          <span class="fallback" aria-hidden="true">{item.kind === 'artist' ? '♙' : '♫'}</span>
        {/if}
      </span>
      <span class="title">{item.title}</span>
    </div>
  {/if}

  <div class="metadata" aria-label="{typeLabel}{item.explicit ? ', explícito' : ''}{artistDetail ? `, ${artistDetail}` : ''}">
    <span>{typeLabel}</span>
    {#if item.explicit}<span class="explicit" title="Contenido explícito" aria-label="Explícito">E</span>{/if}
    {#if showsCredits && (artistDetail || item.album)}
      <span aria-hidden="true">•</span>
      <ArtistCredits artistRuns={item.artistRuns} artists={item.artists ?? subtitleDetail} artistId={item.artistId} onOpenArtist={onOpenArtist} album={item.kind === 'song' || item.kind === 'video' ? item.album : null} albumId={item.kind === 'song' || item.kind === 'video' ? item.albumId : null} onOpenAlbum={onOpenAlbum} wrap />
    {:else if artistDetail}
      <span aria-hidden="true">•</span>
      <span>{artistDetail}</span>
    {/if}
  </div>
</article>

<style>
  .card { width:var(--home-card-artwork-size,160px); height:var(--home-card-height,254px); flex:0 0 var(--home-card-artwork-size,160px); display:flex; flex-direction:column; align-items:stretch; gap:0; padding:0; border:0; border-radius:12px; background:transparent; color:inherit; text-align:left; font:inherit; overflow:hidden; }
  .primary-action { width:100%; flex:none; display:flex; flex-direction:column; align-items:stretch; padding:0; border:0; background:transparent; color:inherit; text-align:left; font:inherit; }
  button.primary-action { cursor:pointer; }
  button.primary-action:hover .cover-frame { filter:brightness(1.08); }
  button.primary-action:focus-visible { outline:2px solid var(--sideb-highlight,#D06C70); outline-offset:2px; border-radius:12px; }
  .cover-frame { width:100%; aspect-ratio:1; display:grid; place-items:center; flex:none; overflow:hidden; border-radius:var(--home-card-artwork-radius,12px); background:var(--sideb-surface-hover,rgba(255,255,255,.08)); }
  .cover-frame.artist { border-radius:50%; }
  img { width:100%; height:100%; object-fit:cover; }
  .fallback { color:rgba(255,255,255,.55); font-size:32px; }
  .title { display:-webkit-box; -webkit-box-orient:vertical; -webkit-line-clamp:2; line-clamp:2; overflow:hidden; margin-top:var(--home-card-artwork-title-gap,11px); font-size:14px; line-height:18px; font-weight:600; }
  .metadata { min-height:34px; display:flex; flex-wrap:wrap; align-content:flex-start; align-items:baseline; gap:0 4px; overflow:hidden; margin-top:3px; color:rgba(255,255,255,.62); font-size:12px; line-height:16px; }
  .explicit { padding:0 3px; border-radius:2px; background:rgba(255,255,255,.12); color:rgba(255,255,255,.8); font-size:9px; line-height:12px; font-weight:700; }
  @container home-content (width < 760px) {
    .card { width:var(--home-card-artwork-size-narrow,140px); flex-basis:var(--home-card-artwork-size-narrow,140px); height:calc(var(--home-card-artwork-size-narrow,140px) + 94px); }
  }
</style>

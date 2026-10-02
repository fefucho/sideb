<script lang="ts">
  import type { HomeItemDto } from '$lib/types';
  import ArtistCredits from '$lib/components/ArtistCredits.svelte';
  import { createMenuHandlers, targetFromHome } from '$lib/menu/hooks';

  export let item: HomeItemDto;
  export let onPlaySong: ((item: HomeItemDto) => void) | undefined = undefined;
  export let onOpenArtist: ((id: string) => void) | undefined = undefined;
  export let onOpenAlbum: ((id: string) => void) | undefined = undefined;
  const menu = createMenuHandlers()(() => targetFromHome(item), { view: 'home' });

  let imageFailed = false;
  let lastThumbnail = item.thumbnail;
  $: if (lastThumbnail !== item.thumbnail) {
    lastThumbnail = item.thumbnail;
    imageFailed = false;
  }
  $: subtitleParts = (item.subtitle ?? '').split(/\s*[•·]\s*/).map((part) => part.trim()).filter(Boolean);
  $: firstSubtitle = (subtitleParts[0] ?? '').toLocaleLowerCase();
  $: fallbackArtist = item.artists || (['song', 'canción', 'video', 'vídeo'].includes(firstSubtitle)
    ? subtitleParts.slice(1).join(' • ')
    : subtitleParts[0] ?? '');
  $: artistText = item.artists || fallbackArtist;
</script>

<article class="compact" aria-label={`Canción: ${item.title}`} oncontextmenu={menu.onContextMenu}>
  {#if onPlaySong && item.id.trim()}
    <button class="main" type="button" onclick={() => onPlaySong?.(item)} onkeydown={menu.onKeyDown} aria-label={`Reproducir ${item.title}`}>
      <span class="art">
        {#if item.thumbnail && !imageFailed}<img src={item.thumbnail} alt="" loading="lazy" onerror={() => (imageFailed = true)} />{:else}<span aria-hidden="true">♫</span>{/if}
      </span>
      <span class="title-line"><span class="title">{item.title}</span>{#if item.explicit}<span class="explicit" title="Contenido explícito" aria-label="Explícito">E</span>{/if}</span>
    </button>
  {:else}
    <div class="main">
      <span class="art">
        {#if item.thumbnail && !imageFailed}<img src={item.thumbnail} alt="" loading="lazy" onerror={() => (imageFailed = true)} />{:else}<span aria-hidden="true">♫</span>{/if}
      </span>
      <span class="title-line"><span class="title">{item.title}</span>{#if item.explicit}<span class="explicit" title="Contenido explícito" aria-label="Explícito">E</span>{/if}</span>
    </div>
  {/if}
  <span class="metadata"><ArtistCredits artistRuns={item.artistRuns} artists={artistText} artistId={item.artistId} onOpenArtist={onOpenArtist} album={item.album} albumId={item.albumId} onOpenAlbum={onOpenAlbum} /></span>
</article>

<style>
  .compact { position:relative; box-sizing:border-box; width:var(--home-compact-card-width,330px); height:var(--home-compact-card-height,56px); flex:none; border:0; border-radius:10px; padding:0; background:transparent; color:inherit; text-align:left; font:inherit; }
  .compact:hover { background:var(--sideb-surface,rgba(255,255,255,.05)); }
  .main { box-sizing:border-box; width:100%; height:100%; min-width:0; display:flex; align-items:flex-start; gap:8px; padding:0 4px 0 0; border:0; background:transparent; color:inherit; text-align:left; font:inherit; cursor:pointer; }
  .main:focus-visible { outline:2px solid var(--sideb-highlight,#D06C70); outline-offset:1px; border-radius:8px; }
  .art { box-sizing:border-box; flex:0 0 50px; width:50px; height:var(--home-compact-card-height,56px); padding:var(--home-compact-artwork-inset,6px); display:grid; place-items:center; }
  .art img,.art>span { width:var(--home-compact-artwork-size,44px); height:var(--home-compact-artwork-size,44px); object-fit:cover; border-radius:var(--home-compact-artwork-radius,8px); background:var(--sideb-surface-hover,rgba(255,255,255,.08)); }
  .art>span { display:grid; place-items:center; color:rgba(255,255,255,.55); font-size:22px; }
  .title-line { min-width:0; flex:1; display:flex; align-items:center; gap:6px; margin-top:5px; padding-right:8px; }
  .title { min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-size:13px; line-height:23px; font-weight:600; }
  .explicit { flex:none; padding:0 3px; border-radius:2px; background:rgba(255,255,255,.12); color:rgba(255,255,255,.8); font-size:9px; line-height:12px; font-weight:700; }
  .metadata { position:absolute; z-index:1; left:58px; right:8px; bottom:5px; width:max-content; max-width:calc(100% - 66px); overflow:hidden; margin:0; color:rgba(255,255,255,.62); font-size:12px; line-height:17px; text-overflow:ellipsis; white-space:nowrap; }
  .metadata :global(.artist-credits) { display:flex; width:100%; }
  @container home-content (width < 760px) { .compact { width:var(--home-compact-card-width-narrow,286px); } }
</style>



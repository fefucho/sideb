<script lang="ts">
  import type { BrowseCardDto, SearchResultsDto, SongDto } from '$lib/types';
  import type { SearchPreviewData } from '$lib/search/preview';
  import { createMenuHandlers } from '$lib/menu/hooks';
  import type { MenuTarget } from '$lib/menu/types';

  interface Props {
    preview: SearchPreviewData;
    variant?: 'spotlight' | 'dropdown';
    onSelectCard: (card: BrowseCardDto) => void;
    onPlaySong: (song: SongDto) => void;
  }
  let { preview, variant = 'spotlight', onSelectCard, onPlaySong }: Props = $props();
  const createMenu = createMenuHandlers();
  const limits = $derived(variant === 'spotlight'
    ? { artists: 5, songs: 8, albums: 5, playlists: 5 }
    : { artists: 2, songs: 3, albums: 2, playlists: 2 });

  type Section = { key: 'top' | 'artists' | 'songs' | 'albums' | 'playlists'; label: string; icon: string };
  const sectionNames: Record<Section['key'], Omit<Section, 'key'>> = {
    top: { label: 'Mejor resultado', icon: 'star' }, artists: { label: 'Artistas', icon: 'artist' },
    songs: { label: 'Canciones', icon: 'song' }, albums: { label: 'Álbumes', icon: 'album' }, playlists: { label: 'Playlists', icon: 'playlist' }
  };
  function sections(results: SearchResultsDto): Section[] {
    const primary = results.top[0]?.kind.toLowerCase();
    const order: Section['key'][] = ['top', ...(primary === 'song' ? ['songs', 'artists', 'albums', 'playlists'] : primary === 'album' ? ['albums', 'songs', 'artists', 'playlists'] : ['artists', 'songs', 'albums', 'playlists']) as Section['key'][]];
    return order.filter((key) => key === 'top' ? results.top.length > 0 : key === 'songs' ? results.songs.length > 0 : results[key].length > 0)
      .map((key) => ({ key, ...sectionNames[key] }));
  }
  function songFromCard(card: BrowseCardDto): SongDto {
    return {
      videoId: card.id, title: card.title, artists: card.artists ?? '', artistRuns: card.artistRuns,
      album: card.album ?? null, duration: card.duration, thumbnail: card.thumbnail,
      isVideo: card.isVideo ?? card.kind === 'video', artistId: card.artistId ?? null, albumId: card.albumId ?? null,
    };
  }
  function pickCard(card: BrowseCardDto) { card.kind === 'song' || card.kind === 'video' ? onPlaySong(songFromCard(card)) : onSelectCard(card); }
  function target(card: BrowseCardDto): MenuTarget | null {
    if (card.kind === 'song' || card.kind === 'video') return { kind: 'song' as const, song: songFromCard(card) };
    if (card.kind === 'artist' || card.kind === 'album' || card.kind === 'playlist') return { kind: card.kind, card };
    return null;
  }
  const menuForCard = (card: BrowseCardDto) => createMenu(() => target(card), { view: 'search_results' });
  const menuForSong = (song: SongDto) => createMenu(() => ({ kind: 'song', song }), { view: 'search_results' });
  function kindLabel(kind: string) { return ({ artist: 'Artista', album: 'Álbum', playlist: 'Playlist', song: 'Canción', video: 'Video' } as Record<string, string>)[kind.toLowerCase()] ?? 'Resultado'; }
</script>

{#if preview.query.trim() && !preview.error && (!preview.results || preview.associatedQuery !== preview.query.trim())}
  <div class="loading" aria-label="Buscando resultados">
    {#each [1, 2, 3] as _}<div class="skeleton"><span></span><i><b></b><b></b></i></div>{/each}
  </div>
{:else if preview.error}
  <div class="state" role="status"><strong>No se pudieron cargar los resultados rápidos</strong><span>{preview.error}</span></div>
{:else if preview.results && preview.associatedQuery === preview.query.trim()}
  {@const results = preview.results}
  {@const categories = sections(results)}
  {#if categories.length}
    {#each categories as section (section.key)}
      <section class="category" aria-label={section.label}>
        <h3><span class="category-icon" aria-hidden="true">
          {#if section.key === 'top'}<svg viewBox="0 0 24 24"><path d="m12 3 2.7 5.5 6.1.9-4.4 4.3 1 6.1-5.4-2.9-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z"/></svg>
          {:else if section.key === 'artists'}<svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="3.5"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>
          {:else if section.key === 'songs'}<svg viewBox="0 0 24 24"><path d="M9 18V5l12-2v13M9 18a3.5 3.5 0 1 1-3.5-3.5A3.5 3.5 0 0 1 9 18Zm12-2a3.5 3.5 0 1 1-3.5-3.5A3.5 3.5 0 0 1 21 16Z"/></svg>
          {:else if section.key === 'albums'}<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2.5"/></svg>
          {:else}<svg viewBox="0 0 24 24"><path d="M4 6h16M4 12h16M4 18h16"/></svg>{/if}
        </span>{section.label}</h3>
        {#if section.key === 'top'}
          {@const card = results.top[0]}
          {@const menu = menuForCard(card)}
          <button class="card-row hero" type="button" oncontextmenu={menu.onContextMenu} onkeydown={menu.onKeyDown} onclick={() => pickCard(card)}>
            <span class="art" class:artist={card.kind === 'artist'} class:hero-art={true}>{#if card.thumbnail}<img src={card.thumbnail} alt="" />{:else}<span class="placeholder">{#if card.kind === 'artist'}<svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="3.5"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>{:else}<svg viewBox="0 0 24 24"><path d="M9 18V5l12-2v13M9 18a3.5 3.5 0 1 1-3.5-3.5A3.5 3.5 0 0 1 9 18Zm12-2a3.5 3.5 0 1 1-3.5-3.5A3.5 3.5 0 0 1 21 16Z"/></svg>{/if}</span>{/if}</span>
            <span class="copy"><strong>{card.title}</strong><span class="subtitle">{kindLabel(card.kind)}{#if card.subtitle}<i>·</i>{card.subtitle}{/if}</span></span>
            <span class="badge">Mejor resultado</span><span class="row-action" aria-hidden="true">{#if card.kind === 'song' || card.kind === 'video'}<svg viewBox="0 0 24 24"><path class="play" d="m8 5 12 7-12 7z"/></svg>{:else}<svg viewBox="0 0 24 24"><path d="m9 5 7 7-7 7"/></svg>{/if}</span>
          </button>
        {:else if section.key === 'songs'}
          {#each results.songs.slice(0, limits.songs) as song, index (song.videoId + '-' + (song.setVideoId ?? '') + '-' + index)}
            {@const menu = menuForSong(song)}
            <div class="song-row" oncontextmenu={menu.onContextMenu} role="group" aria-label={`Opciones de ${song.title}`}>
              <button type="button" class="song-hit" onkeydown={menu.onKeyDown} onclick={() => onPlaySong(song)} aria-label={`Reproducir ${song.title}`}>
                <span class="art">{#if song.thumbnail}<img src={song.thumbnail} alt="" />{:else}<span class="placeholder"><svg viewBox="0 0 24 24"><path d="M9 18V5l12-2v13M9 18a3.5 3.5 0 1 1-3.5-3.5A3.5 3.5 0 0 1 9 18Zm12-2a3.5 3.5 0 1 1-3.5-3.5A3.5 3.5 0 0 1 21 16Z"/></svg></span>{/if}</span>
                <span class="copy"><strong>{song.title}</strong><span class="subtitle">Canción<i>·</i>{song.artists}</span></span>
                {#if song.duration}<span class="duration">{song.duration}</span>{/if}<span class="row-action" aria-hidden="true"><svg viewBox="0 0 24 24"><path class="play" d="m8 5 12 7-12 7z"/></svg></span>
              </button>
            </div>
          {/each}
        {:else}
          {@const cards = section.key === 'artists' ? results.artists.slice(0, limits.artists) : section.key === 'albums' ? results.albums.slice(0, limits.albums) : results.playlists.slice(0, limits.playlists)}
          {#each cards as card (card.id)}
            {@const menu = menuForCard(card)}
            <button class="card-row" type="button" oncontextmenu={menu.onContextMenu} onkeydown={menu.onKeyDown} onclick={() => onSelectCard(card)}>
              <span class="art" class:artist={card.kind === 'artist'}>{#if card.thumbnail}<img src={card.thumbnail} alt="" />{:else}<span class="placeholder">{#if card.kind === 'artist'}<svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="3.5"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>{:else if card.kind === 'album'}<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2.5"/></svg>{:else}<svg viewBox="0 0 24 24"><path d="M9 18V5l12-2v13M9 18a3.5 3.5 0 1 1-3.5-3.5A3.5 3.5 0 0 1 9 18Zm12-2a3.5 3.5 0 1 1-3.5-3.5A3.5 3.5 0 0 1 21 16Z"/></svg>{/if}</span>{/if}</span>
              <span class="copy"><strong>{card.title}</strong><span class="subtitle">{kindLabel(card.kind)}{#if card.subtitle}<i>·</i>{card.subtitle}{/if}</span></span>
              <span class="row-action" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="m9 5 7 7-7 7"/></svg></span>
            </button>
          {/each}
        {/if}
      </section>
    {/each}
  {:else}<div class="state">No se encontraron resultados rápidos</div>{/if}
{/if}

<style>
  .category { display:flex; flex-direction:column; gap:2px; }
  .category h3 { display:flex; align-items:center; gap:6px; margin:0 8px 2px; color:rgb(255 255 255 / 62%); font-size:10.5px; font-weight:700; letter-spacing:.6px; text-transform:uppercase; }
  .category:first-child h3 { color:rgb(255 255 255 / 90%); }
  .category-icon { width:11px; height:11px; display:inline-flex; }
  .category-icon svg { width:100%; height:100%; fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; }
  .card-row,.song-hit { width:100%; min-width:0; display:flex; align-items:center; gap:12px; padding:6px 10px; border:0; border-radius:8px; background:transparent; color:inherit; text-align:left; cursor:pointer; font:inherit; }
  .card-row:hover,.song-hit:hover,.card-row:focus-visible,.song-hit:focus-visible { outline:none; background:rgb(255 255 255 / 8%); }
  .card-row.hero { padding-block:8px; }
  .art { flex:none; width:38px; height:38px; overflow:hidden; display:grid; place-items:center; border-radius:6px; background:rgb(255 255 255 / 6%); }
  .art.hero-art { width:48px; height:48px; }
  .art.artist { border-radius:50%; }
  .art img { width:100%; height:100%; object-fit:cover; }
  .placeholder { display:grid; width:20px; height:20px; place-items:center; color:rgb(255 255 255 / 48%); }
  .placeholder svg { width:100%; height:100%; fill:none; stroke:currentColor; stroke-width:1.5; stroke-linecap:round; stroke-linejoin:round; }
  .copy { display:flex; flex:1; flex-direction:column; gap:3px; min-width:0; }
  .copy strong { overflow:hidden; color:rgb(255 255 255 / 94%); font-size:13px; font-weight:500; text-overflow:ellipsis; white-space:nowrap; }
  .hero .copy strong { font-size:14px; font-weight:600; }
  .subtitle { display:flex; gap:5px; min-width:0; overflow:hidden; color:rgb(255 255 255 / 60%); font-size:11px; text-overflow:ellipsis; white-space:nowrap; }
  .subtitle i { font-style:normal; opacity:.55; }
  .hero .subtitle { color:rgb(255 255 255 / 82%); }
  .badge { flex:none; padding:3px 8px; border-radius:99px; background:rgb(255 255 255 / 10%); color:rgb(255 255 255 / 90%); font-size:10px; font-weight:600; white-space:nowrap; }
  .row-action { display:grid; flex:none; width:18px; place-items:center; color:rgb(255 255 255 / 45%); }
  .row-action svg { width:14px; height:14px; fill:none; stroke:currentColor; stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; }
  .row-action svg .play { fill:currentColor; stroke:none; }
  .song-row { border-radius:8px; }
  .song-hit { padding-block:5px; }
  .song-hit .copy { gap:2.5px; }
  .song-hit .copy strong { font-size:13px; }
  .duration { flex:none; color:rgb(255 255 255 / 44%); font-size:11px; margin-inline:0 2px; }
  .state { display:flex; flex-direction:column; align-items:center; gap:5px; padding:38px 16px; color:rgb(255 255 255 / 62%); font-size:12px; text-align:center; }
  .state strong { color:rgb(255 255 255 / 80%); font-weight:500; }
  .loading { display:flex; flex-direction:column; gap:12px; padding:8px 10px; }
  .skeleton { display:flex; align-items:center; gap:12px; height:42px; }
  .skeleton span { width:38px; height:38px; border-radius:6px; background:rgb(255 255 255 / 6%); }
  .skeleton i { display:flex; flex-direction:column; gap:5px; }
  .skeleton b { display:block; width:145px; height:9px; border-radius:4px; background:rgb(255 255 255 / 8%); }
  .skeleton b+ b { width:92px; background:rgb(255 255 255 / 5%); }
</style>

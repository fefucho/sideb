<script lang="ts">
  import type { BrowseCardDto, PlaybackTrackDto, SongDto } from '$lib/types';
  import type { RecommendationsSnapshot } from '$lib/player/recommendations';
  import ArtistCredits from '$lib/components/ArtistCredits.svelte';
  import { createMenuHandlers } from '$lib/menu/hooks';
  import { targetFromCard } from '$lib/menu/types';

  interface Props {
    snapshot: RecommendationsSnapshot;
    currentTrack: PlaybackTrackDto | null;
    isPlaying: boolean;
    onRefresh: () => void;
    onPlaySong: (song: SongDto) => void;
    onPlayNext?: (song: SongDto) => void;
    onOpenAlbum?: (id: string) => void;
    onOpenArtist?: (id: string) => void;
    onSongContextMenu?: (event: MouseEvent, song: SongDto) => void;
    onArtistContextMenu?: (event: MouseEvent, artist: BrowseCardDto) => void;
  }
  let { snapshot, currentTrack, isPlaying, onRefresh, onPlaySong, onPlayNext, onOpenAlbum, onOpenArtist,
    onSongContextMenu, onArtistContextMenu }: Props = $props();
  const menu = createMenuHandlers();
  let failedImages = $state(new Set<string>());
  const shelves = $derived(snapshot.data ? [
    { title: snapshot.data.artistName ? `Más de ${snapshot.data.artistName}` : 'Más de este artista',
      songs: snapshot.data.artistSongs, browseId: snapshot.data.artistBrowseId, kind: 'artist' },
    { title: snapshot.data.albumTitle ? `Del álbum: ${snapshot.data.albumTitle}` : 'Del mismo álbum',
      songs: snapshot.data.albumSongs, browseId: snapshot.data.albumBrowseId, kind: 'album' },
    { title: 'Canciones parecidas', songs: snapshot.data.similarSongs, browseId: null, kind: 'song' },
  ].filter(shelf => shelf.songs.length) : []);
  const artists = $derived(snapshot.data?.relatedArtists ?? []);
  const hasData = $derived(shelves.length > 0 || artists.length > 0);

  function chunks(songs: SongDto[]) {
    const columns: SongDto[][] = [];
    for (let index = 0; index < songs.length; index += 3) columns.push(songs.slice(index, index + 3));
    return columns;
  }
  function imageFailed(url: string) { failedImages = new Set([...failedImages, url]); }
  function songMenu(event: MouseEvent, song: SongDto) {
    if (onSongContextMenu) { event.preventDefault(); onSongContextMenu(event, song); }
    else menu({ kind: 'song', song }, { view: 'recommendations' }).onContextMenu(event);
  }
  function artistMenu(event: MouseEvent, card: BrowseCardDto) {
    if (onArtistContextMenu) { event.preventDefault(); onArtistContextMenu(event, card); }
    else menu(targetFromCard(card), { view: 'recommendations' }).onContextMenu(event);
  }
</script>

<section class="recommendations" aria-label="Recomendaciones" aria-busy={snapshot.loading}>
  <header>
    <span class="heading"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3Z"/></svg>Recomendaciones</span>
    <button type="button" class="refresh" disabled={snapshot.loading || !currentTrack} onclick={onRefresh} title="Obtener nuevas recomendaciones para esta pista">
      <svg class:spinning={snapshot.loading} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 8a8 8 0 1 0 1 8M20 3v5h-5"/></svg>Actualizar
    </button>
  </header>
  {#if snapshot.error}
    <div class="error" role="alert"><span>{snapshot.error}</span><button type="button" disabled={snapshot.loading} onclick={onRefresh}>Reintentar</button></div>
  {/if}
  {#if snapshot.loading && !snapshot.data}
    <div class="shelves skeleton" role="status" aria-label="Cargando recomendaciones">
      {#each [0, 1] as section}
        <div class="skeleton-shelf"><span class="skeleton-heading"></span><div class="skeleton-columns">
          {#each [0, 1] as column}<div class="song-column">{#each [0, 1, 2] as row}<div class="skeleton-row"><span class="skeleton-art"></span><span class="skeleton-lines"><i></i><i></i></span></div>{/each}</div>{/each}
        </div></div>
      {/each}
    </div>
  {:else if hasData}
    <div class="shelves">
      {#each shelves as shelf (shelf.kind)}
        <section class="shelf" aria-label={shelf.title}>
          <div class="shelf-heading"><h2 title={shelf.title}>{shelf.title}</h2>
            {#if shelf.browseId && ((shelf.kind === 'artist' && onOpenArtist) || (shelf.kind === 'album' && onOpenAlbum))}
              <button type="button" class="browse-link" onclick={() => shelf.kind === 'artist' ? onOpenArtist?.(shelf.browseId!) : onOpenAlbum?.(shelf.browseId!)}>{shelf.kind === 'artist' ? 'Ver artista' : 'Ver álbum'}<span aria-hidden="true">›</span></button>
            {/if}
          </div>
          <div class="song-columns">
            {#each chunks(shelf.songs) as column, columnIndex (columnIndex)}
              <div class="song-column">
                {#each column as song, songIndex (`${song.videoId}:${songIndex}`)}
                  <div class="track-row" class:current={song.videoId === currentTrack?.videoId} role="group" aria-label={`Canción: ${song.title}`} oncontextmenu={(event) => songMenu(event, song)}>
                    <button type="button" class="track-main" aria-label={`Reproducir ${song.title}`} onclick={() => onPlaySong(song)} onkeydown={menu({ kind: 'song', song }, { view: 'recommendations' }).onKeyDown}>
                      <span class="art">
                        {#if song.thumbnail && !failedImages.has(song.thumbnail)}<img src={song.thumbnail} alt="" loading="lazy" onerror={() => imageFailed(song.thumbnail!)} />{:else}<span class="image-placeholder" aria-hidden="true">♫</span>{/if}
                        <span class="play-overlay" aria-hidden="true">
                          {#if song.videoId === currentTrack?.videoId && isPlaying}<svg viewBox="0 0 24 24" fill="currentColor"><path d="M7 5h4v14H7zm6 0h4v14h-4z"/></svg>{:else}<svg viewBox="0 0 24 24" fill="currentColor"><path d="m8 4 13 8-13 8z"/></svg>{/if}
                        </span>
                      </span>
                      <span class="song-title" title={song.title}>{song.title}</span>
                    </button>
                    <span class="metadata"><ArtistCredits artistRuns={song.artistRuns} artists={song.artists} artistId={song.artistId} {onOpenArtist} album={song.album} albumId={song.albumId} {onOpenAlbum} /></span>
                    {#if onPlayNext}<button type="button" class="play-next" aria-label={`Reproducir ${song.title} a continuación`} title="Reproducir a continuación" onclick={() => onPlayNext?.(song)}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M3 5h18M3 10h18M3 15h8M3 20h8"/><path d="m16 14 5 4-5 4z" fill="currentColor" stroke="none"/></svg></button>{/if}
                  </div>
                {/each}
              </div>
            {/each}
          </div>
        </section>
      {/each}
      {#if artists.length}
        <section class="shelf artist-shelf" aria-label="A los fans también les gusta">
          <h2>A los fans también les gusta</h2>
          <div class="artist-cards">
            {#each artists as artist, artistIndex (`${artist.id}:${artistIndex}`)}
              <button type="button" class="artist-card" onclick={() => onOpenArtist?.(artist.id)} disabled={!onOpenArtist} aria-label={`Ver artista: ${artist.title}`} oncontextmenu={(event) => artistMenu(event, artist)} onkeydown={menu(targetFromCard(artist), { view: 'recommendations' }).onKeyDown}>
                <span class="artist-art">{#if artist.thumbnail && !failedImages.has(artist.thumbnail)}<img src={artist.thumbnail} alt="" loading="lazy" onerror={() => imageFailed(artist.thumbnail!)} />{:else}<span class="image-placeholder" aria-hidden="true">♙</span>{/if}<span class="artist-overlay" aria-hidden="true">➜</span></span>
                <span class="artist-name" title={artist.title}>{artist.title}</span>
              </button>
            {/each}
          </div>
        </section>
      {/if}
    </div>
  {:else}
    <div class="empty"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M3 5h10M3 10h10M3 15h8M18 17V4l5-2v5l-5 2"/><ellipse cx="15" cy="18" rx="3" ry="2"/></svg><p>{currentTrack ? 'No hay recomendaciones disponibles' : 'Seleccioná una canción para ver recomendaciones'}</p>{#if currentTrack && !snapshot.error}<button type="button" onclick={onRefresh}>Reintentar</button>{/if}</div>
  {/if}
</section>

<style>
  .recommendations { flex:1; width:100%; min-width:0; min-height:0; height:100%; display:flex; flex-direction:column; gap:10px; color:rgba(255,255,255,.92); }
  header { display:flex; align-items:center; gap:8px; padding:2px 8px 0; flex:none; }
  .heading { display:flex; align-items:center; gap:8px; font-size:13px; font-weight:600; }
  .heading svg { width:13px; height:13px; }
  button { font:inherit; color:inherit; border:0; cursor:pointer; }
  button:disabled { opacity:.45; cursor:default; }
  button:focus-visible { outline:2px solid var(--sideb-highlight,#d06c70); outline-offset:2px; border-radius:6px; }
  .refresh { margin-left:auto; display:flex; align-items:center; gap:5px; background:rgba(255,255,255,.08); border:1px solid rgba(255,255,255,.12); border-radius:999px; padding:4px 10px; font-size:11.5px; font-weight:500; color:rgba(255,255,255,.8); }
  .refresh svg { width:12px; height:12px; }
  .refresh:not(:disabled):hover { background:rgba(255,255,255,.14); color:#fff; }
  .spinning { animation:spin 1s linear infinite; }
  .error { display:flex; gap:8px; align-items:center; padding:6px 8px; color:rgba(255,255,255,.7); font-size:12px; }
  .error button,.empty button { padding:0; background:transparent; color:rgba(255,255,255,.88); font-size:12px; font-weight:600; }
  .error button:hover,.empty button:hover { color:#fff; }
  .shelves { min-height:0; min-width:0; flex:1; overflow-y:auto; overflow-x:hidden; padding:0 4px 24px; overscroll-behavior:contain; scrollbar-width:thin; scrollbar-color:rgba(255,255,255,.25) transparent; }
  .shelf+.shelf { margin-top:22px; }
  .shelf-heading { display:flex; align-items:center; gap:8px; margin-bottom:10px; }
  h2 { min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; margin:0; font-size:14.5px; font-weight:700; color:rgba(255,255,255,.95); }
  .browse-link { flex:none; margin-left:auto; display:flex; gap:3px; align-items:center; background:transparent; padding:0; color:rgba(255,255,255,.75); font-size:11.5px; font-weight:500; }
  .browse-link:hover { color:#fff; }
  .browse-link span { font-size:18px; line-height:14px; }
  .song-columns { display:flex; align-items:flex-start; gap:14px; min-width:0; overflow-x:auto; padding:2px 2px 6px; scrollbar-width:thin; scrollbar-color:rgba(255,255,255,.2) transparent; }
  .song-column { width:270px; flex:none; display:flex; flex-direction:column; gap:6px; }
  .track-row { position:relative; box-sizing:border-box; height:50px; border-radius:8px; background:transparent; }
  .track-row:hover,.track-row:focus-within { background:rgba(255,255,255,.09); }
  .track-row.current { background:var(--sideb-active-row-background,rgba(255,255,255,.12)); box-shadow:inset 0 0 0 1px rgba(255,255,255,.1); }
  .track-main { display:flex; align-items:flex-start; gap:10px; width:100%; height:100%; padding:3px 30px 3px 6px; text-align:left; background:transparent; border-radius:8px; }
  .art { position:relative; width:44px; height:44px; flex:none; border-radius:6px; overflow:hidden; }
  .art img,.image-placeholder { width:100%; height:100%; object-fit:cover; display:grid; place-items:center; background:rgba(255,255,255,.08); color:rgba(255,255,255,.3); font-size:22px; }
  .play-overlay { position:absolute; inset:0; display:grid; place-items:center; opacity:0; background:rgba(0,0,0,.4); }
  .play-overlay svg { width:16px; height:16px; }
  .track-row:hover .play-overlay,.track-row:focus-within .play-overlay,.track-row.current .play-overlay { opacity:1; }
  .song-title { min-width:0; overflow:hidden; white-space:nowrap; text-overflow:ellipsis; font-size:12.5px; line-height:17px; margin-top:3px; font-weight:500; }
  .current .song-title { font-weight:600; }
  .metadata { position:absolute; left:60px; right:30px; bottom:5px; display:block; width:max-content; max-width:calc(100% - 90px); font-size:11px; line-height:16px; color:rgba(255,255,255,.55); }
  .metadata :global(.artist-credits) { display:flex; width:100%; }
  .play-next { position:absolute; right:4px; top:14px; width:22px; height:22px; padding:3px; background:transparent; color:rgba(255,255,255,.7); opacity:0; }
  .play-next svg { display:block; width:16px; height:16px; }
  .track-row:hover .play-next,.track-row:focus-within .play-next { opacity:1; }
  .play-next:hover { color:#fff; }
  .artist-shelf h2 { margin-bottom:12px; }
  .artist-cards { display:flex; gap:16px; overflow-x:auto; padding:2px 2px 6px; scrollbar-width:thin; scrollbar-color:rgba(255,255,255,.2) transparent; }
  .artist-card { flex:none; width:86px; padding:0; display:flex; flex-direction:column; align-items:center; gap:7px; text-align:center; background:transparent; }
  .artist-art { position:relative; width:76px; height:76px; overflow:hidden; border-radius:50%; box-shadow:0 3px 6px rgba(0,0,0,.1); outline:1px solid rgba(255,255,255,.1); }
  .artist-art img { width:100%; height:100%; object-fit:cover; }
  .artist-overlay { position:absolute; inset:0; display:grid; place-items:center; background:rgba(0,0,0,.38); opacity:0; font-size:20px; color:#fff; }
  .artist-card:hover .artist-overlay,.artist-card:focus-visible .artist-overlay { opacity:1; }
  .artist-card:hover .artist-art { outline-color:rgba(255,255,255,.25); }
  .artist-name { color:rgba(255,255,255,.85); font-size:11.5px; font-weight:500; line-height:15px; display:-webkit-box; line-clamp:2; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
  .artist-card:hover .artist-name { color:#fff; }
  .empty { flex:1; min-height:0; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:12px; text-align:center; color:rgba(255,255,255,.6); font-size:14px; }
  .empty svg { width:36px; height:36px; color:rgba(255,255,255,.25); }
  .empty p { margin:0; }
  .skeleton-shelf+.skeleton-shelf { margin-top:20px; }
  .skeleton-heading { display:block; width:140px; height:16px; border-radius:4px; background:rgba(255,255,255,.12); margin-bottom:10px; }
  .skeleton-columns { display:flex; gap:12px; }
  .skeleton-row { display:flex; gap:10px; align-items:center; height:44px; }
  .skeleton-art { width:44px; height:44px; border-radius:6px; background:rgba(255,255,255,.1); }
  .skeleton-lines { display:flex; flex-direction:column; gap:4px; }
  .skeleton-lines i { width:120px; height:12px; border-radius:3px; background:rgba(255,255,255,.12); }
  .skeleton-lines i+i { width:80px; height:10px; background:rgba(255,255,255,.08); }
  @keyframes spin { to { transform:rotate(360deg); } }
  @media (prefers-reduced-motion:reduce) { .spinning { animation:none; } }
</style>

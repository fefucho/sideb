<script lang="ts">
  import { t , language, resolveMessage } from '$lib/i18n';
  import MediaCard from "../common/MediaCard.svelte";
  import { songCard } from "$lib/player/media";
  import type { BrowseCardDto, PlaybackTrackDto, SongDto } from '$lib/types';
  import type { RecommendationsSnapshot } from '$lib/player/recommendations';

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
  const shelves = $derived(snapshot.data ? [
    { title: snapshot.data.artistName ? $t('fullscreen.moreByArtist', [snapshot.data.artistName]) : $t('fullscreen.moreByThisArtist'),
      songs: snapshot.data.artistSongs, browseId: snapshot.data.artistBrowseId, kind: 'artist' },
    { title: snapshot.data.albumTitle ? $t('fullscreen.fromAlbum', [snapshot.data.albumTitle]) : $t('fullscreen.fromSameAlbum'),
      songs: snapshot.data.albumSongs, browseId: snapshot.data.albumBrowseId, kind: 'album' },
    { title: $t('fullscreen.similarSongs'), songs: snapshot.data.similarSongs, browseId: null, kind: 'song' },
  ].filter(shelf => shelf.songs.length) : []);
  const artists = $derived(snapshot.data?.relatedArtists ?? []);
  const hasData = $derived(shelves.length > 0 || artists.length > 0);

  function chunks(songs: SongDto[]) {
    const columns: SongDto[][] = [];
    for (let index = 0; index < songs.length; index += 3) columns.push(songs.slice(index, index + 3));
    return columns;
  }

</script>

<section class="recommendations" aria-label={$t('fullscreen.recommendations')} aria-busy={snapshot.loading}>
  <header>
    <span class="heading"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3Z"/></svg>{$t('fullscreen.recommendations')}</span>
    <button type="button" class="refresh" disabled={snapshot.loading || !currentTrack} onclick={onRefresh} title={$t('windows.ui.getNewRecommendationsForThisTrack')}>
      <svg class:spinning={snapshot.loading} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 8a8 8 0 1 0 1 8M20 3v5h-5"/></svg>{$t('explore.refresh')}
    </button>
  </header>
  {#if snapshot.error}
    <div class="error" role="alert"><span>{resolveMessage(snapshot.error, $language)}</span><button type="button" disabled={snapshot.loading} onclick={onRefresh}>{$t('sidebar.retry')}</button></div>
  {/if}
  {#if snapshot.loading && !snapshot.data}
    <div class="shelves skeleton" role="status" aria-label={$t('windows.ui.loadingRecommendations')}>
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
              <button type="button" class="browse-link" onclick={() => shelf.kind === 'artist' ? onOpenArtist?.(shelf.browseId!) : onOpenAlbum?.(shelf.browseId!)}>{shelf.kind === 'artist' ? $t('menu.view_artist') : $t('menu.view_album')}<span aria-hidden="true">›</span></button>
            {/if}
          </div>
          <div class="song-columns">
            {#each chunks(shelf.songs) as column, columnIndex (columnIndex)}
              <div class="song-column">
                {#each column as song, songIndex (`${song.videoId}:${songIndex}`)}
                  <MediaCard card={songCard(song)} layout="compact" onPlay={()=>onPlaySong(song)} {onOpenArtist} {onOpenAlbum} />
                {/each}
              </div>
            {/each}
          </div>
        </section>
      {/each}
      {#if artists.length}
        <section class="shelf artist-shelf" aria-label={$t('fullscreen.fansAlsoLike')}>
          <h2>{$t('fullscreen.fansAlsoLike')}</h2>
          <div class="artist-cards">
            {#each artists as artist, artistIndex (`${artist.id}:${artistIndex}`)}
              <div class="artist-card"><MediaCard card={{...artist,kind:'artist'}} onOpen={()=>onOpenArtist?.(artist.id)} /></div>
            {/each}
          </div>
        </section>
      {/if}
    </div>
  {:else}
    <div class="empty"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M3 5h10M3 10h10M3 15h8M18 17V4l5-2v5l-5 2"/><ellipse cx="15" cy="18" rx="3" ry="2"/></svg><p>{currentTrack ? $t('fullscreen.noRecommendations') : $t('windows.ui.selectASongToSeeRecommendations')}</p>{#if currentTrack && !snapshot.error}<button type="button" onclick={onRefresh}>{$t('sidebar.retry')}</button>{/if}</div>
  {/if}
</section>

<style>.recommendations { flex:1; width:100%; min-width:0; min-height:0; height:100%; display:flex; flex-direction:column; gap:10px; color:rgba(255,255,255,.92); }header { display:flex; align-items:center; gap:8px; padding:2px 8px 0; flex:none; }.heading { display:flex; align-items:center; gap:8px; font-size:13px; font-weight:600; }.heading svg { width:13px; height:13px; }button { font:inherit; color:inherit; border:0; cursor:pointer; }button:disabled { opacity:.45; cursor:default; }button:focus-visible { outline:2px solid var(--sideb-highlight,#d06c70); outline-offset:2px; border-radius:6px; }.refresh { margin-left:auto; display:flex; align-items:center; gap:5px; background:rgba(255,255,255,.08); border:1px solid rgba(255,255,255,.12); border-radius:999px; padding:4px 10px; font-size:11.5px; font-weight:500; color:rgba(255,255,255,.8); }.refresh svg { width:12px; height:12px; }.refresh:not(:disabled):hover { background:rgba(255,255,255,.14); color:#fff; }.spinning { animation:spin 1s linear infinite; }.error { display:flex; gap:8px; align-items:center; padding:6px 8px; color:rgba(255,255,255,.7); font-size:12px; }.error button, .empty button { padding:0; background:transparent; color:rgba(255,255,255,.88); font-size:12px; font-weight:600; }.error button:hover, .empty button:hover { color:#fff; }.shelves { min-height:0; min-width:0; flex:1; overflow-y:auto; overflow-x:hidden; padding:0 4px 24px; overscroll-behavior:contain; scrollbar-width:thin; scrollbar-color:rgba(255,255,255,.25) transparent; }.shelf+.shelf { margin-top:22px; }.shelf-heading { display:flex; align-items:center; gap:8px; margin-bottom:10px; }h2 { min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; margin:0; font-size:14.5px; font-weight:700; color:rgba(255,255,255,.95); }.browse-link { flex:none; margin-left:auto; display:flex; gap:3px; align-items:center; background:transparent; padding:0; color:rgba(255,255,255,.75); font-size:11.5px; font-weight:500; }.browse-link:hover { color:#fff; }.browse-link span { font-size:18px; line-height:14px; }.song-columns { display:flex; align-items:flex-start; gap:14px; min-width:0; overflow-x:auto; padding:2px 2px 6px; scrollbar-width:thin; scrollbar-color:rgba(255,255,255,.2) transparent; }.song-column { width:270px; flex:none; display:flex; flex-direction:column; gap:6px; }.artist-shelf h2 { margin-bottom:12px; }.artist-cards { display:flex; gap:16px; overflow-x:auto; padding:2px 2px 6px; scrollbar-width:thin; scrollbar-color:rgba(255,255,255,.2) transparent; }.artist-card { flex:none; width:86px; padding:0; display:flex; flex-direction:column; align-items:center; gap:7px; text-align:center; background:transparent; }.empty { flex:1; min-height:0; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:12px; text-align:center; color:rgba(255,255,255,.6); font-size:14px; }.empty svg { width:36px; height:36px; color:rgba(255,255,255,.25); }.empty p { margin:0; }.skeleton-shelf+.skeleton-shelf { margin-top:20px; }.skeleton-heading { display:block; width:140px; height:16px; border-radius:4px; background:rgba(255,255,255,.12); margin-bottom:10px; }.skeleton-columns { display:flex; gap:12px; }.skeleton-row { display:flex; gap:10px; align-items:center; height:44px; }.skeleton-art { width:44px; height:44px; border-radius:6px; background:rgba(255,255,255,.1); }.skeleton-lines { display:flex; flex-direction:column; gap:4px; }.skeleton-lines i { width:120px; height:12px; border-radius:3px; background:rgba(255,255,255,.12); }.skeleton-lines i+i { width:80px; height:10px; background:rgba(255,255,255,.08); }
  @keyframes spin {to { transform:rotate(360deg); } }
  @media (prefers-reduced-motion:reduce) {.spinning { animation:none; } }
</style>

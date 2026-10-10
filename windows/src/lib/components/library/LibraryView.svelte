<script lang="ts">
  import { t , language, resolveMessage } from '$lib/i18n';
  import type { BrowseCardDto } from "$lib/types";
  import type { AccountSongDto as SongDto } from "$lib/account/types";
  import VirtualCatalog from '../explore/VirtualCatalog.svelte';
  import MediaCard from '../common/MediaCard.svelte';
  import AccountTrackTable from "./AccountTrackTable.svelte";
  import ContinuationLoader from "../detail/ContinuationLoader.svelte";

  type LibraryTab = "songs" | "playlists" | "albums" | "artists";
  interface Props {
    loggedIn: boolean; tab: LibraryTab; songs: SongDto[];
    playlists: BrowseCardDto[]; albums: BrowseCardDto[]; artists: BrowseCardDto[];
    loading: boolean; loadingMore: boolean; error: string | null; continuation: string | null;
    currentTrackId: string | null; isPlaying: boolean; likedIds: Set<string>; pendingIds: Set<string>;
    onTab: (tab: LibraryTab) => void; onRefresh: () => void; onLoadMore: () => void;
    onPlay: (index: number) => void; onOpenCard: (card: BrowseCardDto) => void;
    onOpenArtist?: (id: string) => void; onOpenAlbum?: (id: string) => void;
    onToggleLike: (track: SongDto) => void; onToggleSaved: (track: SongDto) => void;
    onCreatePlaylist: () => void; onLogin: () => void;
  }
  let {
    loggedIn, tab, songs, playlists, albums, artists, loading, loadingMore, error, continuation,
    currentTrackId, isPlaying, likedIds, pendingIds, onTab, onRefresh, onLoadMore, onPlay,
    onOpenCard, onOpenArtist, onOpenAlbum, onToggleLike, onToggleSaved, onCreatePlaylist, onLogin,
  }: Props = $props();

  const tabs = $derived<{ id: LibraryTab; label: string }[]>([
    { id: "songs", label: $t('search.filter.songs') }, { id: "playlists", label: $t('windows.ui.playlists') },
    { id: "albums", label: $t('sidebar.albums') }, { id: "artists", label: $t('search.filter.artists') },
  ]);
  const cards = $derived(tab === "playlists" ? playlists : tab === "albums" ? albums : artists);
  const icon = $derived(tab === "playlists" ? "♫" : tab === "albums" ? "◉" : "♙");
  const emptyTitle = $derived(tab === "playlists" ? $t('library.empty.playlists') : tab === "albums" ? $t('sidebar.no_saved_albums') : $t('library.empty.artists'));
  const heading = $derived(tab === "playlists" ? $t('windows.ui.playlists') : tab === "albums" ? $t('sidebar.albums') : $t('search.filter.artists'));

</script>

<main class="library" aria-busy={loading}>
  <header class="heading">
    <div><div class="eyebrow">{$t('detail.kind.collection')}</div><h1>{$t('sidebar.library')}</h1></div>
    <div class="heading-actions">
      {#if loggedIn}<button class="new-playlist" type="button" onclick={onCreatePlaylist}>＋ <span>{$t('detail.playlistEditor.createTitle')}</span></button>{/if}
    </div>
  </header>

  <nav class="tabs" aria-label={$t('windows.ui.librarySections')}>
    {#each tabs as item (item.id)}<button type="button" aria-pressed={tab === item.id} class:selected={tab === item.id} onclick={() => onTab(item.id)}>{item.label}</button>{/each}
    {#if loggedIn}<button class="refresh" type="button" aria-label={$t('library.refresh')} title={$t('library.refresh')} onclick={onRefresh}>↻</button>{/if}
  </nav>
  <div class="divider"></div>

  {#if !loggedIn}
    <section class="state"><div class="state-icon" aria-hidden="true">♙</div><h2>{$t('library.login_required')}</h2><button class="primary" type="button" onclick={onLogin}>{$t('account.sign_in')}</button></section>
  {:else if tab === "songs"}
    {#if loading && songs.length === 0}<section class="state" role="status"><span class="spinner"></span><p>{$t('windows.ui.loadingSongs')}</p></section>
    {:else if error && songs.length === 0}<section class="state" role="alert"><h2>{$t('library.error.load_songs')}</h2><p>{resolveMessage(error, $language)}</p><button class="primary" type="button" onclick={onRefresh}>{$t('sidebar.retry')}</button></section>
    {:else if songs.length === 0}<section class="state"><div class="state-icon" aria-hidden="true">♫</div><h2>{$t('library.empty.songs')}</h2></section>
    {:else}
      <AccountTrackTable items={songs} {currentTrackId} {isPlaying} onPlay={onPlay} {likedIds} {pendingIds} {onToggleLike} {onToggleSaved} {onOpenArtist} {onOpenAlbum} />
      {#if error}<div class="inline-error" role="alert">{$t('windows.error.update', [resolveMessage(error, $language)])}<button type="button" onclick={onRefresh}>{$t('sidebar.retry')}</button></div>{/if}
    {/if}
  {:else if loading && cards.length === 0}<section class="state" role="status"><span class="spinner"></span><p>{$t('common.loading')} {heading.toLocaleLowerCase()}…</p></section>
  {:else if error && cards.length === 0}<section class="state" role="alert"><h2>{$t('library.error.load')}</h2><p>{resolveMessage(error, $language)}</p><button class="primary" type="button" onclick={onRefresh}>{$t('sidebar.retry')}</button></section>
  {:else if cards.length === 0}<section class="state"><div class="state-icon" aria-hidden="true">{icon}</div><h2>{emptyTitle}</h2></section>
  {:else}
    <section class="card-content" aria-label={heading}>
      {#if loading}<div class="updating" role="status">{$t('windows.ui.refreshing')}</div>{/if}
      {#if error}<div class="inline-error" role="alert">{$t('windows.error.update', [resolveMessage(error, $language)])}<button type="button" onclick={onRefresh}>{$t('sidebar.retry')}</button></div>{/if}
      <div class="grid">
      <VirtualCatalog items={cards} scrollSelector=".content-column">
        {#snippet children(card)}
          <MediaCard card={{...card,kind:tab==='artists'?'artist':tab==='albums'?'album':'playlist'}} onOpen={()=>onOpenCard(card)} {onOpenArtist} {onOpenAlbum} />
        {/snippet}
      </VirtualCatalog>
      </div>
    </section>
  {/if}

  {#if loggedIn}
    <ContinuationLoader context={`library:${tab}`} cursor={continuation} loading={loadingMore} disabled={loading} error={error} {onLoadMore} />
    <div class="bottom-space" aria-hidden="true"></div>
  {/if}
</main>

<style>
  .library { position: relative; box-sizing: border-box; min-width: 0; min-height: 100%; color: #f7f7f8; background: var(--sideb-background, #1b1b1e); }
  .heading { display: flex; align-items: flex-end; justify-content: space-between; gap: 16px; padding: 24px 142px 18px 32px; }
  .eyebrow { margin-bottom: 4px; color: #aaaab1; font-size: 11px; font-weight: 700; letter-spacing: 1.2px; }
  h1 { margin: 0; font-size: 32px; font-weight: 700; line-height: 1.15; }
  .heading-actions { display: flex; align-items: center; gap: 12px; }
  .new-playlist, .refresh { border: 1px solid var(--sideb-surface-border); border-radius: 999px; color: #f6f6f7; background: var(--sideb-surface); font: inherit; cursor: pointer; }
  .new-playlist { padding: 8px 14px; font-size: 13px; font-weight: 600; } .new-playlist:hover, .refresh:hover { background: var(--sideb-surface-hover); }
  .refresh { width: 34px; height: 34px; font-size: 21px; line-height: 1; }
  .tabs { display: flex; align-items: center; gap: 8px; padding: 0 32px 14px; }
  .tabs button { padding: 8px 15px; border: 0; border-radius: 999px; color: #e7e7eb; background: var(--sideb-surface); font: inherit; font-size: 13px; font-weight: 600; cursor: pointer; }
  .tabs button:hover { background: var(--sideb-surface-hover); }.tabs button.selected { color: white; background: var(--sideb-accent); }
  .tabs .refresh { margin-left: auto; }
  .divider { height: 1px; margin: 0 32px 8px; background: rgb(255 255 255 / 9%); }
  .state { display: flex; min-height: 320px; flex-direction: column; align-items: center; justify-content: center; gap: 12px; padding: 24px; color: #b9b9c0; text-align: center; }
  .state h2 { margin: 0; color: #f3f3f5; font-size: 17px; }.state p { max-width: 50ch; margin: 0; font-size: 13px; }
  .state-icon { color: #c8c8ce; font-size: 38px; }.spinner { width: 22px; height: 22px; border: 2px solid #ffffff30; border-top-color: var(--sideb-highlight); border-radius: 50%; animation: spin .8s linear infinite; }
  .primary { padding: 8px 15px; border: 0; border-radius: 999px; color: white; background: var(--sideb-accent); font: inherit; font-size: 13px; cursor: pointer; }
  .primary:disabled { opacity: .55; cursor: wait; }
  .card-content { position: relative; }.updating { padding: 8px 32px 0; color: #aaaab1; font-size: 11px; }
  .grid { display: block; padding: 20px 32px 0; }
  .inline-error { display: flex; align-items: center; gap: 10px; margin: 8px 32px; padding: 8px 12px; border-radius: 7px; color: #ffd5d5; background: #9d303033; font-size: 12px; }.inline-error button { margin-left: auto; border: 0; color: inherit; background: transparent; font: inherit; text-decoration: underline; cursor: pointer; }
  .bottom-space { height: 130px; }
  button:focus-visible { outline: 2px solid var(--sideb-highlight); outline-offset: 3px; }
  @keyframes spin { to { transform: rotate(360deg); } }
  @media (max-width: 640px) { .heading { padding-inline: 20px; }.tabs { overflow-x: auto; padding-inline: 20px; }.divider { margin-inline: 20px; }.grid { padding-inline: 20px; } }
  @media (prefers-reduced-motion: reduce) { .spinner { animation: none; } }
</style>

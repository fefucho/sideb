<script lang="ts" module>
  const presentations = new Map<string, {query:string;order:TrackOrder}>();
</script>
<script lang="ts">
  import ControlButton from '$lib/components/common/ControlButton.svelte';
  import MenuIcon from '$lib/components/menu/MenuIcon.svelte';

  import { untrack } from 'svelte';
  import { t, language, count, resolveMessage  } from '$lib/i18n';
  import MoreIcon from '$lib/components/common/MoreIcon.svelte';
  import type { AccountPlaylistDto as PlaylistDetailDto, AccountSongDto as SongDto } from "$lib/account/types";
  import AccountTrackTable from "../library/AccountTrackTable.svelte";
  import DescriptionModal from "./DescriptionModal.svelte";
  import ContinuationLoader from './ContinuationLoader.svelte';
  import TrackFilter from './TrackFilter.svelte';
  import CollectionHeader from './CollectionHeader.svelte';
  import { projectTracks, canReorderPlaylist, type TrackOrder } from '$lib/detail/projection';

  type PlaylistViewDto = PlaylistDetailDto & {
    subtitle?: string | null;
    description?: string | null;
    inLibrary?: boolean;
    owned?: boolean;
  };
  type MenuEvent = MouseEvent | KeyboardEvent;

  interface Props {
    session?: string;
    playlist: PlaylistViewDto | null; loading: boolean; loadingMore: boolean; error: string | null;
    loggedIn: boolean; currentTrackId: string | null; isPlaying: boolean; likedIds: Set<string>; pendingIds: Set<string>;
    onRetry: () => void; onLoadMore: () => void; onPlay: (index: number, shuffle?: boolean, order?: TrackOrder) => void;
    onComplete: () => Promise<void>;
    onToggleLike: (track: SongDto) => void; onToggleSaved: (track: SongDto) => void;
    onToggleLibrary: () => Promise<void>; onOpenArtist: (id: string) => void; onOpenAlbum: (id: string) => void;
    onLogin: () => void;
    onOpenMenu?: (event: MenuEvent) => void;
    onTrackMenu?: (event: MenuEvent, track: SongDto) => void;
    onRemoveTrack?: (track: SongDto) => void;
    onMoveTrack?: (setVideoId: string, successorSetVideoId: string | null) => void;
    onSortChange?: (sort: string) => Promise<void>;
    mutationPending?: boolean;
  }
  let {
    session = 'guest', playlist, loading, loadingMore, error, loggedIn, currentTrackId, isPlaying, likedIds, pendingIds,
    onRetry, onLoadMore, onPlay, onToggleLike, onToggleSaved, onToggleLibrary, onOpenArtist, onOpenAlbum, onLogin,
    onOpenMenu, onTrackMenu, onRemoveTrack, onMoveTrack, onComplete, mutationPending = false,
  }: Props = $props();
  let showDescription = $state(false);
  let failedArtwork = $state(false);
  let saving = $state(false);
  let actionError = $state<string | null>(null);
  let query = $state(''); let order = $state<TrackOrder>('custom');
  $effect(()=>{
    const key = playlist?.id ? `${session}|${playlist.id.replace(/^VL/, '')}` : null;
    if (!key) return;
    untrack(()=>{ const saved=presentations.get(key); query=saved?.query??''; order=saved?.order??'custom'; });
    return ()=>{ presentations.delete(key); presentations.set(key,{query,order}); while(presentations.size>20)presentations.delete(presentations.keys().next().value!); };
  });
  let completeRequest = '';
  const projection = $derived(projectTracks(playlist?.items ?? [], query, order));
  const ordered = $derived(projectTracks(playlist?.items ?? [], '', order));
  const orderedPositions = $derived(new Map(ordered.map((entry,index)=>[entry.sourceIndex,index])));
  const reorder = $derived(!!playlist && canReorderPlaylist(playlist.items, playlist.continuation, !!playlist.owned, order, query, mutationPending || loading || loadingMore) && (playlist.sort ?? 'default') === 'default');
  $effect(()=>{const key=`${playlist?.id}:${order}`; if(order!=='custom'&&playlist?.continuation&&key!==completeRequest){completeRequest=key;void onComplete().catch(()=>{});}});
  const canSavePlaylist = $derived(Boolean(playlist && loggedIn && playlist.id !== "LM" && !playlist.owned));
  const artworkIdentity = $derived(JSON.stringify([playlist?.id, playlist?.thumbnail]));

  $effect(() => { artworkIdentity; failedArtwork = false; showDescription = false; actionError = null; });

  async function toggleLibrary() {
    if (!canSavePlaylist || saving) return;
    saving = true;
    actionError = null;
    try { await onToggleLibrary(); }
    catch (cause) { actionError = cause instanceof Error ? cause.message : String(cause); }
    finally { saving = false; }
  }
</script>

<main class="playlist-page" aria-busy={loading}>
  {#if loading && playlist}<div class="topline"><span class="updating" role="status">{$t('windows.ui.refreshingPlaylist')}</span></div>{/if}
  {#if loading && !playlist}
    <div class="skeleton" role="status" aria-label={$t('windows.ui.loadingPlaylist')}><div class="sk-art"></div><div class="sk-info"><i></i><i></i><i></i></div></div>
  {:else if !playlist && error}
    <section class="state" role="alert"><div class="state-icon">!</div><h2>{$t('windows.ui.couldnTLoadThePlaylist')}</h2><p>{resolveMessage(error, $language)}</p><ControlButton emphasis="prominent" type="button" onclick={onRetry}>{$t('sidebar.retry')}</ControlButton></section>
  {:else if !playlist && !loggedIn}
    <section class="state"><div class="state-icon">♙</div><h2>{$t('windows.ui.signInToOpenThisPlaylist')}</h2><ControlButton emphasis="prominent" type="button" onclick={onLogin}>{$t('account.sign_in')}</ControlButton></section>
  {:else if !playlist}
    <section class="state"><div class="state-icon">♫</div><h2>{$t('windows.ui.playlistUnavailable')}</h2><p>{$t('windows.ui.goBackOrTryLoadingItAgain')}</p><ControlButton emphasis="prominent" type="button" onclick={onRetry}>{$t('sidebar.retry')}</ControlButton></section>
  {:else}
    <div class="scroll-content">
      <CollectionHeader identity={playlist.id} title={playlist.title} thumbnail={playlist.thumbnail} kind={playlist.id === 'LM' ? $t('detail.kind.collection') : $t('detail.kind.playlist')} summary={playlist.continuation ? $t('windows.collection.partialCount', [playlist.items.length]) : count('common.songCount', playlist.items.length, $language)} description={playlist.description} onDescription={() => showDescription = true}>
        {#snippet credit()}{#if playlist.subtitle}<span>{playlist.subtitle}</span>{/if}{/snippet}
        {#snippet actions()}
            <ControlButton data-action="play" emphasis="prominent" type="button" disabled={!playlist.items.length || loadingMore || order!=='custom'&&!!playlist.continuation} onclick={() => onPlay(ordered[0]?.sourceIndex ?? 0, false, order)}><MenuIcon name="play" /><span>{$t('player.play')}</span></ControlButton>
            <ControlButton type="button" disabled={!playlist.items.length} onclick={() => onPlay(0, true, order)}><MenuIcon name="shuffle" /><span>{$t('player.shuffle')}</span></ControlButton>
            {#if canSavePlaylist}<ControlButton selected={Boolean(playlist.inLibrary)} loading={saving} loadingFeedback="subtle" type="button" aria-pressed={Boolean(playlist.inLibrary)} onclick={toggleLibrary}><MenuIcon name={playlist.inLibrary ? 'bookmark-fill' : 'bookmark'} />{playlist.inLibrary ? $t('detail.collection.inLibrary') : $t('detail.collection.save')}</ControlButton>{/if}
            {#if onOpenMenu}<ControlButton iconOnly type="button" aria-label={$t('windows.playlist.moreOptions')} title={$t('menu.more_options')} onclick={onOpenMenu} oncontextmenu={(event) => { event.preventDefault(); onOpenMenu?.(event); }} onkeydown={(event) => { if (event.key === 'ContextMenu' || event.shiftKey && event.key === 'F10') { event.preventDefault(); onOpenMenu?.(event); } }}><MoreIcon /></ControlButton>{/if}
{/snippet}
        {#snippet tools()}{#if playlist.items.length}<TrackFilter bind:query bind:order busy={loadingMore||mutationPending} compact />{/if}{/snippet}
      </CollectionHeader>
      {#if actionError}<div class="inline-error" role="alert">{resolveMessage(actionError, $language)}</div>{/if}
      {#if error && playlist}<div class="inline-error" role="alert">{$t('windows.error.update', [resolveMessage(error, $language)])}<ControlButton onclick={onRetry}>{$t('sidebar.retry')}</ControlButton></div>{/if}
      {#if playlist.items.length}
        {#if playlist.continuation && (order!=='custom'||playlist.owned)}<ControlButton loading={loadingMore} disabled={mutationPending} onclick={()=>onComplete().catch(()=>{})}>{$t('windows.ui.loadTheFullCollectionToSortOrMoveSongs')}</ControlButton>{/if}
        <AccountTrackTable items={projection.map(entry=>entry.track)} occurrenceIndices={projection.map(entry=>orderedPositions.get(entry.sourceIndex) ?? entry.sourceIndex)} occurrenceKeys={projection.map(entry=>entry.key)} source={{kind:'playlist',id:playlist.id}} detail {currentTrackId} {isPlaying} onPlay={(index) => onPlay(projection[index].sourceIndex, false, order)} onOpenArtist={onOpenArtist} onOpenAlbum={onOpenAlbum} {likedIds} {pendingIds} onToggleLike={loggedIn ? onToggleLike : undefined} onToggleSaved={loggedIn ? onToggleSaved : undefined} onContextMenu={onTrackMenu} onRemoveTrack={playlist.owned ? onRemoveTrack : undefined} onMoveTrack={reorder ? onMoveTrack : undefined} canReorder={reorder} {mutationPending} />
        {#if !projection.length}<p class="no-tracks">{$t('windows.ui.noSongsMatchYourSearch')}</p>{/if}
      {:else if loadingMore}<div class="loading-inline" role="status">{$t('windows.ui.loadingSongs')}</div>
      {:else}<p class="no-tracks">{$t('windows.ui.thisPlaylistHasNoSongsAvailableYet')}</p>{/if}
      <ContinuationLoader context={`playlist:${playlist.id}`} cursor={playlist.continuation} loading={loadingMore} disabled={loading || mutationPending} error={error} {onLoadMore} />
      <div class="bottom-space" aria-hidden="true"></div>
    </div>
  {/if}
  {#if showDescription && playlist?.description}<DescriptionModal title={playlist.title} description={playlist.description} onClose={() => showDescription = false} />{/if}
</main>

<style>

.topline {display:flex;align-items:center;justify-content:space-between;min-height:38px;padding:0 20px;}
   .updating {font-size:11px;color:#aaaab1;}


.inline-error {display:flex;gap:10px;margin:0 32px 8px;padding:8px 12px;border-radius:7px;background:#9d303033;color:#ffd5d5;font-size:12px;}

.no-tracks,.loading-inline {padding:20px 32px;color:#aaaab1;font-size:13px;} .bottom-space {height:130px;}
.state {display:flex;min-height:320px;flex-direction:column;align-items:center;justify-content:center;gap:12px;padding:24px;text-align:center;color:#aaaab1;} .state h2 {margin:0;font-size:18px;color:#f7f7f8;} .state p {font-size:13px;} .state-icon {font-size:34px;}
.skeleton {display:flex;gap:24px;padding:28px 32px;} .sk-art {width:216px;height:216px;border-radius:8px;background:#ffffff12;}.sk-info {display:flex;flex-direction:column;gap:14px;}.sk-info i {width:260px;height:15px;border-radius:5px;background:#ffffff12;}
</style>

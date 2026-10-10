<script lang="ts">
  import { t , language, resolveMessage } from '$lib/i18n';
  import type { HistoryGroupDto, AccountSongDto } from '$lib/account/types';
  import { normalizeHistoryDate } from '../common/trackList';
  import VirtualStack from '../common/VirtualStack.svelte';
  import AccountTrackTable from './AccountTrackTable.svelte';
  interface Props {
    loggedIn: boolean; groups: HistoryGroupDto[]; loading: boolean; error: string | null;
    currentTrackId: string | null; isPlaying: boolean; likedIds: Set<string>; pendingIds: Set<string>;
    onLogin: () => void; onRefresh: () => void; onPlay: (items: AccountSongDto[], index: number) => void;
    onToggleLike: (song: AccountSongDto) => void; onToggleSaved: (song: AccountSongDto) => void;
    onOpenArtist: (id: string) => void; onOpenAlbum: (id: string) => void;
  }
  let { loggedIn, groups, loading, error, currentTrackId, isPlaying, likedIds, pendingIds,
    onLogin, onRefresh, onPlay, onToggleLike, onToggleSaved, onOpenArtist, onOpenAlbum }: Props = $props();
  const allTracks = $derived(groups.flatMap(group => group.items));
</script>
<section class="history" aria-busy={loading}>
  <header><div><div class="eyebrow">{$t('detail.kind.collection')}</div><h1>{$t('sidebar.history')}</h1><p>{$t('history.subtitle')}</p></div>
    {#if loggedIn}<button type="button" onclick={onRefresh} disabled={loading} aria-label={$t('windows.ui.refreshHistory')}>↻</button>{/if}
  </header>
  <div class="divider"></div>
  {#if !loggedIn}<div class="state"><h2>{$t('windows.ui.signInToSeeYourHistory')}</h2><button type="button" onclick={onLogin}>{$t('account.sign_in')}</button></div>
  {:else if loading && !allTracks.length}<div class="state" role="status">{$t('windows.ui.loadingHistory')}</div>
  {:else if error && !allTracks.length}<div class="state" role="alert"><h2>{$t('history.error.load')}</h2><p>{resolveMessage(error, $language)}</p><button type="button" onclick={onRefresh}>{$t('sidebar.retry')}</button></div>
  {:else if !allTracks.length}<div class="state"><h2>{$t('history.empty')}</h2></div>
  {:else}
    {#if error}<p class="error" role="alert">{resolveMessage(error, $language)}</p>{/if}
    <VirtualStack items={groups.map((group,index)=>({...group,index,offset:groups.slice(0,index).reduce((sum,g)=>sum+g.items.length,0)}))} key={group=>`${group.title}:${group.index}`} height={group=>group.items.length*52+48}>
      {#snippet children(group)}
      {@const offset = group.offset}
      <section aria-label={normalizeHistoryDate(group.title)}><h2 class="group-heading">{normalizeHistoryDate(group.title)}</h2>
        <AccountTrackTable items={group.items} source={{kind:"history",id:"history"}} indexOffset={offset} {currentTrackId} {isPlaying} {likedIds} {pendingIds} numbered
          onPlay={(index) => onPlay(allTracks, offset + index)} {onToggleLike} {onToggleSaved} {onOpenArtist} {onOpenAlbum} />
      </section>
      {/snippet}
    </VirtualStack>
  {/if}
</section>
<style>
  .history { min-width: 0; padding-bottom: 130px; color: #f7f7f8; }
  header { display: flex; align-items: center; justify-content: space-between; padding: 24px 32px 14px; }
  .eyebrow { font-size: 11px; font-weight: 700; letter-spacing: 1.2px; color: #aaaab1; }
  h1 { margin: 4px 0 0; font-size: 32px; } header p { margin: 6px 0 0; font-size: 13px; color: #aaaab1; }
  .divider { height: 1px; background: #ffffff15; margin: 0 32px 8px; }
  button { border: 0; border-radius: 8px; padding: 8px 14px; color: inherit; background: var(--sideb-surface); font: inherit; cursor: pointer; }
  button:hover { background: var(--sideb-surface-hover); } button:focus-visible { outline: 2px solid var(--sideb-highlight); }
  .state { min-height: 300px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 14px; color: #aaaab1; }
  .state h2 { font-size: 17px; } .group-heading { margin: 20px 32px 8px; font-size: 15px; } .error { margin: 14px 32px; color: #ffd5d5; }
</style>

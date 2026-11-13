<script lang="ts">
  // Drives the Jam UI from a writable store and records every action, so tests and screenshots never need a real Jam.
  import { onMount } from 'svelte';
  import type { Writable } from 'svelte/store';
  import type { JamActions, JamViewState } from '$lib/jam/types';
  import { provideJamUi } from '$lib/components/jam/context';
  import ConnectionsButton from '$lib/components/jam/ConnectionsButton.svelte';
  import JamPanel from '$lib/components/jam/JamPanel.svelte';
  import JamBadge from '$lib/components/jam/JamBadge.svelte';
  import JamToasts from '$lib/components/jam/JamToasts.svelte';
  import JamExitDialog from '$lib/components/jam/JamExitDialog.svelte';
  import JamQueueList from '$lib/components/jam/JamQueueList.svelte';
  import JamDebugPanel from '$lib/components/jam/JamDebugPanel.svelte';
  import SidebarUpcomingQueue from '$lib/components/playback-sidebar/SidebarUpcomingQueue.svelte';
  import type { PlaybackStateDto, SongDto } from '$lib/types';

  interface Props {
    store: Writable<JamViewState>;
    actions: JamActions;
    searchSongs: (query: string) => Promise<SongDto[]>;
    mode: 'panel' | 'connections' | 'toasts' | 'queue' | 'badge' | 'debug' | 'upcoming';
    playback?: PlaybackStateDto;
    calls?: unknown[][];
    toastDuration?: number;
    variant?: 'popover' | 'fullscreen';
  }
  let { store, actions, searchSongs, mode, playback, calls = [], toastDuration = 4500, variant = 'popover' }: Props = $props();
  provideJamUi({ state: store, actions, searchSongs });
</script>

{#if mode === 'panel'}<JamPanel state={$store} {actions} {searchSongs} {variant} />
{:else if mode === 'connections'}<ConnectionsButton />
{:else if mode === 'toasts'}<JamToasts toasts={$store.toasts} onDismiss={id => actions.dismissToast(id)} duration={toastDuration} /><JamExitDialog pending={$store.pendingExit} {actions} />
{:else if mode === 'queue' && playback}<JamQueueList {playback} onSelectQueue={index => calls.push(['select', index])} onTogglePlayback={() => calls.push(['toggle'])} onQueueContextMenu={(event, entry) => calls.push(['menu', entry.entryId])} />
{:else if mode === 'badge'}<JamBadge state={$store} onTap={() => calls.push(['badge'])} />
{:else if mode === 'debug'}<JamDebugPanel state={$store} {actions} />
{:else if mode === 'upcoming' && playback}<SidebarUpcomingQueue session={0} {playback} onSelectQueue={index => calls.push(['select', index])} />{/if}

<script lang="ts">
  import { t, language } from '$lib/i18n';
  import PlayerIcon from '$lib/components/player/PlayerIcon.svelte';
  import JamAvatar from './JamAvatar.svelte';
  import JamFlyout from './JamFlyout.svelte';
  import JamPanel from './JamPanel.svelte';
  import { useJamUi } from './context';
  import { connectionsInviteTooltip, hostNameOf, hostOf, isJamLive } from './view';
  import { readable } from 'svelte/store';
  import { emptyJamState } from '$lib/jam/types';

  /**
   * "Conexiones" button of the player bar. Windows has no AirPlay, so its flyout only offers the Spotify Jam.
   * The icon fills and a small host avatar badges its corner while a Jam is live; an accent dot appears when invites are waiting.
   */
  let { class: className = '' }: { class?: string } = $props();
  const ui = useJamUi();
  const jamState = ui?.state ?? readable(emptyJamState());
  let open = $state(false);
  let button = $state<HTMLButtonElement>();

  const live = $derived(isJamLive($jamState));
  const hasInvites = $derived(!live && $jamState.invites.length > 0);
  const host = $derived(hostOf($jamState));
  const hostName = $derived(hostNameOf($jamState));
  const label = $derived(
    live
      ? (hostName ? $t('connections.activeJam', [hostName]) : $t('connections.activeJamUnknownHost'))
      : hasInvites
        ? connectionsInviteTooltip($jamState.invites, $language)
        : $t('connections.title')
  );
  const tooltip = $derived(
    live && hostName
      ? $t('connections.activeJam', [hostName])
      : hasInvites
        ? connectionsInviteTooltip($jamState.invites, $language)
        : $t('connections.help')
  );
  // The Jam can end while the flyout is open (the host closes it): nothing to close then, the panel just changes stage.
</script>

{#if ui}
  <button bind:this={button} type="button" class={`connections-button ${className}`} class:live class:open data-connections aria-haspopup="dialog" aria-expanded={open} aria-controls="jam-connections-flyout"
    aria-label={label} title={tooltip} onclick={() => open = !open}>
    <PlayerIcon name={live ? 'connections-live' : 'connections'} size={19} />
    {#if live}<span class="host-badge" data-host-badge aria-hidden="true"><JamAvatar name={host?.name} imageUrl={host?.imageUrl ?? null} size={9} /></span>
    {:else if hasInvites}<span class="invite-badge" data-invite-badge aria-hidden="true"></span>{/if}
  </button>
  <JamFlyout anchor={button} {open} onClose={() => open = false} label={$t('connections.title')} id="jam-connections-flyout" placement="above">
    <JamPanel state={$jamState} actions={ui.actions} searchSongs={ui.searchSongs} />
  </JamFlyout>
{/if}

<style>
  .connections-button { position: relative; display: grid; flex: 0 0 32px; place-items: center; width: 32px; height: 32px; padding: 0; border: 0; border-radius: 50%; color: rgb(255 255 255 / 65%); background: transparent; cursor: pointer; transition: color 140ms ease, background-color 140ms ease; }
  .connections-button:hover, .connections-button.open { color: #fff; background: rgb(255 255 255 / 10%); }
  .connections-button:active { background-color: rgb(255 255 255 / 6%); }
  .connections-button.live { color: var(--sideb-highlight, #d06c70); }
  .connections-button:focus-visible { outline: 2px solid var(--sideb-highlight, #d06c70); outline-offset: 3px; }
  /* A notification dot ringed in the bar colour, on the bottom-right corner of the glyph. */
  .host-badge { position: absolute; right: 3px; bottom: 3px; display: grid; place-items: center; padding: 1.5px; border-radius: 50%; background: #29292f; }
  .invite-badge { position: absolute; right: 5px; bottom: 5px; width: 7px; height: 7px; border-radius: 50%; background: var(--sideb-highlight, #d06c70); box-shadow: 0 0 0 1.5px #29292f; }
  @media (prefers-reduced-motion: reduce) { .connections-button { transition: none; } }
  @media (forced-colors: active) { .connections-button.live { color: Highlight; } .invite-badge { background: Highlight; } }
</style>

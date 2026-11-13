<script lang="ts">
  import ControlButton from '$lib/components/common/ControlButton.svelte';
  import { t, language } from '$lib/i18n';
  import type { JamInvite } from '$lib/jam/types';
  import JamAvatar from './JamAvatar.svelte';
  import { inviteBannerTitle } from './view';

  /** Floating live Spotify Jam invitation banner: top-right acrylic surface with Join and Dismiss. */
  let {
    invite,
    onJoin,
    onDismiss
  }: {
    invite: JamInvite | null;
    onJoin: (invite: JamInvite) => void;
    onDismiss: (id: string) => void;
  } = $props();
</script>

{#if invite}
  {@const title = inviteBannerTitle(invite, $language)}
  <div class="invite-banner-host" data-jam-invite-banner role="region" aria-label={$t('jam.invites.section')}>
    <div class="invite-banner" role="status" data-invite-id={invite.id}>
      <JamAvatar name={invite.senderName} imageUrl={invite.senderImageUrl} size={36} ring="rgb(255 255 255 / 14%)" />
      <div class="copy">
        <b data-invite-title>{title}</b>
        <span data-invite-subtitle>{$t('jam.invite.banner.subtitle')}</span>
      </div>
      <div class="actions">
        <ControlButton
          size="utility"
          emphasis="prominent"
          data-invite-join
          aria-label={`${$t('jam.invite.join')}, ${title}`}
          onclick={() => onJoin(invite)}
        >
          {$t('jam.invite.join')}
        </ControlButton>
        <button
          type="button"
          class="dismiss"
          data-invite-dismiss
          aria-label={`${$t('jam.invite.dismiss')}, ${title}`}
          onclick={() => onDismiss(invite.id)}
        >
          {$t('jam.invite.dismiss')}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .invite-banner-host {
    position: fixed;
    z-index: 855;
    top: 48px;
    right: 16px;
    max-width: min(440px, calc(100vw - 32px));
    pointer-events: none;
  }
  .invite-banner {
    display: flex;
    align-items: center;
    gap: 12px;
    box-sizing: border-box;
    max-width: 100%;
    padding: 10px 12px 10px 14px;
    border: .75px solid var(--sideb-acrylic-border, rgb(255 255 255 / 20%));
    border-radius: 16px;
    color: #fff;
    background: var(--sideb-acrylic-fallback, #353538);
    box-shadow: 0 4px 12px rgb(0 0 0 / 25%), 0 10px 28px rgb(0 0 0 / 28%);
    pointer-events: auto;
    animation: invite-in 200ms ease-out;
  }
  @keyframes invite-in { from { opacity: 0; transform: translateY(-10px); } }
  @media (prefers-reduced-motion: reduce) { .invite-banner { animation: none; } }
  @supports ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
    .invite-banner {
      background: color-mix(in srgb, #000 45%, var(--sideb-acrylic-surface, rgb(43 43 49 / 78%)));
      backdrop-filter: var(--sideb-acrylic-blur);
      -webkit-backdrop-filter: var(--sideb-acrylic-blur);
    }
  }
  .copy {
    display: flex;
    flex: 1;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  .copy b {
    display: -webkit-box;
    overflow: hidden;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    font-size: 13px;
    font-weight: 600;
    line-height: 1.3;
  }
  .copy span {
    overflow: hidden;
    color: rgb(255 255 255 / 72%);
    font-size: 11.5px;
    line-height: 1.3;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .actions {
    display: flex;
    flex: none;
    align-items: center;
    gap: 6px;
  }
  .dismiss {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    height: 28px;
    padding: 0 10px;
    border: .5px solid rgb(255 255 255 / 12%);
    border-radius: 999px;
    color: rgb(255 255 255 / 82%);
    background: rgb(255 255 255 / 9%);
    font: inherit;
    font-size: 12px;
    font-weight: 500;
    white-space: nowrap;
    cursor: pointer;
  }
  .dismiss:hover {
    color: #fff;
    background: rgb(255 255 255 / 16%);
  }
  .dismiss:focus-visible {
    outline: 2px solid var(--sideb-highlight, #d06c70);
    outline-offset: 2px;
  }
  @media (forced-colors: active) {
    .invite-banner {
      color: CanvasText;
      background: Canvas;
      border-color: CanvasText;
      backdrop-filter: none;
      box-shadow: none;
    }
    .dismiss {
      color: ButtonText;
      background: ButtonFace;
      border-color: ButtonText;
    }
  }
</style>

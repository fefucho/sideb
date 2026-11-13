<script lang="ts">
  import { t, language } from '$lib/i18n';
  import type { JamViewState } from '$lib/jam/types';
  import JamAvatars from './JamAvatars.svelte';
  import { badgeLabel } from './view';
  /** "In X's Jam" marker with the participants' avatars (port of `JamBadgeContent`). The caller decides when to render it. */
  let { state, size = 'regular', onTap, expanded, controls, element = $bindable() }:
    { state: Pick<JamViewState, 'host' | 'members'>; size?: 'regular' | 'compact'; onTap?: () => void; expanded?: boolean; controls?: string; element?: HTMLButtonElement } = $props();
  const compact = $derived(size === 'compact');
  const label = $derived(badgeLabel(state, $language));
</script>

{#snippet pill()}
  {#if state.members.length}<JamAvatars members={state.members} size={compact ? 16 : 22} limit={compact ? 3 : 4} />
  {:else}<svg class="people" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="8" cy="8" r="3.2" /><path d="M2 20c0-3.8 2.7-6 6-6s6 2.2 6 6Z" /><circle cx="16.5" cy="9" r="2.6" /><path d="M15.5 14.4c3.8-.6 6.5 1.4 6.5 5.6h-5.5c0-2.4-.3-4.2-1-5.6Z" /></svg>{/if}
  <span class="label">{label}</span>
{/snippet}

{#if onTap}
  <button bind:this={element} type="button" class="badge" class:compact title={$t('jam.badge.help')} aria-label={label} aria-haspopup="dialog" aria-expanded={expanded} aria-controls={controls} onclick={onTap}>{@render pill()}</button>
{:else}
  <span class="badge" class:compact role="img" aria-label={label}>{@render pill()}</span>
{/if}

<style>
  .badge { display: inline-flex; align-items: center; gap: 8px; box-sizing: border-box; max-width: 100%; margin: 0; padding: 5px 14px 5px 8px; border: 1px solid var(--sideb-acrylic-border, rgb(255 255 255 / 20%)); border-radius: 999px; color: rgb(255 255 255 / 92%); background: var(--sideb-acrylic-fallback, #353538); font: inherit; font-size: 13px; font-weight: 600; line-height: 20px; }
  @supports ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
    .badge { background: color-mix(in srgb, #000 18%, var(--sideb-acrylic-surface, rgb(43 43 49 / 78%))); backdrop-filter: var(--sideb-acrylic-blur); -webkit-backdrop-filter: var(--sideb-acrylic-blur); }
  }
  .badge.compact { gap: 6px; padding: 4px 10px 4px 6px; font-size: 11px; line-height: 16px; }
  button.badge { cursor: pointer; }
  button.badge:hover { border-color: rgb(255 255 255 / 32%); }
  button.badge:focus-visible { outline: 2px solid var(--sideb-highlight, #d06c70); outline-offset: 3px; }
  .label { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .people { flex: none; width: 16px; height: 16px; }
  .compact .people { width: 12px; height: 12px; }
  @media (forced-colors: active) { .badge { color: ButtonText; background: ButtonFace; border-color: ButtonText; backdrop-filter: none; } }
</style>

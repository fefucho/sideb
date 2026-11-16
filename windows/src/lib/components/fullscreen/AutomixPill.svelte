<script lang="ts">
  import { t } from '$lib/i18n';
  import { automixBlockedByJam, automixPresentation, type AutomixStatus } from '$lib/player/automix';
  interface Props { status: AutomixStatus; pending?: boolean; onToggle: () => void }
  let { status, pending = false, onToggle }: Props = $props();
  const presentation = $derived(automixPresentation(status, $t));
  // A Jam forces Automix off: the pill stays visible but disabled, the saved preference is untouched.
  const jam = $derived(automixBlockedByJam(status));
  const action = $derived(jam ? presentation.text : $t(presentation.on ? 'automix.pill.turnOff' : 'automix.pill.turnOn'));
  const description = $derived(`${presentation.text}. ${action}`);
  const title = $derived(`${$t('automix.pill.title')}: ${description}`);
  const descriptionId = $props.id();
</script>
<!-- Outside the bottom control bar: a small beta switch next to the panel toggles. -->
<button type="button" class="pill" data-tone={presentation.tone} data-automix-pill role="switch" aria-checked={presentation.on}
  disabled={pending || jam} aria-busy={pending || status.phase === 'preparing'} aria-label={$t('automix.pill.title')} aria-describedby={descriptionId} {title} onclick={onToggle}>
  <svg class="icon" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8h5.5l5 8H21M3 16h5.5l2-3.2M13.5 8H21" /><path d="m18 5 3 3-3 3M18 13l3 3-3 3" /></svg>
  <span class="name">{$t('automix.pill.title')}</span>
</button>
<span id={descriptionId} class="sr-only">{description}</span>
<style>
  .pill { position:relative; z-index:2; display:inline-flex; flex:none; align-items:center; gap:6px; box-sizing:border-box; height:32px; max-width:100%; padding:0 11px; border:1px solid rgb(255 255 255 / 12%); border-radius:999px; color:rgb(255 255 255 / 62%); background:rgb(255 255 255 / 9%); font:inherit; font-size:12px; font-weight:600; line-height:1; white-space:nowrap; cursor:pointer; }
  .pill:hover:not(:disabled) { color:#fff; background:rgb(255 255 255 / 16%); }
  .pill:disabled { cursor:default; opacity:.5; }
  .pill:disabled[aria-busy='true']:not([data-tone='busy']) { cursor:wait; }
  .icon { flex:none; width:14px; height:14px; }
  .name { overflow:hidden; text-overflow:ellipsis; }
  .pill[aria-checked='true'] { color:rgb(255 255 255 / 95%); }
  .pill[data-tone='ready'], .pill[data-tone='active'] { border-color:color-mix(in srgb, var(--sideb-highlight, #d06c70) 55%, transparent); }
  .pill[data-tone='ready'] .icon, .pill[data-tone='active'] .icon { color:var(--sideb-highlight, #d06c70); }
  .pill[data-tone='busy'] .icon { animation:automix-pulse 1.2s ease-in-out infinite; }
  .pill[data-tone='warning'] .icon { color:#ffd9a8; }
  .pill:focus-visible { outline:2px solid var(--sideb-highlight, #d06c70); outline-offset:3px; }
  .sr-only { position:absolute; width:1px; height:1px; padding:0; margin:-1px; overflow:hidden; clip-path:inset(50%); white-space:nowrap; }
  @keyframes automix-pulse { 50% { opacity:.35; } }
  /* The toolbar is narrow next to a long tab strip: keep the icon, drop the name. */
  @container panel-column (max-width:520px) { .name { display:none; } .pill { padding:0 9px; } }
  @media (prefers-reduced-motion:reduce) { .pill[data-tone='busy'] .icon { animation:none; } }
  @media (forced-colors:active) { .pill { border:1px solid ButtonText; color:ButtonText; background:ButtonFace; } }
</style>

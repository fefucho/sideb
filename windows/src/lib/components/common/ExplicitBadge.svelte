<script lang="ts">
  import { t, language } from '$lib/i18n';
  import { contentRating, type ContentMetadata } from '$lib/contentRating';
  let { item = {} }: { item?: ContentMetadata } = $props();
  const rating = $derived(contentRating(item));
  const label = $derived($t(rating === 'explicit' ? 'home.explicit_content' : rating === 'clean' ? 'content.clean' : 'content.unknown'));
</script>
{#if rating !== 'unknown'}
  <span class="explicit-badge" role="img" aria-label={label} title={label}>
    <svg viewBox="0 0 14 14" aria-hidden="true" focusable="false">
      {#if rating === 'explicit'}<path d="M4 3 H10 V4.5 H5.5 V6.25 H9.25 V7.75 H5.5 V9.5 H10 V11 H4 Z" />
      {:else if $language === 'es'}<path d="M4 3 H5.5 V9.5 H10 V11 H4 Z" />
      {:else}<path d="M10 3 H4 V11 H10 V9.5 H5.5 V4.5 H10 Z" />{/if}
    </svg>
  </span>
{:else}<span class="unavailable">{label}</span>{/if}

<style>
  .explicit-badge { --content-badge-side:clamp(9px, round(nearest, .85em, 1px), 12px); font:inherit; display:inline-flex; flex:0 0 var(--content-badge-side); align-items:center; justify-content:center; box-sizing:border-box; width:var(--content-badge-side); height:var(--content-badge-side); padding:0; border:0; border-radius:calc(var(--content-badge-side) * 3 / 14); background:rgb(255 255 255 / 78%); color:#1c1c1e; vertical-align:middle; line-height:1; }
  svg { display:block; flex:none; width:var(--content-badge-side); height:var(--content-badge-side); fill:currentColor; }
  @media (forced-colors: active) { .explicit-badge { background:CanvasText;color:Canvas;forced-color-adjust:none; } }
  .unavailable {position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap;}
</style>

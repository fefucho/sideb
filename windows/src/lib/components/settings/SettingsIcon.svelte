<script lang="ts">
  import type { SettingsCategoryId } from './settingsCategories';
  let { name }: { name: SettingsCategoryId } = $props();
</script>
<!-- Monochrome outline glyphs on a 24px grid; stroke follows currentColor (accent in the sidebar). -->
<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
  {#if name === 'general'}
    <circle cx="12" cy="12" r="3.2" /><path d="M12 3.5v2.3M12 18.2v2.3M3.5 12h2.3M18.2 12h2.3M6 6l1.6 1.6M16.4 16.4 18 18M18 6l-1.6 1.6M7.6 16.4 6 18" /><circle cx="12" cy="12" r="6.6" />
  {:else if name === 'playback'}
    <circle cx="12" cy="12" r="9" /><path d="M10 8.6v6.8l5.6-3.4z" />
  {:else if name === 'appearance'}
    <circle cx="12" cy="12" r="9" /><path d="M12 3v18" /><path d="M12 7.5a4.5 4.5 0 0 1 0 9" />
  {:else if name === 'shortcuts'}
    <rect x="3" y="6" width="18" height="12" rx="2.2" /><path d="M7 10h.01M10.5 10h.01M14 10h.01M17.5 10h.01M7.5 14h9" />
  {:else if name === 'homeFeed'}
    <path d="M4 11.2 12 4l8 7.2V19a1 1 0 0 1-1 1h-4.5v-5.5h-5V20H5a1 1 0 0 1-1-1z" />
  {:else if name === 'visualProviders'}
    <path d="M5 5h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-6.5L8 20.5V17H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" /><path d="M8 9.5h8M8 12.5h5" />
  {:else}
    <circle cx="12" cy="12" r="9" /><circle cx="12" cy="10" r="3" /><path d="M6.4 18.2c1.3-2.2 3.2-3.2 5.6-3.2s4.3 1 5.6 3.2" />
  {/if}
</svg>
<style>
  svg { width:100%; height:100%; fill:none; stroke:currentColor; stroke-width:1.6; stroke-linecap:round; stroke-linejoin:round; }
</style>

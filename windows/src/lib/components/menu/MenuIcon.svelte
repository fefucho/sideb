<script lang="ts">
  import type { MenuIconName } from '$lib/menu/types';
  let { name }: { name?: MenuIconName } = $props();
</script>

{#if name}
  <svg class="icon" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.45" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    {#if name === 'play'}<path d="M5 3.5v9l7-4.5-7-4.5Z" fill="currentColor" stroke="none" />
    {:else if name === 'shuffle'}<path d="M2 4h1.5c3 0 5 8 8 8H14m-2-2 2 2-2 2M2 12h1.5c1.2 0 2.2-1.3 3.2-2.8M9 6c.8-1.1 1.5-2 2.5-2H14m-2-2 2 2-2 2" />
    {:else if name === 'radio'}<circle cx="8" cy="8" r="1.2" fill="currentColor" stroke="none" /><path d="M4.8 4.8a4.5 4.5 0 0 0 0 6.4M11.2 4.8a4.5 4.5 0 0 1 0 6.4M2.7 2.7a7.5 7.5 0 0 0 0 10.6M13.3 2.7a7.5 7.5 0 0 1 0 10.6" />
    {:else if name === 'queue-next'}<path d="M2 3.5h8M2 7h5M2 10.5h5M9 9v5l4-2.5L9 9Z" />
    {:else if name === 'queue-end'}<path d="M2 3.5h8M2 7h8M2 10.5h8M12 9v5l3-2.5L12 9Z" />
    {:else if name === 'heart' || name === 'heart-remove' || name === 'heart-fill'}
      <path d="M8 13.3 2.8 8.4A3.1 3.1 0 0 1 7.2 4l.8.9.8-.9a3.1 3.1 0 0 1 4.4 4.4L8 13.3Z" fill={name === 'heart-fill' ? 'currentColor' : 'none'} />
      {#if name === 'heart-remove'}<path d="m11 10.7 3 3m0-3-3 3" />{/if}
    {:else if name === 'bookmark' || name === 'bookmark-fill'}<path d="M4 2.5h8v11l-4-2.8-4 2.8v-11Z" fill={name === 'bookmark-fill' ? 'currentColor' : 'none'} />
    {:else if name === 'music-list'}<path d="M2.5 4h8M2.5 7h8M2.5 10h5M12 3v7.2a1.8 1.8 0 1 1-1.5-1.8V4.5L14 3v6.2a1.8 1.8 0 1 1-1.5-1.8" />
    {:else if name === 'list-add'}<path d="M2 4h7M2 7h7M2 10h4M11.5 9v5m-2.5-2.5h5" />
    {:else if name === 'plus'}<circle cx="8" cy="8" r="6" /><path d="M8 5v6M5 8h6" />
    {:else if name === 'disc'}<circle cx="8" cy="8" r="6" /><circle cx="8" cy="8" r="1.5" />
    {:else if name === 'person'}<circle cx="8" cy="5" r="2.2" /><path d="M3.2 13.5c.4-2.3 2.2-3.6 4.8-3.6s4.4 1.3 4.8 3.6" />
    {:else if name === 'share'}<path d="M8 10V2.5m-3 3 3-3 3 3M3 8.5v5h10v-5" />
    {:else if name === 'trash'}<path d="M2.8 4.5h10.4M6 4.5V2.7h4v1.8m-5.8 0 .6 9h6.4l.6-9M6.5 7v4.2m3-4.2v4.2" />
    {:else if name === 'minus'}<circle cx="8" cy="8" r="6" /><path d="M5 8h6" />
    {:else if name === 'edit'}<path d="m3 11.5-.5 2 2-.5 8-8-1.5-1.5-8 8Zm7.3-6.8 1.5 1.5" />
    {:else if name === 'sort'}<path d="M3 4h10M3 8h7M3 12h4m3-6 3 3 3-3m-3 3V2" />
    {:else if name === 'reorder'}<path d="M3 4h10M3 8h10M3 12h10" />
    {:else if name === 'history'}<path d="M3.2 5.3V2.8m0 2.5h2.5M3.5 5a5.6 5.6 0 1 1-.4 5.4M8 4.5V8l2.5 1.5" />
    {:else if name === 'clock'}<circle cx="8" cy="8" r="6" /><path d="M8 4.5V8l2.5 1.5" />
    {:else if name === 'text'}<path d="M2.5 4V2.8h11V4M8 3v10m-2 0h4m1-5 2 5m-4 0 2-5 2 5m-.6-1.5h-2.8" />
    {:else if name === 'bell'}<path d="M3.3 11.5h9.4l-1.2-1.6V6.5a3.5 3.5 0 0 0-7 0v3.4l-1.2 1.6Zm3.2 1.5a1.5 1.5 0 0 0 3 0" /><path d="M12.4 3.1 14 1.7" />
    {:else if name === 'bell-off'}<path d="M3.3 11.5h9.4l-1.2-1.6V6.5a3.5 3.5 0 0 0-5.8-2.6M6.5 13a1.5 1.5 0 0 0 3 0M2 2l12 12" />
    {/if}
  </svg>
{:else}
  <span class="icon-placeholder" aria-hidden="true"></span>
{/if}

<style>
  .icon, .icon-placeholder { display: block; width: 16px; height: 16px; flex: 0 0 16px; }
  .icon-placeholder { visibility: hidden; }
</style>

<script lang="ts">
  type Icon = 'shuffle' | 'backward' | 'forward' | 'repeat' | 'lyrics' | 'annotations' | 'queue' | 'related';
  let { name, size = 16 }: { name: Icon; size?: number } = $props();
</script>

<svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
  {#if name === 'backward'}
    <path d="m11 5-9 7 9 7V5Zm10 0-9 7 9 7V5Z" fill="currentColor" stroke-width="1.2" />
  {:else if name === 'forward'}
    <path d="m3 5 9 7-9 7V5Zm10 0 9 7-9 7V5Z" fill="currentColor" stroke-width="1.2" />
  {:else if name === 'shuffle'}
    <path d="M3 6h2c5 0 7 12 12 12h4m-4-3 4 3-4 3M3 18h2c2.2 0 3.8-2.3 5.2-5M13.8 8C15 6.7 15.8 6 17 6h4m-4-3 4 3-4 3" />
  {:else if name === 'repeat'}
    <path d="M4 10V8a3 3 0 0 1 3-3h13m-3-3 3 3-3 3M20 14v2a3 3 0 0 1-3 3H4m3-3-3 3 3 3" />
  {:else if name === 'lyrics'}
    <path d="M5 3h14a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2h-7l-5 4v-4H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Z" />
    <path d="M8 8h2v3l-2 2m6-5h2v3l-2 2" stroke-width="2.5" />
  {:else if name === 'annotations'}
    <rect x="4" y="2" width="16" height="20" rx="2" /><path d="M7 2v20M10 7h7M10 10h7M10 13h5M7 18h13" />
  {:else if name === 'queue'}
    <path d="M8 5h13M8 12h13M8 19h13" /><path d="M3 5h.01M3 12h.01M3 19h.01" stroke-width="3" />
  {:else if name === 'related'}
    <path d="M3 6h9M3 10h9M3 14h7M17 16V4l5-2v5l-5 2" /><ellipse cx="14.5" cy="17.5" rx="2.5" ry="2" fill="currentColor" stroke="none" />
  {/if}
</svg>

<style>
  svg { display: block; flex: none; }
</style>

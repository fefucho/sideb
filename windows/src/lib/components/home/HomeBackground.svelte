<script lang="ts">
  import { appearance } from '$lib/appearance/preferences';
  import HomeAmbient from './HomeAmbient.svelte';
  let { artwork, session, active = true }: { artwork: string[]; session: string; active?: boolean } = $props();
</script>

{#if $appearance.homeBackground === 'solid'}
  <div class="home-solid" aria-hidden="true"></div>
{:else}
  <HomeAmbient {artwork} {session} {active} />
{/if}

<style>
  .home-solid { position: fixed; inset: 0 0 0 var(--sidebar-width); background: #211e21; z-index: 0; pointer-events: none; }
</style>

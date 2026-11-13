<script lang="ts">
  import { readable } from 'svelte/store';
  import { emptyJamState } from '$lib/jam/types';
  import JamPanel from '$lib/components/jam/JamPanel.svelte';
  import { useJamUi } from '$lib/components/jam/context';
  /** The Jam tab of the fullscreen player: the same panel as the Connections flyout, over the scene. */
  const ui = useJamUi();
  const jamState = ui?.state ?? readable(emptyJamState());
</script>

{#if ui}<JamPanel state={$jamState} actions={ui.actions} searchSongs={ui.searchSongs} variant="fullscreen" />{/if}

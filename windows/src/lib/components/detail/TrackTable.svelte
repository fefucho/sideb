<script lang="ts">
  import type { SongDto } from '$lib/types';
  import type { MenuOrigin } from '$lib/menu/types';
  import TrackList from '../common/TrackList.svelte';
  interface Props {
    source?: { kind: string; id: string }; indexOffset?: number; occurrenceIndices?: number[]; occurrenceKeys?: string[]; detail?: boolean;
    items: SongDto[]; currentTrackId: string | null; isPlaying: boolean;
    onPlay: (index: number) => void; onOpenArtist?: (id: string) => void;
    onOpenAlbum?: (id: string) => void; hideAlbumColumn?: boolean;
    showAlbumInSubtitle?: boolean; numbered?: boolean; flush?: boolean; origin?: MenuOrigin;
  }
  let props: Props = $props();
</script>
<TrackList {...props} />

<script lang="ts">
  import type { AccountSongDto } from '$lib/account/types';
  import TrackList from '../common/TrackList.svelte';
  type MenuEvent = MouseEvent | KeyboardEvent;
  interface Props {
    source?: { kind: string; id: string }; indexOffset?: number; occurrenceIndices?: number[]; occurrenceKeys?: string[]; detail?: boolean;
    items: AccountSongDto[]; currentTrackId: string | null; isPlaying: boolean;
    onPlay: (index: number) => void; onOpenArtist?: (id: string) => void;
    onOpenAlbum?: (id: string) => void; hideAlbumColumn?: boolean; numbered?: boolean;
    showAlbumInSubtitle?: boolean; likedIds?: Set<string>; pendingIds?: Set<string>;
    onToggleLike?: (track: AccountSongDto) => void; onToggleSaved?: (track: AccountSongDto) => void;
    onContextMenu?: (event: MenuEvent, track: AccountSongDto) => void;
    onRemoveTrack?: (track: AccountSongDto) => void;
    onMoveTrack?: (setVideoId: string, successorSetVideoId: string | null) => void;
    canReorder?: boolean; mutationPending?: boolean;
  }
  let props: Props = $props();
</script>
<TrackList {...props} origin={{view: 'library'}} />

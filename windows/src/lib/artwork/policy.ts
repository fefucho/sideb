export interface ArtworkTrackIdentity {
  videoId?: string | null;
  title?: string | null;
  duration?: number | null;
  albumId?: string | null;
  album?: string | null;
  artists?: string | null;
  artistRuns?: Array<{ text: string; id?: string | null }>;
}

export function animatedArtworkPrimaryArtist(track: ArtworkTrackIdentity | null | undefined): string {
  return track?.artistRuns?.find(run => run.text.trim())?.text.trim() || track?.artists?.trim() || '';
}

/** Stable album key makes track changes on one record reuse its existing video/player. */
export function animatedArtworkAlbumKey(track: ArtworkTrackIdentity | null | undefined): string {
  if (!track) return '';
  const id = track.albumId?.trim();
  if (id) return `id:${id}`;
  const album = track.album?.trim().toLowerCase();
  const artist = animatedArtworkPrimaryArtist(track).toLowerCase();
  return album ? `name:${album}\u0000${artist}` : track.videoId?.trim() ? `track:${track.videoId.trim()}` : `track-name:${track.title?.trim().toLowerCase() ?? ''}\u0000${artist}`;
}

/** Rejects late preparations from an older album/session revision. */
export function isCurrentAnimatedArtworkRequest(requestRevision: number, currentRevision: number, requestId: string, currentRequestId: string | null): boolean {
  return requestRevision === currentRevision && requestId === currentRequestId;
}

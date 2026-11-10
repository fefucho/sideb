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
  return track?.artistRuns?.find(run => run.id?.trim() && run.text.trim())?.text.trim() || track?.artists?.trim() || '';
}

const normalizedIdentity = (value: string | null | undefined) => value?.normalize('NFC').trim().toLowerCase().replace(/\s+/gu, ' ') ?? '';

/**
 * Stable album key makes track changes on one record reuse its existing video/player. With the optional visual
 * provider active (`visualProviderSalt`, sidebar only) the identity is per track — a provider's Canvas belongs to
 * one song, not to its album — and moves whenever the provider configuration changes (Mac `AnimatedArtworkIdentity`).
 */
export function animatedArtworkAlbumKey(track: ArtworkTrackIdentity | null | undefined, visualProviderSalt?: string | null): string {
  if (!track) return '';
  if (visualProviderSalt) return `extension:${visualProviderSalt}|track:${track.videoId?.trim() ?? ''}`;
  const id = track.albumId?.trim();
  if (id) return `id:${id}`;
  const album = normalizedIdentity(track.album);
  const artist = normalizedIdentity(animatedArtworkPrimaryArtist(track));
  return album ? `name:${album}\u0000${artist}` : track.videoId?.trim() ? `track:${track.videoId.trim()}` : `track-name:${normalizedIdentity(track.title)}\u0000${artist}`;
}

/** Rejects late preparations from an older album/session revision. */
export function isCurrentAnimatedArtworkRequest(requestRevision: number, currentRevision: number, requestId: string, currentRequestId: string | null): boolean {
  return requestRevision === currentRevision && requestId === currentRequestId;
}

export interface VideoDimensions { width: number; height: number }
/** Assets of the optional visual provider carry this id prefix (host `asset_id: visual-extension:<request>`). */
export const visualProviderAssetPrefix = 'visual-extension:';
export const isVisualProviderAsset = (assetId: string | null | undefined): boolean => !!assetId?.startsWith(visualProviderAssetPrefix);

/** Square artwork video, as validated since the fullscreen cover (<=1080 px). */
export function isSquareArtworkVideo(size: VideoDimensions): boolean {
  return size.width > 0 && size.width === size.height && size.width <= 1080;
}
/**
 * Portrait video by origin (Mac `allowsTallDimensions`). Apple tall: 3:4 ±, w/h 0.70–0.80, <=1080×1440. Provider
 * (`isExtension`): ~9:16, w/h 0.55–0.58, 720–1920 px tall. The two ranges are disjoint and neither widens the other:
 * a 1921 px provider video or a 1441 px Apple video is rejected, and a 9:16 video never passes as Apple's.
 */
export function isTallArtworkVideo(size: VideoDimensions, isExtension = false): boolean {
  if (!(size.height > size.width) || size.width <= 0 || size.width > 1080) return false;
  const ratio = size.width / Math.max(1, size.height);
  return isExtension ? ratio >= 0.55 && ratio <= 0.58 && size.height >= 720 && size.height <= 1920 : ratio >= 0.70 && ratio <= 0.80 && size.height <= 1440;
}
/** Decoded frame and reported asset must agree, and tall frames are only valid when portrait was requested. */
export function acceptsArtworkVideo(decoded: VideoDimensions, asset: VideoDimensions & { assetId?: string }, allowTall: boolean): boolean {
  if (decoded.width !== asset.width || decoded.height !== asset.height) return false;
  if (isSquareArtworkVideo(decoded)) return true;
  return allowTall && isTallArtworkVideo(decoded, isVisualProviderAsset(asset.assetId));
}
/** Apple allows up to 60 fps; the provider contract allows 60.1 (Mac `frameRate <= 60.1`). */
export function acceptsArtworkFrameRate(frameRate: number, assetId?: string): boolean {
  return Number.isFinite(frameRate) && frameRate > 0 && frameRate <= (isVisualProviderAsset(assetId) ? 60.1 : 60);
}

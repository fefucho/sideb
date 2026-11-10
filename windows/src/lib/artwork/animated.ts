import { invoke, convertFileSrc } from '@tauri-apps/api/core';
import { AnimatedArtworkClearCoordinator } from './clearCoordinator';
import { clearVisualProviderCache, getVisualProviderCacheSize } from '../visualProvider/api';

export interface AnimatedArtworkRequest {
  videoId: string; title: string; artists: string; album: string | null; albumId: string | null;
  durationSecs: number | null; storefront: string; preferHevc: false;
  /** Ask for the portrait (3:4) variant; the core falls back to the square one. Omitted = square only. */
  preferTall?: boolean;
  /** Only read by the optional visual provider (sidebar fallback); Apple ignores it. */
  explicit?: boolean | null;
}
export interface AnimatedArtworkAsset {
  assetId: string; localPath: string; codec: string; width: number; height: number;
  frameRate: number; sizeBytes: number;
}
export const animatedArtworkUrl = (asset: AnimatedArtworkAsset) => convertFileSrc(asset.localPath, 'asset');
export const prepareAnimatedArtwork = (request: AnimatedArtworkRequest, requestId: string) =>
  invoke<AnimatedArtworkAsset | null>('prepare_animated_artwork', { request, requestId });
export const cancelAnimatedArtwork = (requestId: string) => invoke<void>('cancel_animated_artwork', { requestId });
/** Apple's cache plus the optional provider's private cache, like Mac `AnimatedArtworkManager.size/clear`. */
export const getAnimatedArtworkCacheSize = async () =>
  (await invoke<number>('get_animated_artwork_cache_size')) + (await getVisualProviderCacheSize().catch(() => 0));
export const clearAnimatedArtworkCache = async () =>
  (await invoke<number>('clear_animated_artwork_cache')) + (await clearVisualProviderCache().catch(() => 0));

const clearCoordinator = new AnimatedArtworkClearCoordinator();
export const animatedArtworkClearState = () => clearCoordinator.clearing;
export const registerAnimatedArtworkRelease = (release: () => Promise<void>) => clearCoordinator.register(release);

/** Ask the mounted player to remove its source and drop its core lease before cache deletion. */
export function clearAnimatedArtworkCacheSafely(): Promise<number> {
  return clearCoordinator.clear(clearAnimatedArtworkCache);
}

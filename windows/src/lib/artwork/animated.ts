import { invoke, convertFileSrc } from '@tauri-apps/api/core';
import { AnimatedArtworkClearCoordinator } from './clearCoordinator';

export interface AnimatedArtworkRequest {
  videoId: string; title: string; artists: string; album: string | null; albumId: string | null;
  durationSecs: number | null; storefront: string; preferHevc: false;
}
export interface AnimatedArtworkAsset {
  assetId: string; localPath: string; codec: string; width: number; height: number;
  frameRate: number; sizeBytes: number;
}
export const animatedArtworkUrl = (asset: AnimatedArtworkAsset) => convertFileSrc(asset.localPath, 'asset');
export const prepareAnimatedArtwork = (request: AnimatedArtworkRequest, requestId: string) =>
  invoke<AnimatedArtworkAsset | null>('prepare_animated_artwork', { request, requestId });
export const cancelAnimatedArtwork = (requestId: string) => invoke<void>('cancel_animated_artwork', { requestId });
export const getAnimatedArtworkCacheSize = () => invoke<number>('get_animated_artwork_cache_size');
export const clearAnimatedArtworkCache = () => invoke<number>('clear_animated_artwork_cache');

const clearCoordinator = new AnimatedArtworkClearCoordinator();
export const animatedArtworkClearState = () => clearCoordinator.clearing;
export const registerAnimatedArtworkRelease = (release: () => Promise<void>) => clearCoordinator.register(release);

/** Ask the mounted player to remove its source and drop its core lease before cache deletion. */
export function clearAnimatedArtworkCacheSafely(): Promise<number> {
  return clearCoordinator.clear(clearAnimatedArtworkCache);
}

import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import {
  visualProviderEvents,
  type VisualProviderArtworkRequest,
  type VisualProviderAsset,
  type VisualProviderLoginState,
  type VisualProviderState,
} from './types';

/** Thin, mockable boundary over the Tauri commands. */
export interface VisualProviderApi {
  state(): Promise<VisualProviderState>;
  setEnabled(enabled: boolean): Promise<VisualProviderState>;
  installBundled(): Promise<VisualProviderState>;
  installFromFolder(path: string): Promise<VisualProviderState>;
  uninstall(): Promise<VisualProviderState>;
  saveToken(token: string): Promise<VisualProviderState>;
  openLogin(title: string | null): Promise<boolean>;
  cancelLogin(): Promise<void>;
  onChanged(listener: (state: VisualProviderState) => void): Promise<UnlistenFn>;
  onLogin(listener: (state: VisualProviderLoginState) => void): Promise<UnlistenFn>;
}

export const visualProviderApi: VisualProviderApi = {
  state: () => invoke('get_visual_provider_state'),
  setEnabled: enabled => invoke('set_visual_provider_enabled', { enabled }),
  installBundled: () => invoke('install_visual_provider_bundled'),
  installFromFolder: path => invoke('install_visual_provider_from_folder', { path }),
  uninstall: () => invoke('uninstall_visual_provider'),
  saveToken: token => invoke('save_visual_provider_token', { token }),
  openLogin: title => invoke('open_visual_provider_login', { title }),
  cancelLogin: () => invoke('cancel_visual_provider_login'),
  onChanged: listener => listen<VisualProviderState>(visualProviderEvents.changed, event => listener(event.payload)),
  onLogin: listener => listen<{ state: VisualProviderLoginState }>(visualProviderEvents.login, event => listener(event.payload.state)),
};

/**
 * Fallback visual for the sidebar's vertical player (route it through `resolveVisualArtwork`).
 * `null` = nothing usable (the reason is in the provider state). The file stays leased until
 * `releaseVisualProviderArtwork(requestId)`; call it when the video is unmounted or the request is stale.
 */
export const prepareVisualProviderArtwork = (request: VisualProviderArtworkRequest, requestId: string) =>
  invoke<VisualProviderAsset | null>('prepare_visual_provider_artwork', { request, requestId });
export const releaseVisualProviderArtwork = (requestId: string) =>
  invoke<void>('cancel_visual_provider_artwork', { requestId });
export const getVisualProviderCacheSize = () => invoke<number>('get_visual_provider_cache_size');
export const clearVisualProviderCache = () => invoke<number>('clear_visual_provider_cache');

/**
 * Emitted BEFORE the host releases files: detach the provider video (drop its `src`) synchronously
 * and re-run the request afterwards. Returns the unsubscribe function.
 */
export const onVisualProviderWillChange = (listener: () => void): Promise<UnlistenFn> =>
  listen(visualProviderEvents.willChange, () => listener());

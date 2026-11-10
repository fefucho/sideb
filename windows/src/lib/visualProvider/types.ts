/** DTOs of the optional visual provider host (`src-tauri/src/visual_provider`). Never carries a credential. */
export interface VisualProviderInfo {
  id: string;
  name: string;
  version: string;
  /** The provider signs in through a web view; otherwise only a manual token exists. */
  webLogin: boolean;
}

export interface VisualProviderState {
  installed: boolean;
  /** A preinstalled package ships with this build (install/reinstall button). */
  bundledAvailable: boolean;
  provider: VisualProviderInfo | null;
  enabled: boolean;
  hasCredential: boolean;
  /** The provider rejected the session: queries wait for a new token. */
  authBlocked: boolean;
  /** Bumps on every configuration change; consumers re-run their request when it moves. */
  revision: number;
  /** Localization key `visualProvider.status.*`. */
  statusKey: string;
  /** Mixed into the sidebar artwork identity so the provider's video is per track. Null when inactive. */
  identitySalt: string | null;
}

export type VisualProviderLoginState = 'waiting' | 'extracting' | 'connected' | 'failed' | 'closed';

/** Same shape as `AnimatedArtworkRequest` (extra fields are ignored by the host) plus `explicit`. */
export interface VisualProviderArtworkRequest {
  videoId: string;
  title: string;
  /** The principal artist: exactly what is sent to `prepare_animated_artwork`. */
  artists: string;
  album: string | null;
  durationSecs: number | null;
  explicit?: boolean | null;
}

/** Same shape as `AnimatedArtworkAsset`, so the existing `animatedArtworkUrl()` serves it. */
export interface VisualProviderAsset {
  assetId: string;
  localPath: string;
  codec: string;
  width: number;
  height: number;
  frameRate: number;
  sizeBytes: number;
}

export const visualProviderEvents = {
  changed: 'visual-provider-changed',
  willChange: 'visual-provider-will-change',
  login: 'visual-provider-login',
} as const;

/**
 * Apple remains authoritative. The optional provider is a fallback ONLY in the sidebar's vertical
 * player, ONLY when enabled, after an empty result or an error from Apple. Fullscreen passes
 * `verticalPlayer: false` and never reaches the provider. Mirrors `VisualProviderRouting.swift`.
 */
export interface VisualArtworkRoute<T> {
  verticalPlayer: boolean;
  extensionEnabled: boolean;
  primary: () => Promise<T | null>;
  secondary: () => Promise<T | null>;
  /** Abort when the request became stale: nothing further is consulted. */
  signal?: AbortSignal;
}

export function allowsSecondary(verticalPlayer: boolean, extensionEnabled: boolean): boolean {
  return verticalPlayer && extensionEnabled;
}

const abortError = () => new DOMException('The visual request was cancelled.', 'AbortError');
export const isAbortError = (error: unknown): boolean => error instanceof DOMException && error.name === 'AbortError';

export async function resolveVisualArtwork<T>(route: VisualArtworkRoute<T>): Promise<T | null> {
  const { signal } = route;
  const checkCancelled = () => { if (signal?.aborted) throw abortError(); };
  const allowSecondary = allowsSecondary(route.verticalPlayer, route.extensionEnabled);
  try {
    const asset = await route.primary();
    if (asset) { checkCancelled(); return asset; }
  } catch (error) {
    if (isAbortError(error)) throw error;
    checkCancelled();
    if (!allowSecondary) throw error;
  }
  checkCancelled();
  if (!allowSecondary) return null;
  return route.secondary();
}

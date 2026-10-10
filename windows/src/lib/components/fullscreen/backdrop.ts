import { cardArtworkCandidates, fallbackArtworkUrl } from '../../images/artwork';

/** Apple FullscreenBackdrop requests a small 300px image, independently of the
 * foreground's original/max-quality artwork. Keep the provider URL as fallback.
 * Use the existing bounded-image policy to leave signed/query/external URLs intact.
 */
export function fullscreenBackdropCandidates(thumbnail: string | null | undefined): string[] {
  if (!thumbnail) return [];
  const bounded = cardArtworkCandidates(thumbnail, 300)[0];
  if (bounded === thumbnail) return [thumbnail];
  return [...new Set([fallbackArtworkUrl(thumbnail, 300), thumbnail]
    .filter((url): url is string => Boolean(url)))];
}

const GOOGLE_ARTWORK_HOSTS = new Set(['lh3.googleusercontent.com', 'yt3.ggpht.com', 'yt3.googleusercontent.com']);
const YOUTUBE_THUMBNAIL_HOSTS = new Set(['i.ytimg.com', 'img.youtube.com']);
const GOOGLE_SIZE_WITH_FLAGS = /^(.*)(=w\d+-h\d+|=s\d+)((?:-[a-z][a-z0-9]*)*)$/i;
const YOUTUBE_THUMBNAIL_SUFFIX = /(?:^|\/)(?:default|mqdefault|hqdefault|sddefault)\.jpg$/;

function parseKnownImageURL(value: string | null | undefined): URL | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
    return url;
  } catch {
    return null;
  }
}

function isGoogleArtworkHost(host: string): boolean {
  return GOOGLE_ARTWORK_HOSTS.has(host.toLowerCase());
}

function replaceGoogleSize(pathname: string, replacement: (flags: string) => string): string | null {
  const finalSlash = pathname.lastIndexOf('/');
  const prefix = pathname.slice(0, finalSlash + 1);
  const tail = pathname.slice(finalSlash + 1);
  const match = GOOGLE_SIZE_WITH_FLAGS.exec(tail);
  if (!match) return null;
  return `${prefix}${match[1]}${replacement(match[3])}`;
}

/** Builds a 1200px Google artwork or YouTube max resolution URL when its known format supports it. */
export function maxQualityArtworkUrl(value: string | null | undefined): string | null {
  const url = parseKnownImageURL(value);
  if (!url) return value ?? null;

  if (isGoogleArtworkHost(url.hostname)) {
    const pathname = replaceGoogleSize(url.pathname, flags => {
      const wasSingleSize = /=s\d+/i.test(url.pathname.slice(url.pathname.lastIndexOf('/') + 1));
      return `${wasSingleSize ? '=s1200' : '=w1200-h1200'}${flags}`;
    });
    if (!pathname) return value ?? null;
    url.pathname = pathname;
    return url.href;
  }

  if (YOUTUBE_THUMBNAIL_HOSTS.has(url.hostname.toLowerCase()) && YOUTUBE_THUMBNAIL_SUFFIX.test(url.pathname)) {
    url.pathname = url.pathname.replace(YOUTUBE_THUMBNAIL_SUFFIX, (suffix) => `${suffix.slice(0, suffix.lastIndexOf('/') + 1)}maxresdefault.jpg`);
    return url.href;
  }
  return value ?? null;
}

/** Requests Google's original artwork only for the known Music artwork hosts and size-token format. */
export function originalArtworkUrl(value: string | null | undefined): string | null {
  const url = parseKnownImageURL(value);
  if (!url || !isGoogleArtworkHost(url.hostname)) return null;
  const pathname = replaceGoogleSize(url.pathname, () => '=s0');
  if (!pathname) return null;
  url.pathname = pathname;
  url.searchParams.set('imgmax', '0');
  return url.href;
}

/** Keeps the original URL as a fallback while lowering only known Google artwork variants to 544px. */
export function fallbackArtworkUrl(value: string | null | undefined, targetPixelSize = 544): string | null {
  const url = parseKnownImageURL(value);
  if (!url || !isGoogleArtworkHost(url.hostname)) return value ?? null;
  const size = Math.max(1, Math.floor(targetPixelSize));
  const pathname = replaceGoogleSize(url.pathname, flags => {
    const wasSingleSize = /=s\d+/i.test(url.pathname.slice(url.pathname.lastIndexOf('/') + 1));
    return `${wasSingleSize ? `=s${size}` : `=w${size}-h${size}`}${flags}`;
  });
  if (!pathname) return value ?? null;
  url.pathname = pathname;
  return url.href;
}

/** Ordered fullscreen attempts: original, largest CDN variant, 544px, then the source thumbnail. */
export function artworkCandidates(value: string | null | undefined): string[] {
  const candidates = [originalArtworkUrl(value), maxQualityArtworkUrl(value), fallbackArtworkUrl(value), value]
    .filter((url): url is string => Boolean(url));
  return [...new Set(candidates)];
}

/** Returns the next URL not yet rejected for the current track. */
export function nextArtworkUrl(candidates: readonly string[], failedUrls: readonly string[]): string | null {
  const failed = new Set(failedUrls);
  return candidates.find(url => !failed.has(url)) ?? null;
}

/** Cards request a bounded physical-pixel variant, then retry the exact provider URL.
 * Query-bearing/signed and external URLs remain byte-for-byte unchanged.
 * Fullscreen uses its existing original/max-quality candidate policy independently.
 */
export function cardArtworkCandidates(value: string | null | undefined, cssSize: number, pixelRatio = 1): string[] {
  if (!value) return [];
  const url = parseKnownImageURL(value);
  if (!url || url.search || url.hash || !isGoogleArtworkHost(url.hostname)) return [value];
  const size = Math.max(32, Math.min(1200, Math.ceil((Number.isFinite(cssSize) ? cssSize : 160)
    * (Number.isFinite(pixelRatio) ? Math.max(1, pixelRatio) : 1) / 32) * 32));
  return [...new Set([fallbackArtworkUrl(value, size), value].filter((candidate): candidate is string => Boolean(candidate)))];
}

export interface ArtworkFailures { key: string; urls: string[] }
/** A recycled image cannot reject the replacement, or an attempt already superseded by fallback. */
export function rejectArtworkAttempt(failures: ArtworkFailures, key: string, candidates: readonly string[], attemptKey: string, url: string): ArtworkFailures {
  const previous = failures.key === key ? failures.urls : [];
  if (attemptKey !== key || nextArtworkUrl(candidates, previous) !== url) return failures;
  return { key, urls: [...previous, url] };
}

import { ambientColor, chroma, samplePalette, type RGB } from './ambient';
import { fallbackArtworkUrl } from '$lib/images/artwork';

const LIMIT = 128;
const cache = new Map<string, RGB | null>();
const pending = new Map<string, Promise<RGB | null>>();
let cacheSession: string | null = null;

/** Puro: color más cromático de la muestra, pasado por ambientColor; null si no hay color utilizable. */
export function dominantColor(pixels: ArrayLike<number>): RGB | null {
  const palette = samplePalette(pixels);
  if (!palette.length) return null;
  const best = palette.reduce((a, b) => (chroma(b) > chroma(a) ? b : a));
  return ambientColor(best);
}

/** 'rgb(r g b)' con enteros, o null. */
export function cssColor(rgb: RGB | null): string | null {
  if (!rgb) return null;
  const [r, g, b] = rgb.map(c => Math.max(0, Math.min(255, Math.round(c))));
  return `rgb(${r} ${g} ${b})`;
}

async function sample(url: string): Promise<RGB | null> {
  const image = new Image();
  image.crossOrigin = 'anonymous';
  image.src = fallbackArtworkUrl(url, 32) ?? url;
  await image.decode();
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 32;
  const ctx = canvas.getContext('2d');
  if (!ctx) return null;
  ctx.drawImage(image, 0, 0, 32, 32);
  return dominantColor(ctx.getImageData(0, 0, 32, 32).data);
}

function useSession(session: string) {
  if (cacheSession === session) return;
  cache.clear();
  pending.clear();
  cacheSession = session;
}

/** Color de una carátula; null si no hay URL, falla la carga o no hay color. Nunca rechaza. */
export function coverColor(url: string | null | undefined, session: string): Promise<RGB | null> {
  if (!url) return Promise.resolve(null);
  useSession(session);
  if (cache.has(url)) {
    const value = cache.get(url)!;
    cache.delete(url);
    cache.set(url, value);
    return Promise.resolve(value);
  }
  const running = pending.get(url);
  if (running) return running;
  const run = async (): Promise<RGB | null> => {
    let value: RGB | null = null;
    // A failed load is remembered too: recycled cards must not refetch a broken cover on every mount.
    try { value = await sample(url); } catch { value = null; }
    if (cacheSession === session) {
      cache.set(url, value);
      while (cache.size > LIMIT) cache.delete(cache.keys().next().value as string);
    }
    return value;
  };
  const task = run().finally(() => { if (pending.get(url) === task) pending.delete(url); });
  pending.set(url, task);
  return task;
}

export function resetCoverColors(): void {
  cache.clear();
  pending.clear();
  cacheSession = null;
}

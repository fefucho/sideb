import { samplePalette as sampleHueFamilies } from '../home/ambient';
import { fallbackArtworkUrl } from '../images/artwork';

/**
 * Port of macOS `PlaybackSidebarPalette` (FIX-289): the cover's real hue in a dark-mode legible
 * luminance, a vertical top→bottom gradient from the sampled top/bottom bands, warm yellows kept
 * amber instead of olive, saturation proportional to the cover (never forced), and a neutral
 * charcoal without blue bias when there is no artwork or the cover is monochrome.
 * Components in 0…1, like the Swift `HomeAmbientRGB`.
 */
export interface Rgb { red: number; green: number; blue: number }
export interface SidebarPalette { primary: Rgb; secondary: Rgb; isChromatic: boolean }

export const neutralSidebarPalette: SidebarPalette = {
  primary: { red: 0.14, green: 0.14, blue: 0.14 },
  secondary: { red: 0.09, green: 0.09, blue: 0.09 },
  isChromatic: false,
};
const chromaOf = (c: Rgb) => Math.max(c.red, c.green, c.blue) - Math.min(c.red, c.green, c.blue);

function hueFraction(c: Rgb): number {
  const maximum = Math.max(c.red, c.green, c.blue);
  const chroma = chromaOf(c);
  if (chroma <= 0) return 0;
  const raw = maximum === c.red ? (c.green - c.blue) / chroma / 6
    : maximum === c.green ? ((c.blue - c.red) / chroma + 2) / 6
    : ((c.red - c.green) / chroma + 4) / 6;
  return (raw + 1) % 1;
}
function shortestHueDelta(from: number, to: number): number {
  let delta = to - from;
  if (delta > 0.5) delta -= 1;
  if (delta < -0.5) delta += 1;
  return delta;
}
function hsl(hue: number, saturation: number, lightness: number): Rgb {
  const a = saturation * Math.min(lightness, 1 - lightness);
  const component = (n: number) => {
    const k = (n + hue * 12) % 12;
    return Math.max(0, Math.min(1, lightness - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))));
  };
  return { red: component(0), green: component(8), blue: component(4) };
}
/** Scales down until relative luminance allows white controls on top. */
function clampedForWhiteForeground(color: Rgb, maxLuminance: number): Rgb {
  const linear = (v: number) => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  let { red, green, blue } = color;
  for (let guard = 0; guard < 400 && 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue) > maxLuminance; guard++) {
    red *= 0.94; green *= 0.94; blue *= 0.94;
  }
  return { red, green, blue };
}
/** Yellow/lime (hue 0.12–0.20) is guided to bronze/amber so darkening does not turn it into olive. */
function warmed(hue: number): number {
  return hue >= 0.12 && hue <= 0.20 ? 0.11 + ((hue - 0.12) / 0.08) * 0.03 : hue;
}
function saturationOf(dominant: Rgb): number {
  const rawSaturation = chromaOf(dominant) / Math.max(Math.max(dominant.red, dominant.green, dominant.blue), 0.001);
  return Math.min(0.50, Math.max(0.18, 0.08 + rawSaturation * 0.60));
}
function primaryColor(dominant: Rgb): Rgb {
  return clampedForWhiteForeground(hsl(warmed(hueFraction(dominant)), saturationOf(dominant), 0.24), 0.11);
}
function secondaryColor(dominant: Rgb): Rgb {
  return clampedForWhiteForeground(hsl(warmed(hueFraction(dominant)), saturationOf(dominant) * 0.88, 0.15), 0.065);
}

/** Hue-family tints (Mac `HomeAmbientPaletteSampler.tints`), reusing the shared Windows sampler. */
export function tintsFromRgba(rgba: ArrayLike<number>): Rgb[] {
  return sampleHueFamilies(rgba).map(([r, g, b]) => ({ red: r / 255, green: g / 255, blue: b / 255 }));
}
export function paletteFromTints(tints: Rgb[], fallbackLuminance: number | null = null): SidebarPalette {
  const dominant = tints[0];
  if (!dominant || chromaOf(dominant) < 0.06) {
    if (fallbackLuminance === null) return neutralSidebarPalette;
    const top = Math.min(0.20, Math.max(0.11, 0.11 + fallbackLuminance * 0.09));
    const bottom = Math.min(0.14, Math.max(0.08, top * 0.68));
    return { primary: { red: top, green: top, blue: top }, secondary: { red: bottom, green: bottom, blue: bottom }, isChromatic: false };
  }
  const hue = warmed(hueFraction(dominant));
  const sat = saturationOf(dominant);
  let secondHue = hue;
  if (tints.length > 1 && chromaOf(tints[1]) >= 0.10) {
    const candidate = hueFraction(tints[1]);
    secondHue = (hue + shortestHueDelta(hue, candidate) * 0.25 + 1) % 1;
  }
  secondHue = warmed(secondHue);
  return {
    primary: clampedForWhiteForeground(hsl(hue, sat, 0.24), 0.11),
    secondary: clampedForWhiteForeground(hsl(secondHue, sat * 0.88, 0.15), 0.065),
    isChromatic: true,
  };
}
function paletteFromGlobal(rgba: ArrayLike<number>): SidebarPalette {
  const tints = tintsFromRgba(rgba);
  if (tints.length) return paletteFromTints(tints);
  if (rgba.length < 4 || rgba.length % 4) return neutralSidebarPalette;
  let total = 0, count = 0;
  for (let i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] / 255 <= 0.5) continue;
    total += 0.2126 * rgba[i] / 255 + 0.7152 * rgba[i + 1] / 255 + 0.0722 * rgba[i + 2] / 255;
    count++;
  }
  return count ? paletteFromTints([], total / count) : neutralSidebarPalette;
}
/**
 * Square RGBA buffer of `side`×`side`: samples the top and bottom ~22 % row bands so the hero blends with the
 * panel at both seams, falling back per band to the whole cover when a band has no legible chroma.
 */
export function paletteFromRgba(rgba: ArrayLike<number>, side?: number): SidebarPalette {
  const pixelCount = Math.floor(rgba.length / 4);
  const resolvedSide = side ?? Math.floor(Math.sqrt(pixelCount));
  if (side === undefined && (resolvedSide * resolvedSide !== pixelCount || resolvedSide < 2)) return paletteFromGlobal(rgba);
  if (resolvedSide < 1 || rgba.length !== resolvedSide * resolvedSide * 4) return neutralSidebarPalette;
  if (resolvedSide < 2) return paletteFromGlobal(rgba);
  const bandRows = Math.min(Math.max(1, Math.round(resolvedSide * 0.22)), Math.floor(resolvedSide / 2));
  const bytesPerRow = resolvedSide * 4;
  const slice = (from: number, to: number) => Array.prototype.slice.call(rgba, from, to) as number[];
  const topTints = tintsFromRgba(slice(0, bandRows * bytesPerRow));
  const bottomTints = tintsFromRgba(slice((resolvedSide - bandRows) * bytesPerRow, resolvedSide * bytesPerRow));
  const topDominant = topTints[0], bottomDominant = bottomTints[0];
  const topIsChromatic = !!topDominant && chromaOf(topDominant) >= 0.06;
  const bottomIsChromatic = !!bottomDominant && chromaOf(bottomDominant) >= 0.06;
  if (topIsChromatic && bottomIsChromatic) {
    return { primary: primaryColor(topDominant), secondary: secondaryColor(bottomDominant), isChromatic: true };
  }
  const global = paletteFromGlobal(rgba);
  return {
    primary: topIsChromatic ? primaryColor(topDominant) : global.primary,
    secondary: bottomIsChromatic ? secondaryColor(bottomDominant) : global.secondary,
    isChromatic: topIsChromatic || bottomIsChromatic || global.isChromatic,
  };
}

export interface PaletteSurfaceOptions { reduceTransparency?: boolean; increasedContrast?: boolean }
const scale = (c: Rgb, factor: number): Rgb => ({ red: c.red * factor, green: c.green * factor, blue: c.blue * factor });
/** Top surface of the sidebar (Mac `surfaceColor`). */
export function sidebarTopSurface(palette: SidebarPalette, options: PaletteSurfaceOptions = {}): Rgb {
  if (options.reduceTransparency || options.increasedContrast) return scale(palette.primary, 0.78);
  return clampedForWhiteForeground(scale(palette.primary, 1.18), 0.115);
}
/** Bottom surface of the sidebar (Mac `bottomSurfaceColor`). */
export function sidebarBottomSurface(palette: SidebarPalette, options: PaletteSurfaceOptions = {}): Rgb {
  if (options.reduceTransparency || options.increasedContrast) return scale(palette.secondary, 0.75);
  return clampedForWhiteForeground(scale(palette.secondary, 1.08), 0.075);
}
export function rgbCss(color: Rgb, alpha = 1): string {
  const byte = (v: number) => Math.round(Math.min(1, Math.max(0, v)) * 255);
  return alpha >= 1 ? `rgb(${byte(color.red)} ${byte(color.green)} ${byte(color.blue)})`
    : `rgb(${byte(color.red)} ${byte(color.green)} ${byte(color.blue)} / ${Math.round(alpha * 1000) / 1000})`;
}
export interface SidebarPaletteCss { top: string; bottom: string; background: string }
/** CSS for the continuous top→bottom surface over the `#121214` base used by `PlaybackSidebarBackground`. */
export function sidebarPaletteCss(palette: SidebarPalette, options: PaletteSurfaceOptions = {}): SidebarPaletteCss {
  const top = rgbCss(sidebarTopSurface(palette, options)), bottom = rgbCss(sidebarBottomSurface(palette, options));
  return { top, bottom, background: `linear-gradient(180deg, ${top}, ${bottom}), rgb(18 18 20)` };
}

const paletteSide = 24;
/** 24×24 RGBA samples of a cover; `null` when it cannot be read (CORS, network, no canvas). */
export async function loadCoverPixels(url: string): Promise<Uint8ClampedArray | null> {
  try {
    const image = new Image();
    image.crossOrigin = 'anonymous';
    image.decoding = 'async';
    image.src = fallbackArtworkUrl(url, 48) ?? url;
    await image.decode();
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = paletteSide;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    if (!context) return null;
    context.drawImage(image, 0, 0, paletteSide, paletteSide);
    return context.getImageData(0, 0, paletteSide, paletteSide).data;
  } catch { return null; }
}

/**
 * Resolves the palette for the current cover. A newer request supersedes an older one; an unreadable cover
 * publishes the neutral palette instead of keeping the previous track's color.
 */
export class SidebarPaletteController {
  private revision = 0;
  private cache = new Map<string, SidebarPalette>();
  constructor(
    private publish: (palette: SidebarPalette) => void,
    private load: (url: string) => Promise<ArrayLike<number> | null> = loadCoverPixels,
  ) {}
  async update(thumbnail: string | null | undefined): Promise<void> {
    const revision = ++this.revision;
    if (!thumbnail) { this.publish(neutralSidebarPalette); return; }
    const cached = this.cache.get(thumbnail);
    if (cached) { this.cache.delete(thumbnail); this.cache.set(thumbnail, cached); this.publish(cached); return; }
    const pixels = await this.load(thumbnail).catch(() => null);
    if (revision !== this.revision) return;
    const palette = pixels ? paletteFromRgba(pixels, paletteSide) : neutralSidebarPalette;
    if (pixels) {
      this.cache.set(thumbnail, palette);
      while (this.cache.size > 32) this.cache.delete(this.cache.keys().next().value!);
    }
    this.publish(palette);
  }
  dispose() { ++this.revision; }
}

/**
 * Pure geometry/policy shared by the side player pieces. Ported from macOS
 * `PlaybackSidebarLayout`, `SidebarArtworkLayout` and `SidebarArtworkScrollState`;
 * all values are CSS pixels. Components only apply what these functions return.
 */
export type SidebarPanel = 'lyrics' | 'artwork' | 'queue';

export const sidebarLayout = {
  width: 380,
  inset: 6,
  headerHeight: 58,
  metadataHeight: 68,
  /** The cover starts just inside the header band (macOS `coverTop`). */
  coverTop: 56,
  /** The cover spans the panel minus this inset per side; text and controls keep `contentInset`. */
  coverInset: 4,
  contentInset: 20,
  /** One vertical rhythm of the artwork panel, measured between visible glyph/shape edges (FIX-349). */
  gap: 23,
  /** Progress bar spacing, measured from the bar itself and not from the time labels around it. */
  progressGap: 28,
  /** Cover → title text; the title glyphs sit ~6 px below the metadata frame top. */
  metadataSpacing: 17,
  /** Lyrics/queue footers keep their own metadata spacing. */
  footerMetadataSpacing: 16,
  /** Metadata frame leaves ~20 px under the artist line: progress top = progressGap - 20. */
  progressTopGap: 8,
  /** Time labels are 13 px tall, 9 px under the 5 px bar: bar bottom → play top = progressGap + 1. */
  progressToTransportGap: 7,
  /** Volume glyphs sit ~8 px inside their 32 px row. */
  volumeRowSlack: 8,
  /** Height reserved by "Up next" or the lyrics sample, including its 16/12 px margins. */
  upcomingBlockHeight: 134,
  /** Panel height from which the area under the transport is shown (queue or lyrics sample). */
  upcomingMinPanelHeight: 840,
  lyricsPreviewFontSize: 26,
} as const;

/** Queue/lyrics sample is shown only on the square cover layout and in tall panels. */
export function showsUpcoming(panelHeight: number, panel: SidebarPanel, isPortrait = false): boolean {
  return panel === 'artwork' && !isPortrait && panelHeight >= sidebarLayout.upcomingMinPanelHeight;
}
function controlsHeight(panelHeight: number): number {
  return Math.min(240, Math.max(200, panelHeight * 0.24));
}
/** Height of the fixed footer (progress + transport + volume [+ metadata] [+ upcoming]). */
export function sidebarFooterHeight(panelHeight: number, panel: SidebarPanel = 'lyrics', isPortrait = false, width: number = sidebarLayout.width): number {
  const minimum = controlsHeight(panelHeight)
    + (panel === 'artwork' ? 0 : sidebarLayout.metadataHeight + sidebarLayout.footerMetadataSpacing)
    + (showsUpcoming(panelHeight, panel, isPortrait) ? sidebarLayout.upcomingBlockHeight : 0);
  if (panel !== 'artwork' || isPortrait) return minimum;
  const idealHero = sidebarLayout.coverTop + Math.max(0, width - sidebarLayout.coverInset * 2) + sidebarLayout.metadataSpacing + sidebarLayout.metadataHeight;
  return Math.max(minimum, panelHeight - idealHero);
}
/** Fixed (no longer height dependent): bar bottom → play top is `progressGap + 1` including the time labels. */
export function progressToTransportSpacing(_panelHeight?: number): number {
  return sidebarLayout.progressToTransportGap;
}

export interface SidebarArtworkGeometry {
  width: number; height: number; portrait: boolean;
  metadataWidth: number; cardSide: number; cardTop: number; metadataTop: number;
  videoWidth: number; videoHeight: number; videoTop: number;
}
/** Square artwork stays a card; only a ready portrait video becomes immersive (full width and height). */
export function sidebarArtworkGeometry(widthPx: number, heightPx: number, portrait: boolean): SidebarArtworkGeometry {
  const width = Math.max(0, Number.isFinite(widthPx) ? widthPx : 0);
  const height = Math.max(0, Number.isFinite(heightPx) ? heightPx : 0);
  const { headerHeight: header, metadataHeight, metadataSpacing, coverTop, coverInset, contentInset } = sidebarLayout;
  const cardTop = coverTop;
  const cardSide = Math.max(0, Math.min(width - coverInset * 2, height - cardTop - metadataSpacing - metadataHeight));
  const metadataTop = portrait ? Math.max(header, height - 16 - metadataHeight) : cardTop + cardSide + metadataSpacing;
  return {
    width, height, portrait,
    metadataWidth: portrait ? Math.max(0, width - contentInset * 2) : Math.min(Math.max(0, width - contentInset * 2), cardSide),
    cardSide, cardTop, metadataTop,
    videoWidth: portrait ? width : cardSide,
    videoHeight: portrait ? height : cardSide,
    videoTop: portrait ? 0 : cardTop,
  };
}

export interface VideoSize { width: number; height: number }
/**
 * The cover is a square card until a *ready* video frame says otherwise. Reduced motion
 * never leaves the static square poster, even if a portrait frame had been reported.
 */
export function sidebarArtworkPresentation(ready: VideoSize | null, reducedMotion: boolean): { tall: boolean; showVideo: boolean } {
  const showVideo = ready !== null && !reducedMotion;
  return { showVideo, tall: showVideo && ready.height > ready.width };
}

export interface HeroScroll {
  offset: number; progress: number; quantized: number;
  /** The hero (cover) still intersects the viewport. */
  heroVisible: boolean;
  /** Within 5 % of the initial position: video may run. A brief nudge past it suspends, never unmounts. */
  motionActive: boolean;
}
/** `SidebarArtworkScrollState.evaluateScroll` without the recommendation-loading side effects. */
export function heroScroll(offsetY: number, upperHeight: number): HeroScroll {
  const offset = Number.isFinite(offsetY) ? Math.max(0, offsetY) : 0;
  const upper = Math.max(1, Number.isFinite(upperHeight) ? upperHeight : 1);
  const progress = Math.min(Math.max(offset / upper, 0), 1);
  return {
    offset, progress,
    quantized: Math.min(1, Math.max(0, Math.round(progress * 50) / 50)),
    heroVisible: offset < upper,
    motionActive: progress <= 0.05,
  };
}
/**
 * Mac `suspended: !isMotionVisible || panel != .artwork`. Suspension pauses the video and starts the
 * (30 s) idle release inside the artwork controller; the element and its player identity stay mounted.
 */
export function sidebarMotionSuspended(input: { panelActive: boolean; scroll: HeroScroll; reducedMotion: boolean }): boolean {
  return !input.panelActive || input.reducedMotion || !input.scroll.heroVisible || !input.scroll.motionActive;
}

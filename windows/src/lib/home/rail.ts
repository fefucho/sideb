/**
 * Geometry of the Home featured rails (Speed Dial and albums/playlists).
 *
 * Final macOS state (`HomeFeaturedLayout`, `HomeFeaturedRailViewport`): cards keep one fixed size
 * at every window width, so resizing only reveals more or fewer cards and never changes a row
 * height. Everything here is pure so it can be tested without a DOM.
 */
export const FEATURED = {
  /** Leading inset of the rails and headings. */
  inset: 28,
  /** Air between the Speed Dial block and the collections block. */
  sectionGap: 30,
  headerHeight: 38,
  /** Between a heading and its rail. */
  contentGap: 8,
  /** Between the featured block and the next feed section. */
  bottomGap: 20,
  songWidth: 190,
  songHeight: 126,
  songGap: 12,
  maxSongRows: 3,
  maxSongs: 27,
  albumWidth: 176,
  /** Square artwork, then title, creator and one detail line. */
  albumTextHeight: 64,
  albumGap: 14,
  /** Candidate pool for albums/playlists. The rails only fetch metadata for what is on screen. */
  capacity: 6,
  /** The «Ver todo» sheet uses 180 pt cards. */
  sheetCardWidth: 180,
  sheetGap: 14,
  /** Edge fades and floating arrows only exist where content is out of view. */
  fadeWidth: 44,
} as const;

export interface FeaturedLayout {
  rows: number;
  songGridHeight: number;
  albumCardHeight: number;
  albumContentHeight: number;
  songPanelHeight: number;
  albumPanelHeight: number;
  totalHeight: number;
}

/** `HomeFeaturedLayout.init`: rows follow the song count (at most three). */
export function featuredLayout(hasSongs: boolean, hasCollections: boolean, songCount = 9): FeaturedLayout {
  const rows = hasSongs ? Math.min(FEATURED.maxSongRows, Math.max(0, Math.floor(songCount))) : 0;
  const songGridHeight = rows * FEATURED.songHeight + Math.max(0, rows - 1) * FEATURED.songGap;
  const albumCardHeight = FEATURED.albumWidth + FEATURED.albumTextHeight;
  const albumContentHeight = hasCollections ? albumCardHeight : 0;
  const header = FEATURED.headerHeight + FEATURED.contentGap;
  const songPanelHeight = hasSongs ? header + songGridHeight : 0;
  const albumPanelHeight = hasCollections ? header + albumContentHeight : 0;
  const totalHeight = songPanelHeight + albumPanelHeight + (hasSongs && hasCollections ? FEATURED.sectionGap : 0)
    + (hasSongs || hasCollections ? FEATURED.bottomGap : 0);
  return { rows, songGridHeight, albumCardHeight, albumContentHeight, songPanelHeight, albumPanelHeight, totalHeight };
}

export interface RailWindow { start: number; end: number; columns: number }

/** Columns that must be mounted for an offset: the visible ones plus one column of margin on each side. */
export function railWindow(count: number, rows: number, stride: number, offset: number, viewport: number): RailWindow {
  const perColumn = Math.max(1, Math.floor(rows));
  const columns = Math.ceil(Math.max(0, count) / perColumn);
  if (stride <= 0) return { start: 0, end: 0, columns };
  const start = Math.max(0, Math.floor(Math.max(0, offset) / stride) - 1);
  const end = Math.min(columns, Math.ceil((Math.max(0, offset) + Math.max(0, viewport)) / stride) + 1);
  return { start, end: Math.max(start, end), columns };
}

/** Width of the scrollable content: columns minus the trailing gap. */
export function railContentWidth(columns: number, stride: number, gap: number): number {
  return Math.max(0, columns * stride - (columns > 0 ? gap : 0));
}

/**
 * Ids of the cards whose bounds intersect the viewport, excluding the gaps between them
 * (`HomeFeaturedRailViewport.visibleIDs`). `offset` is relative to the first column.
 */
export function railVisibleIds(ids: string[], itemWidth: number, rows: number, spacing: number, offset: number, width: number): string[] {
  if (width <= 0 || itemWidth <= 0 || rows <= 0) return [];
  const stride = itemWidth + spacing;
  const first = Math.max(0, Math.floor(Math.max(0, offset) / stride)) * rows;
  const end = Math.min(ids.length, Math.ceil((Math.max(0, offset) + width) / stride) * rows);
  if (first >= end) return [];
  const visible: string[] = [];
  for (let index = first; index < end; index++) {
    const x = Math.floor(index / rows) * stride;
    if (x + itemWidth > offset && x < offset + width) visible.push(ids[index]);
  }
  return visible;
}

/** Id of the first card of the first (possibly partial) column, used to anchor reloads. */
export function railAnchorId(ids: string[], rows: number, stride: number, offset: number): string | null {
  if (stride <= 0 || !ids.length) return null;
  return ids[Math.floor(Math.max(0, offset) / stride) * Math.max(1, rows)] ?? null;
}

/** Offset of the column that now holds `anchor`, or null when it left the list. */
export function railAnchorOffset(ids: string[], anchor: string | null, rows: number, stride: number): number | null {
  if (anchor === null) return null;
  const index = ids.indexOf(anchor);
  return index < 0 ? null : Math.floor(index / Math.max(1, rows)) * stride;
}

/** Indexes of the cards of a wrapped grid that intersect a vertical viewport. */
export function gridVisibleIndexes(count: number, columns: number, rowHeight: number, gap: number, top: number, viewport: number): number[] {
  if (count <= 0 || columns <= 0 || rowHeight <= 0 || viewport <= 0) return [];
  const stride = rowHeight + gap;
  const firstRow = Math.max(0, Math.floor(Math.max(0, top) / stride));
  const lastRow = Math.ceil((Math.max(0, top) + viewport) / stride);
  const result: number[] = [];
  for (let index = firstRow * columns; index < Math.min(count, lastRow * columns); index++) {
    const y = Math.floor(index / columns) * stride;
    if (y + rowHeight > top && y < top + viewport) result.push(index);
  }
  return result;
}

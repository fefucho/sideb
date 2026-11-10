import { horizontalOffset } from '../horizontal/scroll';
import type { ArtistCarouselDto } from '../types';

/** Geometry shared by the profile viewport and its tests; mirrors the Mac shelf (fixed card cell, 16 pt gap, 32 pt inset). */
export const ARTIST_CARD_WIDTH = 144;
export const ARTIST_CARD_GAP = 16;
export const ARTIST_CARD_STRIDE = ARTIST_CARD_WIDTH + ARTIST_CARD_GAP;
export const ARTIST_SHELF_INSET = 32;
/** Tallest MediaCard cell: square artwork + two title lines + one credit line (measured in Chromium). */
export const ARTIST_CARD_HEIGHT = 216;
const HEADING_HEIGHT = 30, HEADING_GAP = 14, SHELF_SPACING = 32, SCROLLBAR_ROOM = 8;
/** Cards kept mounted beyond each horizontal edge. */
export const ARTIST_CARD_OVERSCAN = 2;

/** Empty sections never render; the order and titles are the provider's. */
export const artistShelves = (sections: ArtistCarouselDto[]): ArtistCarouselDto[] => sections.filter(section => section.items.length > 0);
export const artistShelfHeight = (): number => HEADING_HEIGHT + HEADING_GAP + ARTIST_CARD_HEIGHT + SCROLLBAR_ROOM + SHELF_SPACING;
/** Identity for restoring a shelf offset: title + position survives data refreshes of the same artist. */
export const artistShelfKey = (section: ArtistCarouselDto, index: number): string => `${index}:${section.title}:${section.moreBrowseId ?? ''}:${section.moreParams ?? ''}`;

export interface ArtistShelfWindow { start: number; end: number; before: number; after: number; width: number }
/** Cards intersecting the horizontal viewport plus overscan; spacers keep the scroll extent identical to a full list. */
export function artistShelfWindow(count: number, scrollLeft: number, viewport: number, rtl = false): ArtistShelfWindow {
  const width = count <= 0 ? 0 : ARTIST_SHELF_INSET * 2 + count * ARTIST_CARD_STRIDE - ARTIST_CARD_GAP;
  if (count <= 0) return { start: 0, end: 0, before: 0, after: 0, width };
  const maximum = Math.max(0, width - Math.max(0, viewport));
  const left = horizontalOffset(scrollLeft, maximum, rtl);
  const first = Math.floor((left - ARTIST_SHELF_INSET) / ARTIST_CARD_STRIDE);
  const last = Math.ceil((left + Math.max(0, viewport) - ARTIST_SHELF_INSET) / ARTIST_CARD_STRIDE);
  const start = Math.max(0, Math.min(count, first - ARTIST_CARD_OVERSCAN));
  const end = Math.max(start, Math.min(count, last + ARTIST_CARD_OVERSCAN));
  return { start, end, before: start * ARTIST_CARD_STRIDE, after: (count - end) * ARTIST_CARD_STRIDE, width };
}

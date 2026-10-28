export type ContentRating = 'explicit' | 'clean' | 'unknown';
export interface ContentMetadata { contentRating?: unknown; explicit?: boolean }

/** Legacy false/missing means unavailable evidence, never a confirmed clean edition. */
export function contentRating(item: ContentMetadata | null | undefined): ContentRating {
  if (item?.contentRating === 'explicit' || item?.contentRating === 'clean') return item.contentRating;
  return item?.explicit === true ? 'explicit' : 'unknown';
}

/** Merge only evidence for the same provider identity; a container is not a track. */
export function ratingForIdentity(current: ContentMetadata & {videoId:string}, candidate?: ContentMetadata & {videoId:string}): ContentRating {
  const rating = contentRating(current);
  return rating === 'unknown' && candidate?.videoId === current.videoId ? contentRating(candidate) : rating;
}

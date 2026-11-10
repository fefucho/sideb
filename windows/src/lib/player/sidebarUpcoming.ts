import type { QueueEntryDto, QueueStateDto } from '../types';

export interface SidebarUpcomingItem {
  /** Native queue occurrence; `entry.entryId` is its identity (duplicates stay distinct). */
  entry: QueueEntryDto;
  /** Global queue index to hand to `playQueueIndex`. */
  queueIndex: number;
}
/**
 * "Up next": the (at most) two committed occurrences after the current one (`SidebarUpcomingOccurrence.preview`).
 * Reading never promotes radio recommendations, extends a source or builds a replacement queue. The window can be
 * sparse (`queueIndex`), so a missing occurrence ends the preview instead of being invented.
 */
export function sidebarUpcomingPreview(queue: QueueStateDto | null | undefined, limit = 2): SidebarUpcomingItem[] {
  const items = queue?.items;
  const local = queue?.currentIndex;
  if (!items || local === null || local === undefined) return [];
  const current = items[local];
  if (!current) return [];
  const currentIndex = current.queueIndex ?? local;
  const total = queue.totalCount ?? Number.POSITIVE_INFINITY;
  const result: SidebarUpcomingItem[] = [];
  for (let step = 1; step <= limit; step++) {
    const wanted = currentIndex + step;
    if (wanted >= total) break;
    let entry = items[local + step];
    if (!entry || (entry.queueIndex ?? local + step) !== wanted) entry = items.find((candidate, index) => (candidate.queueIndex ?? index) === wanted)!;
    if (!entry) break;
    result.push({ entry, queueIndex: wanted });
  }
  return result;
}
export function formatSidebarDuration(seconds: number | null | undefined): string {
  if (typeof seconds !== 'number' || !Number.isFinite(seconds) || seconds < 0) return '';
  const whole = Math.floor(seconds);
  const hours = Math.floor(whole / 3600), minutes = Math.floor((whole % 3600) / 60), rest = whole % 60;
  return hours ? `${hours}:${String(minutes).padStart(2, '0')}:${String(rest).padStart(2, '0')}` : `${minutes}:${String(rest).padStart(2, '0')}`;
}

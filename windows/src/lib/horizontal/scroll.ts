/** Logical offsets: Chromium's RTL scrollers expose negative scrollLeft. */
export const horizontalOffset = (left: number, max: number, rtl = false): number =>
  Math.max(0, Math.min(max, rtl ? -left : left));

export interface HorizontalPage {
  position: number;
  extent: number;
  maximum: number;
  direction: -1 | 1;
  stride?: number;
  count?: number;
  startAt?: (index: number) => number;
}

/** Read only the item boundaries around the next viewport, including mixed widths.
 * Virtual lists provide a stride and never measure their offscreen children. */
export function horizontalPageTarget({ position, extent, maximum, direction, stride, count = 0, startAt }: HorizontalPage): number {
  const current = Math.max(0, Math.min(maximum, position));
  const width = Math.max(1, extent);
  const raw = current + direction * width;
  let target = raw;
  if (stride && Number.isFinite(stride) && stride > 0 && width >= stride) {
    const columns = Math.max(1, Math.floor(width / stride));
    target = (direction > 0 ? Math.floor((current + .5) / stride) + columns : Math.ceil((current - .5) / stride) - columns) * stride;
  } else if (!stride && startAt && count > 0) {
    // Find the partially visible boundary, rather than skipping its item.
    let lo = 0, hi = count;
    while (lo < hi) {
      const mid = (lo + hi) >>> 1;
      if (startAt(mid) < raw || (direction > 0 && startAt(mid) <= raw + .5)) lo = mid + 1;
      else hi = mid;
    }
    const index = direction > 0 ? lo - 1 : lo;
    if (index >= 0 && index < count) {
      const boundary = startAt(index);
      if (direction * (boundary - current) > .5) target = boundary;
    }
  }
  return Math.max(0, Math.min(maximum, target));
}

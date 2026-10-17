/** Tab controls activate and focus together; unrelated keys retain native behavior. */
export function segmentKeyIndex(key: string, current: number, count: number, rtl = false): number | null {
  if (!count) return null;
  if (key === 'Home') return 0;
  if (key === 'End') return count - 1;
  const direction = key === 'ArrowRight' ? 1 : key === 'ArrowLeft' ? -1 : 0;
  if (!direction) return null;
  return (Math.max(current, 0) + (rtl ? -direction : direction) + count) % count;
}

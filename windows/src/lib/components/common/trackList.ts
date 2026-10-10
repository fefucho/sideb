/** Fixed-height row windows keep provider occurrence indices independent from the DOM. */
export function visibleTrackRange(count: number, top: number, height: number, rowHeight = 52, overscan = 8): [number, number] {
  const start = Math.max(0, Math.min(count, Math.floor(top / rowHeight) - overscan));
  return [start, Math.min(count, Math.max(start, Math.ceil((top + height) / rowHeight) + overscan))];
}

/** Retain focused/dragged rows even when scrolling, without mounting the interval between them. */
export function trackSegments(count: number, range: [number, number], pinned: number[]): [number, number][] {
  const segments: [number, number][] = [range, ...pinned.filter(index => index >= 0 && index < count).map(index => [index, index + 1] as [number, number])];
  return segments.filter(([start, end]) => end > start).sort((a, b) => a[0] - b[0]).reduce<[number, number][]>((merged, segment) => {
    const previous = merged.at(-1);
    if (previous && segment[0] <= previous[1]) previous[1] = Math.max(previous[1], segment[1]);
    else merged.push([...segment]);
    return merged;
  }, []);
}

export function occurrenceKey(track: { videoId: string; setVideoId?: string | null }, index: number): string {
  return track.setVideoId ?? `${track.videoId}:${index}`;
}

export function selectionFor(keys: string[], current: Set<string>, index: number, anchor: number, shift: boolean, additive: boolean): { selected: Set<string>; anchor: number; activate: boolean } {
  if (shift) return { selected: new Set(keys.slice(Math.min(index, anchor), Math.max(index, anchor) + 1)), anchor, activate: false };
  if (additive) {
    const selected = new Set(current);
    if (selected.has(keys[index])) selected.delete(keys[index]); else selected.add(keys[index]);
    return { selected, anchor: index, activate: false };
  }
  return { selected: new Set([keys[index]]), anchor: index, activate: true };
}

export function normalizeHistoryDate(title: string): string {
  const trimmed = title.trim();
  if (/^(today|hoy)$/i.test(trimmed)) return 'Hoy';
  if (/^(yesterday|ayer)$/i.test(trimmed)) return 'Ayer';
  const names: Record<string, string> = { Monday: 'Lunes', Tuesday: 'Martes', Wednesday: 'Miércoles', Thursday: 'Jueves', Friday: 'Viernes', Saturday: 'Sábado', Sunday: 'Domingo', January: 'enero', February: 'febrero', March: 'marzo', April: 'abril', May: 'mayo', June: 'junio', July: 'julio', August: 'agosto', September: 'septiembre', October: 'octubre', November: 'noviembre', December: 'diciembre' };
  return trimmed.replace(/\b(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|January|February|March|April|May|June|July|August|September|October|November|December)\b/g, name => names[name]);
}

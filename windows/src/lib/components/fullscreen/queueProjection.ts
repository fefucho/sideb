import type { QueueEntryDto, QueueStateDto } from '$lib/types';

export type QueueSectionKind = 'previous' | 'current' | 'upcoming' | 'recommendations';
export interface QueueSection {
  kind: QueueSectionKind;
  start: number;
  end: number;
  headerSlot: number;
  firstTrackSlot: number;
  trackCount: number;
  headerSection: 'current' | 'recommendations' | null;
  entries: QueueEntryDto[];
  byIndex: Map<number, { entry: QueueEntryDto; localIndex: number }>;
}
export type QueueProjectedRow = { kind: 'header'; section: QueueSectionKind; slot: number }
  | { kind: 'track'; section: QueueSectionKind; entry: QueueEntryDto; queueIndex: number | null; queueLocalIndex: number | null; slot: number };

/** Uses sparse native queue indexes; missing tracks leave virtual space, never copied placeholder rows. */
export function queueSections(queue: QueueStateDto): QueueSection[] {
  const items = queue.items;
  const currentLocal = queue.currentIndex;
  const activeEntry = currentLocal == null ? null : items[currentLocal] ?? null;
  const current = currentLocal == null ? null : activeEntry?.queueIndex ?? currentLocal;
  const total = queue.totalCount ?? Math.max(items.length, ...items.map((entry, index) => (entry.queueIndex ?? index) + 1));
  const recommendations = queue.recommendations ?? [];
  const byIndex = new Map<number, { entry: QueueEntryDto; localIndex: number }>();
  items.forEach((entry, localIndex) => byIndex.set(entry.queueIndex ?? localIndex, { entry, localIndex }));
  const sections: QueueSection[] = [];
  let slot = 0;
  const add = (kind: QueueSectionKind, entries: QueueEntryDto[], start: number, end: number,
    headerSection: 'current' | 'recommendations' | null = null, lookup = byIndex) => {
    const trackCount = Math.max(0, end - start);
    if (!trackCount && !headerSection) return;
    const headerSlot = headerSection ? slot++ : -1;
    sections.push({ kind, start, end, headerSlot, headerSection, firstTrackSlot: slot, trackCount, entries, byIndex: lookup });
    slot += trackCount;
  };
  if (current !== null && current >= 0 && current < total) {
    if (current > 0) add('previous', items, 0, current, 'current');
    add('current', items, current, current + 1, current === 0 ? 'current' : null);
    add('upcoming', items, current + 1, total);
  } else if (total > 0) {
    add('upcoming', items, 0, total, 'current');
  }
  if (recommendations.length) {
    const recommendationLookup = new Map(recommendations.map((entry, index) => [index, { entry, localIndex: index }]));
    add('recommendations', recommendations, 0, recommendations.length, 'recommendations', recommendationLookup);
  }
  return sections;
}

export function queueRowCount(sections: QueueSection[]): number {
  return sections.reduce((count, section) => count + (section.headerSlot >= 0 ? 1 : 0) + section.trackCount, 0);
}

export function queueRowAt(sections: QueueSection[], slot: number): QueueProjectedRow | null {
  for (const section of sections) {
    if (slot >= 0 && slot === section.headerSlot && section.headerSection) return { kind: 'header', section: section.headerSection, slot };
    const index = section.start + slot - section.firstTrackSlot;
    if (slot < section.firstTrackSlot || slot >= section.firstTrackSlot + section.trackCount
      || index < section.start || index >= section.end) continue;
    const found = section.byIndex.get(index);
    if (!found) return null;
    return { kind: 'track', section: section.kind, entry: found.entry,
      queueIndex: section.kind === 'recommendations' ? null : index,
      queueLocalIndex: section.kind === 'recommendations' ? null : found.localIndex, slot };
  }
  return null;
}

export function queueIndexAtSlot(sections: QueueSection[], slot: number): number | null {
  for (const section of sections) {
    if (slot >= section.firstTrackSlot && slot < section.firstTrackSlot + section.trackCount) {
      return section.kind === 'recommendations' ? null : section.start + slot - section.firstTrackSlot;
    }
  }
  return null;
}

export function queueSlotForEntry(sections: QueueSection[], entryId: string): number | null {
  for (const section of sections) {
    for (const [index, value] of section.byIndex) {
      if (index >= section.start && index < section.end && value.entry.entryId === entryId) {
        return section.firstTrackSlot + index - section.start;
      }
    }
  }
  return null;
}

/** Returns a focused occurrence only when the command added exactly one new native entry. */
export function promotedEntryId(previousIds: ReadonlySet<string>, queue: QueueStateDto): string | null {
  let added: string | null = null;
  for (const item of queue.items) {
    if (previousIds.has(item.entryId)) continue;
    if (added !== null) return null;
    added = item.entryId;
  }
  return added;
}

/** Resolves a dragged row boundary to the stable occurrence that should follow the promoted entry. */
export function queueDropDestination(items: QueueEntryDto[], targetEntryId: string, after: boolean, totalCount = items.length): string | null | undefined {
  const index = items.findIndex(entry => entry.entryId === targetEntryId);
  if (index < 0) return undefined;
  if (!after) return targetEntryId;
  const nextIndex = (items[index].queueIndex ?? index) + 1;
  if (nextIndex >= totalCount) return null;
  return items.find(entry => (entry.queueIndex ?? items.indexOf(entry)) === nextIndex)?.entryId;
}

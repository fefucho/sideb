// Port of JamQueueMapping.swift / JamQueueEdit: index bookkeeping between the Jam queue (every
// upcoming track, 0 = plays next) and the rows mirrored into the native queue (only the tracks
// that have a YouTube Music match). Pure value logic.

export const JAM_ENTRY_PREFIX = 'jam|';

/** Occurrence number of each URI in order: the n-th time a URI appears gets n. */
export function occurrences(uris: string[]): number[] {
  const seen = new Map<string, number>();
  return uris.map(uri => {
    const n = seen.get(uri) ?? 0;
    seen.set(uri, n + 1);
    return n;
  });
}

/** Native queue entry id of a Jam occurrence; deterministic and distinct for duplicates. */
export const jamEntryId = (uri: string, occurrence: number) => `${JAM_ENTRY_PREFIX}${uri}|${occurrence}`;
/** `JamTrackView.key` of a Jam occurrence. */
export const jamTrackKey = (uri: string, occurrence: number) => `${uri}#${occurrence}`;
export const isJamEntryId = (entryId: string | null | undefined) => !!entryId && entryId.startsWith(JAM_ENTRY_PREFIX);

/** `uri` of a jam entry id (`jam|<uri>|<n>`), or null. */
export function uriOfEntryId(entryId: string): string | null {
  if (!isJamEntryId(entryId)) return null;
  const body = entryId.slice(JAM_ENTRY_PREFIX.length);
  const cut = body.lastIndexOf('|');
  return cut > 0 ? body.slice(0, cut) : null;
}

/** Keys and entry ids for `[current, ...queue]` counted together, so a repeat of the current track is occurrence 1. */
export function identities(current: string | null, queue: string[]): { current: { key: string; entryId: string } | null; queue: { key: string; entryId: string }[] } {
  const all = current === null ? queue : [current, ...queue];
  const counts = occurrences(all);
  const make = (index: number) => ({ key: jamTrackKey(all[index], counts[index]), entryId: jamEntryId(all[index], counts[index]) });
  const offset = current === null ? 0 : 1;
  return {
    current: current === null ? null : make(0),
    queue: queue.map((_, index) => make(index + offset))
  };
}

export class JamQueueMapping {
  /** Jam indices of the matched tracks, ascending; `matchedJamIndices[row]` is that row's Jam index. */
  readonly matchedJamIndices: number[];
  readonly jamCount: number;

  /** `matched[i]` tells whether the Jam track at index `i` has a mirrored row. */
  constructor(matched: boolean[]) {
    this.jamCount = matched.length;
    this.matchedJamIndices = matched.flatMap((flag, index) => flag ? [index] : []);
  }

  get rowCount(): number { return this.matchedJamIndices.length; }

  jamIndexForRow(row: number): number | null { return this.matchedJamIndices[row] ?? null; }

  rowForJamIndex(index: number): number | null {
    const row = this.matchedJamIndices.indexOf(index);
    return row < 0 ? null : row;
  }

  /** Jam index at which a track dropped before `row` must be inserted. A row past the end means "after everything". */
  insertionJamIndex(row: number): number {
    if (row < 0) return 0;
    return this.jamIndexForRow(row) ?? this.jamCount;
  }

  /** Jam `move` for dragging mirrored row `from` so that it ends at mirrored row `to`. */
  move(from: number, to: number): { from: number; to: number } | null {
    const source = this.jamIndexForRow(from);
    const target = this.jamIndexForRow(to);
    if (from === to || source === null || target === null || source === target) return null;
    return { from: source, to: target };
  }

  /**
   * Jam `move` that puts the track at Jam index `from` right before the track at Jam index
   * `before` (`null` = after the last mirrored row). `to` is the final index after the move.
   */
  moveBefore(from: number, before: number | null): { from: number; to: number } | null {
    const lastMatched = this.matchedJamIndices.at(-1);
    const slot = before ?? (lastMatched === undefined ? null : lastMatched + 1);
    if (slot === null) return null;
    const to = from < slot ? slot - 1 : slot;
    return to === from ? null : { from, to };
  }
}

/** A change requested on the Jam queue. Spotify only acknowledges it; the next queue the plugin reports decides. */
export type JamQueueEdit =
  | { action: 'add'; uri: string }
  | { action: 'insert'; uri: string; index: number }
  | { action: 'move'; from: number; to: number }
  | { action: 'remove'; index: number };

const countOf = (uri: string, list: string[]) => list.filter(entry => entry === uri).length;

/** Plugin command for this edit, built against the queue revision the indices refer to. */
export function editCommand(edit: JamQueueEdit, revision: string | null, requestId: string): Record<string, unknown> {
  const message: Record<string, unknown> = { ...edit, type: 'command', requestId };
  if (revision !== null) message.revision = revision;
  return message;
}

/** False when the edit points outside `queue` (nothing is sent). */
export function editIsValid(edit: JamQueueEdit, queue: string[]): boolean {
  switch (edit.action) {
    case 'add': return edit.uri !== '';
    case 'insert': return edit.uri !== '' && edit.index >= 0 && edit.index <= queue.length;
    case 'move': return edit.from >= 0 && edit.from < queue.length && edit.to >= 0 && edit.to < queue.length && edit.from !== edit.to;
    case 'remove': return edit.index >= 0 && edit.index < queue.length;
  }
}

/** Whether `next` shows the effect of this edit applied to `old`; tolerant of other participants' changes. */
export function editIsSatisfied(edit: JamQueueEdit, old: string[], next: string[]): boolean {
  switch (edit.action) {
    case 'add': return countOf(edit.uri, next) > countOf(edit.uri, old);
    case 'insert': {
      if (countOf(edit.uri, next) <= countOf(edit.uri, old)) return false;
      return edit.index < next.length ? next[edit.index] === edit.uri : next.at(-1) === edit.uri;
    }
    case 'move': {
      if (edit.from >= old.length || edit.to >= next.length || next.length === old.length && next.every((uri, i) => uri === old[i])) return false;
      return next[edit.to] === old[edit.from];
    }
    case 'remove': {
      if (edit.index >= old.length) return false;
      return countOf(old[edit.index], next) < countOf(old[edit.index], old);
    }
  }
}

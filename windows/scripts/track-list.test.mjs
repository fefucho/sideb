import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/components/common/trackList.ts', import.meta.url), 'utf8');
const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { visibleTrackRange, trackSegments, occurrenceKey, selectionFor, normalizeHistoryDate } = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);

test('large-list windows preserve bounded row count and exact total spacer height at middle and end', () => {
  for (const top of [0, 52 * 485, 52 * 999, 52 * 1100]) {
    const range = visibleTrackRange(1000, top, 520);
    const segments = trackSegments(1000, range, []);
    const rendered = segments.reduce((sum, [start, end]) => sum + end - start, 0);
    assert.ok(rendered <= 27);
    assert.ok(range[0] >= 0 && range[1] <= 1000);
    let previousEnd = 0;
    let total = 0;
    for (const [start, end] of segments) { total += (start - previousEnd) * 52 + (end - start) * 52; previousEnd = end; }
    total += (1000 - previousEnd) * 52;
    assert.equal(total, 52000);
  }
});

test('focused and dragged occurrences remain mounted without filling distant gaps or duplicating the viewport', () => {
  assert.deepEqual(trackSegments(1000, [500, 525], [0, 510, 999, 999, -1, 1000]), [[0, 1], [500, 525], [999, 1000]]);
  assert.deepEqual(trackSegments(0, [0, 0], [-1]), []);
  assert.deepEqual(trackSegments(20, [5, 10], [4, 10]), [[4, 11]]);
  assert.deepEqual(visibleTrackRange(1000, 4800, 480, 48, 6), [94, 116]);
});

test('focus and drag pins follow provider occurrences after reordering rather than retaining stale row indices', () => {
  const original = Array.from({length: 1000}, (_, index) => ({videoId: 'duplicate', setVideoId: `occ-${index}`}));
  const focus = occurrenceKey(original[0], 0), drag = occurrenceKey(original[999], 999);
  const reordered = [...original.slice(1, 999), original[999], original[0]];
  const keys = reordered.map(occurrenceKey);
  const segments = trackSegments(1000, [450, 475], [keys.indexOf(focus), keys.indexOf(drag)]);
  assert.deepEqual(segments, [[450, 475], [998, 1000]]);
  const rendered = segments.flatMap(([start, end]) => keys.slice(start, end));
  assert.ok(rendered.includes(focus)); assert.ok(rendered.includes(drag));
  assert.equal(rendered.length, 27);
});

test('duplicate songs keep separate selected occurrences and modifiers never trigger playback', () => {
  const same = { videoId: 'same' };
  const keys = [occurrenceKey(same, 0), occurrenceKey(same, 1), occurrenceKey({ ...same, setVideoId: 'provider-occurrence' }, 2)];
  assert.equal(new Set(keys).size, 3);
  const initial = selectionFor(keys, new Set(), 0, 0, false, false);
  assert.equal(initial.activate, true);
  const additive = selectionFor(keys, initial.selected, 2, initial.anchor, false, true);
  assert.equal(additive.activate, false);
  assert.deepEqual([...additive.selected], [keys[0], keys[2]]);
  const range = selectionFor(keys, additive.selected, 0, additive.anchor, true, false);
  assert.equal(range.activate, false);
  assert.deepEqual([...range.selected], keys);
  const removed = selectionFor(keys, additive.selected, 2, additive.anchor, false, true);
  assert.deepEqual([...removed.selected], [keys[0]]);
});

test('history normalizes provider date titles and preserves already localized or unknown dates', () => {
  assert.equal(normalizeHistoryDate(' Today '), 'Hoy');
  assert.equal(normalizeHistoryDate('yesterday'), 'Ayer');
  assert.equal(normalizeHistoryDate('Monday, October 5'), 'Lunes, octubre 5');
  assert.equal(normalizeHistoryDate('Viernes, 2 de octubre'), 'Viernes, 2 de octubre');
  assert.equal(normalizeHistoryDate('Mayhem mix'), 'Mayhem mix');
});

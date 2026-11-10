import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFile } from 'node:fs/promises';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/components/fullscreen/queueProjection.ts', import.meta.url), 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const moduleUrl = `data:text/javascript;base64,${Buffer.from(js).toString('base64')}`;
const { promotedEntryId, queueDropDestination, queueIndexAtSlot, queueSections, queueRowAt, queueRowCount, queueSlotForEntry } = await import(moduleUrl);
const trackSource = await readFile(new URL('../src/lib/components/common/trackList.ts', import.meta.url), 'utf8');
const trackJS = ts.transpileModule(trackSource, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { visibleTrackRange, trackSegments } = await import(`data:text/javascript;base64,${Buffer.from(trackJS).toString('base64')}`);
const entry = entryId => ({ entryId, videoId: entryId, title: entryId, artists: '', thumbnail: null, duration: 4 });

test('continuous projection has only two headers while preserving occurrence indices', () => {
  const items = Array.from({ length: 2000 }, (_, index) => entry(`e${index}`));
  const recommendations = [entry('r1'), entry('r2')];
  const sections = queueSections({ items, currentIndex: 1500, recommendations });
  assert.equal(sections[0].entries, items, 'previous rows reference native data');
  assert.equal(sections.at(-1).entries, recommendations);
  assert.equal(queueRowCount(sections), items.length + recommendations.length + 2);
  const headers = Array.from({length: queueRowCount(sections)}, (_, slot) => queueRowAt(sections, slot)).filter(row => row?.kind === 'header');
  assert.deepEqual(headers.map(row => row.section), ['current', 'recommendations']);
  const current = queueRowAt(sections, 1501);
  assert.deepEqual({ kind: current.kind, id: current.entry.entryId, index: current.queueIndex }, { kind: 'track', id: 'e1500', index: 1500 });
  assert.equal(queueRowAt(sections, 1500).entry.entryId, 'e1499');
  assert.equal(queueRowAt(sections, 1502).entry.entryId, 'e1501');
  const recSlot = queueSlotForEntry(sections, 'r2');
  assert.equal(queueRowAt(sections, recSlot).queueIndex, null);
  assert.equal(queueRowAt(sections, recSlot).entry.entryId, 'r2');
});

test('ten thousand previous tracks remain scrollable as virtual slots without mounting them', () => {
  const items = Array.from({ length: 10002 }, (_, index) => entry(`p${index}`));
  const sections = queueSections({ items, currentIndex: 10000, recommendations: [] });
  assert.equal(queueRowCount(sections), 10003);
  assert.equal(queueRowAt(sections, 0).kind, 'header');
  assert.equal(queueRowAt(sections, 1).entry.entryId, 'p0');
  assert.equal(queueRowAt(sections, 10001).entry.entryId, 'p10000');
  assert.equal(queueRowAt(sections, 4980).section, 'previous');
  const segments = trackSegments(queueRowCount(sections), visibleTrackRange(queueRowCount(sections), 5000 * 48, 480, 48), [0, 10002]);
  assert.ok(segments.reduce((sum, [start, end]) => sum + end - start, 0) < 40);
});

test('radio without manual pending rows omits empty upcoming and has no empty category', () => {
  const sections = queueSections({ items: [entry('current')], currentIndex: 0, source: {kind:'radio'}, recommendations: [entry('r1')] });
  assert.deepEqual(Array.from({length: queueRowCount(sections)}, (_, slot) => queueRowAt(sections, slot)).map(row => row.kind === 'header' ? row.section : row.entry.entryId), ['current','current','recommendations','r1']);
  assert.equal(queueRowCount(queueSections({ items: [], currentIndex: null })), 0);
});

test('promotion focus resolves the new occurrence ID and declines ambiguous native diffs', () => {
  const oldIds = new Set(['existing-a', 'existing-b']);
  const promoted = { items: [entry('existing-a'), entry('new-occurrence')] };
  assert.equal(promotedEntryId(oldIds, promoted), 'new-occurrence');
  assert.equal(promotedEntryId(oldIds, { items: [entry('new-one'), entry('new-two')] }), null);
});

test('dragging a proposal to either side of a chosen occurrence preserves the exact destination occurrence', () => {
  const chosen = [entry('dup-a'), entry('dup-b'), entry('last')];
  assert.equal(queueDropDestination(chosen, 'dup-a', false), 'dup-a');
  assert.equal(queueDropDestination(chosen, 'dup-a', true), 'dup-b');
  assert.equal(queueDropDestination(chosen, 'last', true), null);
  assert.equal(queueDropDestination(chosen, 'missing', false), undefined);
});

test('sparse queue snapshot retains absolute virtual slots and maps each visible occurrence to local array index', () => {
  const queue = { items: [
    { ...entry('before-window'), queueIndex: 5000 },
    { ...entry('current'), queueIndex: 5001 },
    { ...entry('tail-manual'), queueIndex: 9999 },
  ], currentIndex: 1, totalCount: 10000, pendingCount: 4998, recommendations: [entry('radio-proposal')] };
  const sections = queueSections(queue);
  assert.equal(queueRowCount(sections), 10003);
  assert.equal(queueIndexAtSlot(sections, 5003), 5002);
  assert.equal(queueRowAt(sections, 5003), null, 'sparse native gaps do not materialize fake tracks');
  assert.deepEqual(queueRowAt(sections, 5002), { kind: 'track', section: 'current', entry: queue.items[1], queueIndex: 5001, queueLocalIndex: 1, slot: 5002 });
  const tailSlot = queueSlotForEntry(sections, 'tail-manual');
  assert.equal(queueRowAt(sections, tailSlot).queueIndex, 9999);
  assert.equal(queueRowAt(sections, tailSlot).queueLocalIndex, 2);
  assert.equal(queueIndexAtSlot(sections, queueSlotForEntry(sections, 'radio-proposal')), null);
});

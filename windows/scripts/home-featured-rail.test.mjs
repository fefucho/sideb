import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
// Expected values follow the Apple tests (HomeFeaturedPresentationTests), not a copy of the implementation.
const compile = text => ts.transpileModule(text,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const rail = await import(`data:text/javascript;base64,${Buffer.from(compile(await readFile(new URL('../src/lib/home/rail.ts',import.meta.url),'utf8'))).toString('base64')}`);
const { FEATURED, featuredLayout, railWindow, railContentWidth, railVisibleIds, railAnchorId, railAnchorOffset, gridVisibleIndexes } = rail;

test('featured layout: fixed card sizes, panels and gaps of the final Mac layout, independent of the window width', () => {
  assert.equal([FEATURED.songWidth, FEATURED.songHeight, FEATURED.albumWidth, FEATURED.albumTextHeight].join(), '190,126,176,64');
  const both = featuredLayout(true, true, 27);
  assert.equal(both.rows, 3);
  assert.equal(both.songGridHeight, 3 * 126 + 2 * 12);
  assert.equal(both.songPanelHeight, 448);
  assert.equal(both.albumCardHeight, 176 + 64);
  assert.equal(both.albumPanelHeight, 46 + both.albumCardHeight);
  assert.equal(both.totalHeight, both.songPanelHeight + both.albumPanelHeight + 30 + 20);
  assert.equal(featuredLayout(false, false).totalHeight, 0);
  assert.equal(featuredLayout(false, true).totalHeight, 46 + 240 + 20, 'no gap between blocks when only one exists');
  for (let count = 1; count <= 27; count++) {
    const rows = Math.min(3, count), layout = featuredLayout(true, true, count);
    assert.equal(layout.songGridHeight, rows * 126 + (rows - 1) * 12, `partial Speed Dial ${count} does not reserve empty rows`);
    assert.equal(layout.albumContentHeight, layout.albumCardHeight);
  }
});

test('visible metadata range follows the offset and excludes the gaps between cards', () => {
  const ids = Array.from({ length: 36 }, (_, index) => String(index));
  assert.deepEqual(railVisibleIds(ids, 180, 1, 14, 0, 400), ['0', '1', '2']);
  assert.deepEqual(railVisibleIds(ids, 180, 1, 14, 1940, 400), ['10', '11', '12']);
  assert.deepEqual(railVisibleIds(ids, 180, 1, 14, 181, 12), []);
  assert.deepEqual(railVisibleIds(ids, 180, 3, 12, 192, 180), ['3', '4', '5']);
  assert.deepEqual(railVisibleIds(ids, 180, 1, 14, 0, 0), []);
  // The leading inset places the first column after the viewport edge: offsets before the first card still find it.
  assert.deepEqual(railVisibleIds(ids, 176, 1, 14, -28, 400), ['0', '1']);
});

test('only the columns around the viewport are mounted, however many cards exist', () => {
  assert.deepEqual(railWindow(27, 3, 202, 0, 800), { start: 0, end: 5, columns: 9 });
  assert.deepEqual(railWindow(27, 3, 202, 800, 800), { start: 2, end: 9, columns: 9 });
  assert.deepEqual(railWindow(36, 1, 190, -28, 800), { start: 0, end: 6, columns: 36 });
  assert.deepEqual(railWindow(0, 1, 190, 0, 800), { start: 0, end: 0, columns: 0 });
  assert.equal(railContentWidth(9, 202, 12), 9 * 202 - 12);
  assert.equal(railContentWidth(0, 202, 12), 0);
  // A viewport 4x wider mounts more columns, not larger cards.
  assert.ok(railWindow(36, 1, 190, 0, 3200).end > railWindow(36, 1, 190, 0, 800).end);
});

test('the first visible card anchors the rail when the list is reloaded', () => {
  const ids = Array.from({ length: 12 }, (_, index) => `s${index}`);
  assert.equal(railAnchorId(ids, 3, 202, 0), 's0');
  assert.equal(railAnchorId(ids, 3, 202, 210), 's3', 'a partially scrolled column still anchors to its first row');
  assert.equal(railAnchorId(ids, 3, 202, 99999), null);
  assert.equal(railAnchorId([], 3, 202, 0), null);
  const inserted = ['new-a', 'new-b', 'new-c', ...ids];
  assert.equal(railAnchorOffset(ids, 's3', 3, 202), 202);
  assert.equal(railAnchorOffset(inserted, 's3', 3, 202), 2 * 202, 'three new cards add one column before the anchor');
  assert.equal(railAnchorOffset(ids.slice(6), 's3', 3, 202), null, 'a card that left the list gives no anchor');
  assert.equal(railAnchorOffset(ids, null, 3, 202), null);
});

test('the View all sheet reports only the cards inside its vertical viewport', () => {
  const rowHeight = 180 + 64;
  assert.deepEqual(gridVisibleIndexes(36, 4, rowHeight, 14, 0, 300), [0, 1, 2, 3, 4, 5, 6, 7]);
  assert.deepEqual(gridVisibleIndexes(36, 4, rowHeight, 14, 258, 244), [4, 5, 6, 7], 'a viewport exactly one row high shows one row');
  assert.deepEqual(gridVisibleIndexes(36, 4, rowHeight, 14, 300, 244), [4, 5, 6, 7, 8, 9, 10, 11]);
  assert.equal(gridVisibleIndexes(10, 4, rowHeight, 14, 0, 500).length, 8, 'the third row starts below 500');
  assert.equal(gridVisibleIndexes(10, 4, rowHeight, 14, 0, 800).length, 10);
  assert.deepEqual(gridVisibleIndexes(10, 0, rowHeight, 14, 0, 500), []);
  assert.deepEqual(gridVisibleIndexes(10, 4, rowHeight, 14, 0, 0), []);
});

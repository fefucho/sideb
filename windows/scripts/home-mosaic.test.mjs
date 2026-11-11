import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const compile = text => ts.transpileModule(text,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const load = async (file, replacements={}) => {let source=compile(await readFile(new URL(`../src/lib/${file}.ts`,import.meta.url),'utf8'));for(const [path,ref] of Object.entries(replacements)) source=source.replaceAll(`'${path}'`,JSON.stringify(ref));return `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;};
const { mosaicLayout, mosaicSeed, MOSAIC_ROWS } = await import(await load('home/mosaic'));
const ambientUrl = await load('home/ambient');
const { dominantColor, cssColor, coverColor, resetCoverColors } = await import(await load('home/coverColor',{'./ambient':ambientUrl,'$lib/images/artwork':'data:text/javascript,export const fallbackArtworkUrl=()=>null;'}));
const seeds = [0, 1, 7, 12345, 0xdeadbeef, 4294967295, mosaicSeed(['a','b','c'])];

test('layout covers every song once, inside the grid, without overlaps or holes', () => {
  for (let count = 0; count <= 60; count++) for (const seed of seeds) {
    const { cells, columns } = mosaicLayout(count, seed);
    assert.equal(cells.length, count);
    assert.deepEqual(cells.map(c => c.index), Array.from({length: count}, (_, i) => i));
    const grid = new Map();
    for (const c of cells) {
      assert.ok(c.row >= 0 && c.row + c.rows <= MOSAIC_ROWS && c.column >= 0, `bounds ${count}/${seed}`);
      assert.deepEqual([c.columns, c.rows], {small:[1,1], wide:[2,1], large:[2,2]}[c.size]);
      for (let x = c.column; x < c.column + c.columns; x++) for (let y = c.row; y < c.row + c.rows; y++) {
        assert.ok(!grid.has(`${x},${y}`), `overlap ${count}/${seed}`);
        grid.set(`${x},${y}`, c.index);
      }
    }
    const used = count ? Math.max(...cells.map(c => c.column + c.columns)) : 0;
    assert.equal(columns, used);
    if (count >= 3) for (let x = 0; x < columns - 1; x++) for (let y = 0; y < MOSAIC_ROWS; y++) assert.ok(grid.has(`${x},${y}`), `hole ${count}/${seed} at ${x},${y}`);
  }
});

test('empty and first-song rules', () => {
  assert.deepEqual(mosaicLayout(0, 5), {cells: [], columns: 0});
  assert.deepEqual(mosaicLayout(-3, 5), {cells: [], columns: 0});
  for (let count = 1; count <= 60; count++) for (const seed of seeds) assert.equal(mosaicLayout(count, seed).cells[0].size, 'large');
});

test('large pieces are spaced 1-3 columns apart and alternate top/bottom', () => {
  for (let count = 1; count <= 80; count++) for (const seed of seeds) {
    const larges = mosaicLayout(count, seed).cells.filter(c => c.size === 'large');
    larges.forEach((c, i) => {
      assert.equal(c.row, i % 2 === 0 ? 0 : 1, `alternation ${count}/${seed}`);
      if (i) { const gap = c.column - (larges[i-1].column + 2); assert.ok(gap >= 1 && gap <= 3, `gap ${gap} ${count}/${seed}`); }
    });
  }
});

test('layout is deterministic and varies with the seed', () => {
  assert.deepEqual(mosaicLayout(40, 99), mosaicLayout(40, 99));
  const shapes = new Set();
  for (let s = 0; s < 50; s++) shapes.add(JSON.stringify(mosaicLayout(40, mosaicSeed([`x${s}`]))));
  assert.ok(shapes.size > 10, `only ${shapes.size} distinct layouts`);
  const sizes = new Set(mosaicLayout(60, 3).cells.map(c => c.size));
  assert.ok(sizes.has('small') && sizes.has('large'));
});

test('mosaicSeed is stable, unsigned and order sensitive', () => {
  assert.equal(mosaicSeed(['a','b']), mosaicSeed(['a','b']));
  assert.notEqual(mosaicSeed(['a','b']), mosaicSeed(['b','a']));
  assert.notEqual(mosaicSeed(['ab']), mosaicSeed(['a','b']));
  for (const ids of [[], ['x'], ['a','b','c']]) { const v = mosaicSeed(ids); assert.ok(Number.isInteger(v) && v >= 0 && v <= 0xffffffff); }
  assert.equal(mosaicSeed([]), mosaicSeed([]));
});

const fill = (rgb, n = 1024) => Uint8ClampedArray.from({length: n * 4}, (_, i) => i % 4 === 3 ? 255 : rgb[i % 4]);
test('dominantColor picks the saturated hue and rejects neutrals', () => {
  const [r, g, b] = dominantColor(fill([220, 40, 40]));
  assert.ok(r > g && r > b);
  assert.equal(dominantColor(fill([128, 128, 128])), null);
  assert.equal(dominantColor(fill([0, 0, 0])), null);
  assert.equal(dominantColor(fill([255, 255, 255])), null);
  assert.equal(dominantColor([1, 2, 3]), null);
  assert.equal(dominantColor([]), null);
});

test('cssColor formats integers or null', () => {
  assert.equal(cssColor([10.4, 20.6, 255]), 'rgb(10 21 255)');
  assert.equal(cssColor(null), null);
});

test('coverColor never rejects', async () => {
  resetCoverColors();
  assert.equal(await coverColor(null, 's'), null);
  assert.equal(await coverColor('https://x/y.jpg', 's'), null); // sin DOM en Node
});

export type MosaicSize = 'small' | 'wide' | 'large';
export interface MosaicCell { index: number; column: number; row: number; columns: number; rows: number; size: MosaicSize }
export interface MosaicLayout { cells: MosaicCell[]; columns: number }
export const MOSAIC_ROWS = 3;

type Block = 'T' | 'B' | 'W' | 'S';
const NEED: Record<Block, number> = { T: 3, B: 3, W: 5, S: 3 };
const WIDTH: Record<Block, number> = { T: 2, B: 2, W: 2, S: 1 };
const GAPS: Block[][][] = [[], [['S']], [['S', 'S'], ['W']], [['S', 'S', 'S'], ['S', 'W'], ['W', 'S']]];

/** Hash determinista de 32 bits sin signo (FNV-1a) a partir de los IDs en orden. */
export function mosaicSeed(ids: string[]): number {
  let hash = 0x811c9dc5;
  const text = ids.join('\u001f');
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

function mulberry32(seed: number) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const cell = (index: number, column: number, row: number, size: MosaicSize): MosaicCell => ({
  index, column, row, size,
  columns: size === 'small' ? 1 : 2,
  rows: size === 'large' ? 2 : 1,
});

/** Disposición por bloques sin huecos para `count` canciones. */
export function mosaicLayout(count: number, seed: number): MosaicLayout {
  if (!Number.isFinite(count) || count <= 0) return { cells: [], columns: 0 };
  const total = Math.floor(count);
  const random = mulberry32(seed);
  const cells: MosaicCell[] = [];
  let next = 0, column = 0;
  let largeType: 'T' | 'B' = 'T';
  let queue: Block[] = ['T'];
  const emit = (block: Block, limit: number) => {
    const small = (c: number, r: number) => { if (next < limit) cells.push(cell(next++, c, r, 'small')); };
    if (block === 'T' || block === 'B') {
      cells.push(cell(next++, column, block === 'T' ? 0 : 1, 'large'));
      const row = block === 'T' ? 2 : 0;
      small(column, row); small(column + 1, row);
    } else if (block === 'W') {
      const wideRow = Math.floor(random() * MOSAIC_ROWS);
      cells.push(cell(next++, column, wideRow, 'wide'));
      for (let r = 0; r < MOSAIC_ROWS; r++) if (r !== wideRow) { small(column, r); small(column + 1, r); }
    } else {
      for (let r = 0; r < MOSAIC_ROWS; r++) small(column, r);
    }
    column += WIDTH[block];
  };
  while (next < total) {
    if (!queue.length) {
      // Tras una pieza grande: 1 a 3 columnas sin large, y luego la grande opuesta.
      const options = GAPS[1 + Math.floor(random() * 3)];
      queue = [...options[Math.floor(random() * options.length)]];
      largeType = largeType === 'T' ? 'B' : 'T';
      queue.push(largeType);
    }
    let block = queue.shift()!;
    const left = total - next;
    if (block !== 'T' && block !== 'B' && NEED[block] > left) block = 'S';
    if (block === 'T' && next === 0) emit('T', total);
    else if (NEED[block] <= left) emit(block, total);
    else { emit('S', total); break; }
  }
  return { cells, columns: column };
}

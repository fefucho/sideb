import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import vm from 'node:vm';
import ts from 'typescript';

test('ambient worker transfers a nonempty translucent mask with fading edges', async () => {
  const source = await readFile(new URL('../src/lib/home/smoke.worker.ts', import.meta.url), 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022 } }).outputText;
  const replies = [];
  const self = { postMessage: (data, options) => replies.push({ data, options }) };
  vm.runInNewContext(compiled, { self });
  self.onmessage({ data: {} });
  assert.equal(replies.length, 1);
  const { data: { width, height, pixels }, options } = replies[0];
  assert.equal(pixels.length, width * height * 4);
  assert.equal(options.transfer[0], pixels.buffer);
  const alpha = (x, y) => pixels[(y * width + x) * 4 + 3];
  for (let y = 0; y < height; y++) { assert.equal(alpha(0, y), 0); assert.equal(alpha(width - 1, y), 0); }
  for (let x = 0; x < width; x++) assert.equal(alpha(x, height - 1), 0);
  const values = new Set();
  let top = 0, bottom = 0;
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const value = alpha(x, y);
    assert.ok(value < 210, 'smoke must remain translucent');
    values.add(value);
    if (y < height / 4) top += value;
    if (y >= height * 3 / 4) bottom += value;
  }
  assert.ok(values.size > 40, 'texture must not become a flat rectangle');
  assert.ok(top > bottom * 2, 'light fades into the graphite base');
});

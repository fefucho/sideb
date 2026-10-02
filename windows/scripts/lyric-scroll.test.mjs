import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/player/lyric-scroll.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { LyricScroller } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

function frames() {
  let id = 0;
  const pending = new Map();
  return {
    request(callback) { pending.set(++id, callback); return id; },
    cancel(frame) { pending.delete(frame); },
    advance(time) { const callbacks = [...pending.values()]; pending.clear(); for (const callback of callbacks) callback(time); },
    get callbacks() { return [...pending.values()]; },
  };
}
const container = () => ({ scrollTop: 0, scrollHeight: 2000, clientHeight: 400 });

test('lyric follow takes the Mac response time, moves monotonically and stops at the exact target', () => {
  const clock = frames(); const element = container(); const scroller = new LyricScroller(clock);
  scroller.center(element, 300, true);
  clock.advance(0); clock.advance(100);
  assert.ok(element.scrollTop > 0 && element.scrollTop < 150);
  let previous = element.scrollTop;
  for (const time of [200, 325, 500, 649]) {
    clock.advance(time);
    assert.ok(element.scrollTop >= previous && element.scrollTop < 300);
    previous = element.scrollTop;
  }
  clock.advance(650);
  assert.equal(element.scrollTop, 300);
  assert.equal(clock.callbacks.length, 0);
});

test('manual input or teardown cancels following and a newer target starts at the visible position', () => {
  const clock = frames(); const element = container(); const scroller = new LyricScroller(clock);
  scroller.center(element, 800, true);
  clock.advance(0); clock.advance(100);
  const abandoned = clock.callbacks[0];
  scroller.cancel(); element.scrollTop = 80;
  abandoned(500); clock.advance(650);
  assert.equal(element.scrollTop, 80);
  scroller.center(element, 400, true);
  clock.advance(1000);
  assert.equal(element.scrollTop, 80);
  scroller.center(element, 200, true);
  clock.advance(1200); clock.advance(1850);
  assert.equal(element.scrollTop, 200);
});

test('initial placement and reduced motion jump directly within natural scroll bounds', () => {
  const clock = frames(); const element = container(); const scroller = new LyricScroller(clock);
  scroller.center(element, 500, true); clock.advance(0);
  scroller.center(element, 9999, false);
  assert.equal(element.scrollTop, 1600);
  assert.equal(clock.callbacks.length, 0);
  scroller.center(element, -20, false);
  assert.equal(element.scrollTop, 0);
});

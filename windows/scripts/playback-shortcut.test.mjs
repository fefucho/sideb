import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';
const source = await readFile(new URL('../src/lib/player/playback-shortcut.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { dispatchPlaybackSpace } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);
const focus = { hasTrack: true, editing: false, nativeControl: false, ownsSpace: false };
function event(patch = {}) {
  return { key: ' ', code: 'Space', altKey: false, ctrlKey: false, metaKey: false, shiftKey: false,
    repeat: false, isComposing: false, defaultPrevented: false, prevented: 0,
    preventDefault() { this.prevented++; }, ...patch };
}
test('Space on a page/track-list toggles once and consumes scrolling; held key never flips again', () => {
  let toggles = 0;
  for (const repeat of [false, true, true, true]) {
    const key = event({ repeat });
    assert.equal(dispatchPlaybackSpace(key, focus, () => toggles++), true);
    assert.equal(key.prevented, 1);
  }
  assert.equal(toggles, 1);
});
test('typing, native buttons/links and lyric scroll keep Space and never trigger playback', () => {
  for (const owner of ['editing', 'nativeControl', 'ownsSpace']) {
    const key = event(); let toggles = 0;
    assert.equal(dispatchPlaybackSpace(key, { ...focus, [owner]: true }, () => toggles++), false);
    assert.equal(key.prevented, 0); assert.equal(toggles, 0);
  }
});
test('shortcuts, composition and previously consumed Space are not stolen', () => {
  for (const patch of [{ altKey: true }, { ctrlKey: true }, { metaKey: true }, { shiftKey: true },
    { isComposing: true }, { defaultPrevented: true }, { key: 'Enter', code: 'Enter' }]) {
    const key = event(patch);
    assert.equal(dispatchPlaybackSpace(key, focus, () => assert.fail('toggle')), false);
    assert.equal(key.prevented, 0);
  }
});
test('empty player preserves default Space behavior', () => {
  const key = event();
  assert.equal(dispatchPlaybackSpace(key, { ...focus, hasTrack: false }, () => assert.fail('toggle')), false);
  assert.equal(key.prevented, 0);
});

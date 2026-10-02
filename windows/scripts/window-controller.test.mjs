import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/window/controller.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { WindowController, WindowControllerError } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

function fakeWindow(initial = false) {
  const calls = []; let fullscreen = initial;
  return {
    calls,
    api: {
      isFullscreen: async () => { calls.push('is'); return fullscreen; },
      setFullscreen: async value => { calls.push(value); fullscreen = value; },
    },
    get fullscreen() { return fullscreen; },
  };
}

test('F11 enters and exits native fullscreen', async () => {
  const native = fakeWindow(false); const controller = new WindowController(async () => native.api);
  await controller.toggleNativeFullscreen();
  assert.equal(native.fullscreen, true);
  await controller.toggleNativeFullscreen();
  assert.equal(native.fullscreen, false);
  assert.deepEqual(native.calls, ['is', true, 'is', false]);
});

test('F11 exits an already fullscreen window', async () => {
  const native = fakeWindow(true); const controller = new WindowController(async () => native.api);
  await controller.toggleNativeFullscreen();
  assert.equal(native.fullscreen, false);
  assert.deepEqual(native.calls, ['is', false]);
});

test('native fullscreen actions are serialized and failures remain retryable', async () => {
  let failNextSet = true; const native = fakeWindow(false);
  const controller = new WindowController(async () => ({
    isFullscreen: native.api.isFullscreen,
    setFullscreen: async value => {
      if (failNextSet) { failNextSet = false; throw new Error('native failure'); }
      await native.api.setFullscreen(value);
    },
  }));
  await assert.rejects(controller.toggleNativeFullscreen(), error => error instanceof WindowControllerError && error.action === 'toggle-native-fullscreen');
  await controller.toggleNativeFullscreen();
  assert.equal(native.fullscreen, true);
  await controller.toggleNativeFullscreen();
  assert.equal(native.fullscreen, false);
});

test('overlapping F11 transitions run in call order', async () => {
  let releaseFirstRead;
  let signalFirstRead;
  const firstReadStarted = new Promise(resolve => { signalFirstRead = resolve; });
  let fullscreen = false;
  const calls = [];
  const controller = new WindowController(async () => ({
    isFullscreen: () => {
      calls.push('read-start');
      if (calls.filter(call => call === 'read-start').length === 1) {
        signalFirstRead();
        return new Promise(resolve => { releaseFirstRead = () => { calls.push('read-end'); resolve(fullscreen); }; });
      }
      calls.push('read-end');
      return Promise.resolve(fullscreen);
    },
    setFullscreen: async value => { calls.push(`set-${value}`); fullscreen = value; },
  }));
  const entering = controller.toggleNativeFullscreen();
  const toggling = controller.toggleNativeFullscreen();
  await firstReadStarted;
  assert.deepEqual(calls, ['read-start']);
  releaseFirstRead();
  await Promise.all([entering, toggling]);
  assert.deepEqual(calls, ['read-start', 'read-end', 'set-true', 'read-start', 'read-end', 'set-false']);
  assert.equal(fullscreen, false);
});

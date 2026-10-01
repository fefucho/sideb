import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import ts from 'typescript';

const source = await readFile(new URL('../src/lib/updater/controller.ts', import.meta.url), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { UpdaterController } = await import(`data:text/javascript;base64,${Buffer.from(output).toString('base64')}`);

function createMockApi(overrides = {}) {
  let progressCb = null;
  return {
    calls: [],
    progressCb: (p) => progressCb?.(p),
    api: {
      getAppVersion: async () => '0.1.0',
      checkForUpdates: async (manual) => {
        overrides.calls?.push({ method: 'checkForUpdates', manual });
        if (overrides.checkResult) return overrides.checkResult;
        return { status: 'upToDate', currentVersion: '0.1.0' };
      },
      downloadAndInstallUpdate: async (url) => {
        overrides.calls?.push({ method: 'downloadAndInstallUpdate', url });
        if (overrides.downloadError) throw new Error(overrides.downloadError);
      },
      skipVersion: async (ver) => {
        overrides.calls?.push({ method: 'skipVersion', ver });
      },
      resetSkippedVersion: async () => {},
      getSkippedVersion: async () => null,
      onDownloadProgress: (cb) => {
        progressCb = cb;
        return () => { progressCb = null; };
      },
      ...overrides,
    },
  };
}

test('UpdaterController init loads current version', async () => {
  const mock = createMockApi({ getAppVersion: async () => '1.2.3' });
  const controller = new UpdaterController(async () => mock.api);
  await controller.init();
  assert.equal(controller.getSnapshot().currentVersion, '1.2.3');
});

test('automatic check transitions to available and opens modal when update exists', async () => {
  const calls = [];
  const sampleUpdate = {
    tagName: 'v0.2.0',
    version: '0.2.0',
    releaseNotes: 'Nuevas funciones y mejoras',
    downloadUrl: 'https://example.com/setup.exe',
  };
  const mock = createMockApi({
    calls,
    checkResult: { status: 'available', data: sampleUpdate },
  });

  const controller = new UpdaterController(async () => mock.api);
  await controller.checkForUpdates(false);

  const snapshot = controller.getSnapshot();
  assert.equal(snapshot.isModalOpen, true);
  assert.equal(snapshot.state.type, 'available');
  assert.deepEqual(snapshot.state.info, sampleUpdate);
});

test('automatic check stays idle and closed when up to date', async () => {
  const mock = createMockApi({
    checkResult: { status: 'upToDate', currentVersion: '0.1.0' },
  });

  const controller = new UpdaterController(async () => mock.api);
  await controller.checkForUpdates(false);

  const snapshot = controller.getSnapshot();
  assert.equal(snapshot.isModalOpen, false);
  assert.equal(snapshot.state.type, 'idle');
});

test('manual check opens modal and shows upToDate when app is updated', async () => {
  const mock = createMockApi({
    checkResult: { status: 'upToDate', currentVersion: '0.1.0' },
  });

  const controller = new UpdaterController(async () => mock.api);
  await controller.checkForUpdates(true);

  const snapshot = controller.getSnapshot();
  assert.equal(snapshot.isModalOpen, true);
  assert.equal(snapshot.state.type, 'upToDate');
  assert.equal(snapshot.state.version, '0.1.0');
});

test('downloadAndInstall coordinates progress and installing state', async () => {
  const calls = [];
  let capturedCb = null;
  const sampleUpdate = {
    tagName: 'v0.2.0',
    version: '0.2.0',
    releaseNotes: 'Fixes',
    downloadUrl: 'https://example.com/setup.exe',
  };

  const mock = createMockApi({
    calls,
    checkResult: { status: 'available', data: sampleUpdate },
    onDownloadProgress: (cb) => {
      capturedCb = cb;
      return () => { capturedCb = null; };
    },
    downloadAndInstallUpdate: async (url) => {
      calls.push({ method: 'downloadAndInstallUpdate', url });
      // Simulate progress event
      capturedCb?.({ percentage: 0.5, downloadedBytes: 50, totalBytes: 100 });
    },
  });

  const controller = new UpdaterController(async () => mock.api);
  await controller.checkForUpdates(false);
  assert.equal(controller.getSnapshot().state.type, 'available');

  await controller.downloadAndInstall();

  const snapshot = controller.getSnapshot();
  assert.equal(snapshot.state.type, 'installing');
  assert.equal(calls.some(c => c.method === 'downloadAndInstallUpdate' && c.url === 'https://example.com/setup.exe'), true);
});

test('skipVersion calls API and closes modal', async () => {
  const calls = [];
  const mock = createMockApi({
    calls,
    skipVersion: async (ver) => { calls.push({ method: 'skipVersion', ver }); },
  });

  const controller = new UpdaterController(async () => mock.api);
  controller.openModal();
  assert.equal(controller.getSnapshot().isModalOpen, true);

  await controller.skipVersion('0.2.0');
  assert.equal(controller.getSnapshot().isModalOpen, false);
  assert.deepEqual(calls, [{ method: 'skipVersion', ver: '0.2.0' }]);
});

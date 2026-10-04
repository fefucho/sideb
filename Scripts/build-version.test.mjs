import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync, copyFileSync, chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { buildVersion, reserveBuild, parseArguments, sourceSnapshot } from './build-version.mjs';

const scripts = dirname(fileURLToPath(import.meta.url));
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'sideb-build-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  writeFileSync(join(root, 'version.env'), 'MARKETING_VERSION="1.1.4"\nBUILD_NUMBER="8"\n');
  mkdirSync(join(root, 'apple'));
  return root;
}
const snapshot = () => ({ commit: 'test-commit', branch: 'main', workingTree: ' M source', sourceSHA256: 'source-hash' });
function nativeArtifacts(root, configuration) {
  const dir = join(root, 'windows', 'src-tauri', 'target', configuration);
  mkdirSync(dir, { recursive: true });
  for (const name of ['sideb-windows.exe', 'libmpv-2.dll', 'vulkan-1.dll', 'VulkanRT-License.txt']) writeFileSync(join(dir, name), `${name}: complete`);
}

test('arguments default to release and reject accidental options/configurations', () => {
  assert.deepEqual(parseArguments(['macos']), { platform: 'macos', configuration: 'release', open: false });
  assert.deepEqual(parseArguments(['windows', '--configuration', 'debug', '--open']), { platform: 'windows', configuration: 'debug', open: true });
  for (const args of [[], ['linux'], ['macos', '--configuration'], ['windows', '--configuration', 'typo'], ['macos', '--skip-checks']]) assert.throws(() => parseArguments(args));
});

test('exclusive reservation preserves builds and never reuses a deleted latest number', t => {
  const root = fixture(t);
  const first = reserveBuild(root, 'macos');
  writeFileSync(join(first.directory, 'old-app'), 'old version');
  assert.throws(() => reserveBuild(root, 'macos'), /lock/);
  first.release();
  const second = reserveBuild(root, 'macos');
  assert.equal(second.id, 'build-0002');
  second.release(); rmSync(second.directory, { recursive: true });
  const third = reserveBuild(root, 'macos');
  assert.equal(third.id, 'build-0003'); third.release();
  assert.equal(readFileSync(join(first.directory, 'old-app'), 'utf8'), 'old version');
  const win = reserveBuild(root, 'windows');
  assert.equal(win.id, 'build-0001'); win.release();
});

test('imported numbered folders advance the counter; corrupted counter releases lock', t => {
  const root = fixture(t);
  const dir = join(root, 'builds', 'macos');
  mkdirSync(join(dir, 'build-0012'), { recursive: true });
  const build = reserveBuild(root, 'macos');
  assert.equal(build.id, 'build-0013'); build.release();
  writeFileSync(join(dir, '.next-number'), 'broken');
  assert.throws(() => reserveBuild(root, 'macos'), /Contador inválido/);
  assert.equal(existsSync(join(dir, '.lock')), false);
});

test('wrong host fails without reserving a build', async t => {
  const root = fixture(t);
  await assert.rejects(buildVersion(root, parseArguments(['windows']), { host: 'darwin', architecture: 'arm64' }), /Windows x64/);
  assert.equal(existsSync(join(root, 'builds')), false);
});

test('Mac runs checks, regenerates core artifacts, and writes a verified deliverable manifest', async t => {
  const root = fixture(t), calls = [];
  const execute = async (command, args) => {
    calls.push([command, args]);
    if (command === 'bash' && args[0].endsWith('build-macos.sh')) {
      const binary = join(args[2], 'Contents', 'MacOS');
      mkdirSync(binary, { recursive: true }); writeFileSync(join(binary, 'Side B'), 'new binary');
    }
  };
  const result = await buildVersion(root, parseArguments(['macos']), { host: 'darwin', architecture: 'arm64', snapshot, execute });
  assert.deepEqual(calls.map(([command]) => command), ['cargo', 'bash', 'swift', 'bash']);
  assert.deepEqual(calls[1][1], ['build_xcframework.sh']);
  assert.equal(result.metadata.status, 'compiled');
  assert.equal(result.metadata.publicBuild, '8');
  assert.equal(result.metadata.sourceBefore.workingTree, ' M source');
  assert.match(result.metadata.artifactSHA256['Side B.app/Contents/MacOS/Side B'], /^[a-f0-9]{64}$/);
  assert.equal(existsSync(join(root, 'builds', 'macos', '.lock')), false);
  assert.equal(readFileSync(join(root, 'version.env'), 'utf8').includes('BUILD_NUMBER="8"'), true);
});

test('Windows conserves all required runtime files and runs bootstrap, verify, build', async t => {
  const root = fixture(t), actions = [];
  const execute = async (command, args) => {
    const action = args[args.indexOf('-Action') + 1]; actions.push(action);
    if (action === 'build') nativeArtifacts(root, 'debug');
  };
  const result = await buildVersion(root, parseArguments(['windows', '--configuration', 'debug']), { host: 'win32', architecture: 'x64', powerShell: 'mock-powershell', snapshot, execute });
  assert.deepEqual(actions, ['bootstrap', 'verify', 'build']);
  assert.equal(result.metadata.status, 'compiled');
  assert.equal(Object.keys(result.metadata.artifactSHA256).length, 4);
  assert.equal(readFileSync(join(result.directory, 'libmpv-2.dll'), 'utf8'), 'libmpv-2.dll: complete');
  nativeArtifacts(root, 'debug');
  writeFileSync(join(root, 'windows', 'src-tauri', 'target', 'debug', 'libmpv-2.dll'), 'next build');
  assert.equal(readFileSync(join(result.directory, 'libmpv-2.dll'), 'utf8'), 'libmpv-2.dll: complete');
});

test('failure stops compilation, records diagnosis, releases lock, and next attempt uses a new number', async t => {
  const root = fixture(t), actions = [];
  const execute = async (command, args) => {
    const action = args[args.indexOf('-Action') + 1]; actions.push(action);
    if (action === 'verify') throw new Error('check failed');
  };
  const deps = { host: 'win32', architecture: 'x64', powerShell: 'mock-powershell', snapshot, execute };
  await assert.rejects(buildVersion(root, parseArguments(['windows']), deps), /check failed/);
  assert.deepEqual(actions, ['bootstrap', 'verify']);
  const first = join(root, 'builds', 'windows', 'build-0001');
  const failed = JSON.parse(readFileSync(join(first, 'BUILD.json'), 'utf8'));
  assert.equal(failed.status, 'failed');
  assert.equal(failed.steps.at(-1).status, 'failed');
  assert.equal(existsSync(join(root, 'builds', 'windows', '.lock')), false);
  const second = reserveBuild(root, 'windows');
  assert.equal(second.id, 'build-0002'); second.release();
  assert.equal(existsSync(join(first, 'build.log')), true);
});

test('missing standalone runtime is a failed build rather than a successful EXE-only delivery', async t => {
  const root = fixture(t);
  await assert.rejects(buildVersion(root, parseArguments(['windows']), { host: 'win32', architecture: 'x64', powerShell: 'mock-powershell', snapshot, execute: async () => {} }), /Falta el archivo standalone/);
  assert.equal(JSON.parse(readFileSync(join(root, 'builds', 'windows', 'build-0001', 'BUILD.json'), 'utf8')).status, 'failed');
});

test('source fingerprint detects edits and untracked source without depending on a clean Git tree', t => {
  const root = fixture(t);
  const gitEnv = { ...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: process.platform === 'win32' ? 'NUL' : '/dev/null' };
  for (const args of [['init', '--initial-branch=main'], ['add', '--', 'version.env'], ['-c', 'user.name=Build Test', '-c', 'user.email=build@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '-m', 'base']]) {
    const result = spawnSync('git', args, { cwd: root, env: gitEnv, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
  }
  const first = sourceSnapshot(root);
  writeFileSync(join(root, 'apple', 'new.swift'), 'first');
  const second = sourceSnapshot(root);
  writeFileSync(join(root, 'apple', 'new.swift'), 'second');
  const third = sourceSnapshot(root);
  assert.equal(first.commit, third.commit);
  assert.notEqual(first.sourceSHA256, second.sourceSHA256);
  assert.notEqual(second.sourceSHA256, third.sourceSHA256);
});

test('Mac packaging handles paths with spaces and refuses overwrite/signing failure', { skip: process.platform === 'win32' }, t => {
  const root = fixture(t), tools = join(root, 'fake tools'), bin = join(root, 'native output');
  mkdirSync(tools); mkdirSync(bin); mkdirSync(join(root, 'Scripts')); mkdirSync(join(root, 'apple', 'SideBCore.xcframework'));
  writeFileSync(join(bin, 'SideB'), 'native binary');
  copyFileSync(join(scripts, 'build-macos.sh'), join(root, 'Scripts', 'build-macos.sh'));
  const commands = {
    swift: '#!/bin/bash\nif [[ "$*" == *"--show-bin-path"* ]]; then printf "%s\\n" "$TEST_MAC_BIN"; fi\n',
    xcrun: '#!/bin/bash\nif [ "$1" = vtool ]; then echo "sdk 27.0"; else echo "27.0"; fi\n',
    codesign: '#!/bin/bash\nif [ "${TEST_SIGN_FAIL:-0}" = 1 ]; then exit 1; fi\n',
  };
  for (const [name, content] of Object.entries(commands)) { writeFileSync(join(tools, name), content); chmodSync(join(tools, name), 0o755); }
  const app = join(root, 'version one', 'Side B.app');
  const env = { ...process.env, PATH: `${tools}:${process.env.PATH}`, TEST_MAC_BIN: bin };
  const run = (path, extra = {}) => spawnSync('bash', [join(root, 'Scripts', 'build-macos.sh'), 'release', path], { env: { ...env, ...extra }, encoding: 'utf8' });
  assert.equal(run(app).status, 0);
  assert.equal(readFileSync(join(app, 'Contents', 'MacOS', 'Side B'), 'utf8'), 'native binary');
  assert.notEqual(run(app).status, 0);
  assert.notEqual(run(join(root, 'unsigned', 'Side B.app'), { TEST_SIGN_FAIL: '1' }).status, 0);
});

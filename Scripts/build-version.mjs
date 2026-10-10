#!/usr/bin/env node
// One local build protocol for both shells; native commands stay platform-specific.
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import {
  appendFileSync, closeSync, copyFileSync, existsSync, mkdirSync, openSync,
  readFileSync, readdirSync, unlinkSync, writeFileSync,
} from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const repository = dirname(dirname(scriptPath));
const platforms = ['macos', 'windows'];
const usage = 'node Scripts/build-version.mjs <macos|windows> [--configuration release|debug] [--open]';

export function parseArguments(args) {
  if (args.length === 1 && ['--help', '-h'].includes(args[0])) return { help: true };
  const [platform, ...options] = args;
  if (!platforms.includes(platform)) throw new Error(usage);
  let configuration = 'release', open = false;
  for (let i = 0; i < options.length; i++) {
    if (options[i] === '--open') open = true;
    else if (options[i] === '--configuration' && ['release', 'debug'].includes(options[i + 1])) {
      configuration = options[++i];
    } else throw new Error(`Opción inválida: ${options[i]}. ${usage}`);
  }
  return { platform, configuration, open };
}

export function reserveBuild(root, platform) {
  if (!platforms.includes(platform)) throw new Error('Plataforma inválida.');
  const base = join(root, 'builds', platform);
  mkdirSync(base, { recursive: true });
  const lock = join(base, '.lock');
  let fd;
  try { fd = openSync(lock, 'wx'); }
  catch (error) {
    if (error.code === 'EEXIST') throw new Error(`Hay una build activa o un lock pendiente: ${lock}. Comprobar el proceso antes de quitarlo.`);
    throw error;
  }
  const release = () => { closeSync(fd); unlinkSync(lock); };
  try {
    writeFileSync(fd, JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString() }));
    const counter = join(base, '.next-number');
    let number = 1;
    if (existsSync(counter)) {
      const value = readFileSync(counter, 'utf8').trim();
      if (!/^[1-9]\d*$/.test(value) || !Number.isSafeInteger(Number(value))) throw new Error(`Contador inválido: ${counter}`);
      number = Number(value);
    }
    // Also honor directories imported from an earlier machine/protocol.
    for (const name of readdirSync(base)) {
      const match = /^build-(\d+)$/.exec(name);
      if (match) number = Math.max(number, Number(match[1]) + 1);
    }
    if (!Number.isSafeInteger(number + 1)) throw new Error('Contador de builds fuera de rango.');
    const id = `build-${String(number).padStart(4, '0')}`;
    const directory = join(base, id);
    mkdirSync(directory);
    writeFileSync(counter, `${number + 1}\n`);
    return { id, number, directory, release };
  } catch (error) { release(); throw error; }
}

function git(root, args) {
  const result = spawnSync('git', args, { cwd: root, encoding: 'utf8', windowsHide: true });
  if (result.error || result.status !== 0) throw new Error(result.stderr || result.error?.message || 'Falló Git.');
  return result.stdout;
}

export function sourceSnapshot(root) {
  const sha = createHash('sha256');
  const files = [...new Set(git(root, ['ls-files', '--cached', '--others', '--exclude-standard', '-z']).split('\0'))]
    .filter(name => name && !name.startsWith('temp/') && !name.startsWith('builds/')).sort();
  for (const name of files) {
    sha.update(name).update('\0');
    const path = join(root, name);
    sha.update(existsSync(path) ? readFileSync(path) : 'DELETED').update('\0');
  }
  return {
    commit: git(root, ['rev-parse', 'HEAD']).trim(),
    branch: git(root, ['rev-parse', '--abbrev-ref', 'HEAD']).trim(),
    workingTree: git(root, ['status', '--porcelain=v1', '--untracked-files=all']).trim(),
    sourceSHA256: sha.digest('hex'),
  };
}

export async function execute(command, args, { cwd, env, log }) {
  await new Promise((accept, reject) => {
    const child = spawn(command, args, { cwd, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    child.stdout.on('data', chunk => { process.stdout.write(chunk); appendFileSync(log, chunk); });
    child.stderr.on('data', chunk => { process.stderr.write(chunk); appendFileSync(log, chunk); });
    child.once('error', reject);
    child.once('close', (code, signal) => code === 0 ? accept() : reject(new Error(`${command} terminó con ${signal || code}.`)));
  });
}

function commandVersion(command, args, root) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', windowsHide: true });
  return result.status === 0 ? result.stdout.trim() : 'no disponible';
}

export function selectPowerShell(root, probe = commandVersion) {
  // PowerShell 7's inherited module path can leave a nested Windows PowerShell
  // without Utility cmdlets. Prefer pwsh and require the hash command we use.
  return ['pwsh', 'powershell'].find(command =>
    probe(command, ['-NoProfile', '-Command', '(Get-Command Get-FileHash -ErrorAction Stop).Name'], root) === 'Get-FileHash');
}

function hashes(path, root = path) {
  const result = {};
  for (const entry of readdirSync(path, { withFileTypes: true })) {
    if (path === root && ['BUILD.json', 'build.log'].includes(entry.name)) continue;
    const file = join(path, entry.name);
    if (entry.isDirectory()) Object.assign(result, hashes(file, root));
    else if (entry.isFile()) result[relative(root, file).replaceAll('\\', '/')] = createHash('sha256').update(readFileSync(file)).digest('hex');
  }
  return result;
}

export async function buildVersion(root, options, dependencies = {}) {
  const host = dependencies.host || process.platform;
  const architecture = dependencies.architecture || process.arch;
  if (!platforms.includes(options.platform) || !['release', 'debug'].includes(options.configuration)) throw new Error('Opciones de build inválidas.');
  if (options.platform === 'macos' && (host !== 'darwin' || architecture !== 'arm64')) {
    throw new Error('La build Mac actual requiere macOS Apple Silicon y Xcode.');
  }
  if (options.platform === 'windows' && (host !== 'win32' || architecture !== 'x64')) {
    throw new Error('La build Windows requiere Windows x64 y MSVC.');
  }
  const snapshot = dependencies.snapshot || sourceSnapshot;
  const before = snapshot(root);
  const versionText = readFileSync(join(root, 'version.env'), 'utf8');
  const build = reserveBuild(root, options.platform);
  const metadataPath = join(build.directory, 'BUILD.json');
  const log = join(build.directory, 'build.log');
  const metadata = {
    schemaVersion: 1, id: build.id, platform: options.platform, configuration: options.configuration,
    createdAt: new Date().toISOString(), status: 'building', sourceBefore: before,
    publicVersion: /^MARKETING_VERSION="([^"]+)"/m.exec(versionText)?.[1] || null,
    publicBuild: /^BUILD_NUMBER="([^"]+)"/m.exec(versionText)?.[1] || null,
    tools: { node: process.version, host, architecture }, steps: [],
  };
  const save = () => writeFileSync(metadataPath, `${JSON.stringify(metadata, null, 2)}\n`);
  const run = dependencies.execute || execute;
  // Standard builds run without live account/provider smoke tests.
  const buildEnv = { ...process.env, SIDEB_LIVE_TESTS: '0', SIDEB_LIVE_CIPHER: '0', SIDEB_LIVE_ACCOUNT: '0' };
  const step = async (command, args, cwd = root) => {
    const record = { command, args, cwd: relative(root, cwd) || '.', status: 'running' };
    metadata.steps.push(record); save();
    const message = `\n> ${command} ${args.join(' ')}\n`;
    process.stdout.write(message); appendFileSync(log, message);
    try { await run(command, args, { cwd, env: buildEnv, log }); record.status = 'passed'; }
    catch (error) { record.status = 'failed'; throw error; }
    finally { save(); }
  };
  let artifact;
  try {
    writeFileSync(log, '');
    for (const command of ['git', 'cargo', 'rustc']) metadata.tools[command] = commandVersion(command, ['--version'], root);
    save();
    if (options.platform === 'macos') {
      metadata.tools.swift = commandVersion('swift', ['--version'], root);
      metadata.tools.xcode = commandVersion('xcodebuild', ['-version'], root);
      await step('cargo', ['test', '--locked', '--manifest-path', 'core/Cargo.toml', '-p', 'innertube', '-p', 'sideb-core']);
      await step('bash', ['build_xcframework.sh'], join(root, 'apple'));
      // Explicitly serialize Swift Testing's AppKit/AVPlayer integration suite.
      // XCTest's default policy alone does not serialize Swift Testing tests.
      await step('swift', ['test', '--package-path', 'apple', '-c', options.configuration, '--no-parallel']);
      artifact = join(build.directory, 'Side B.app');
      await step('bash', [join(root, 'Scripts', 'build-macos.sh'), options.configuration, artifact]);
      if (!existsSync(join(artifact, 'Contents', 'MacOS', 'Side B'))) throw new Error('Falta el ejecutable del bundle Mac.');
    } else {
      const powerShell = dependencies.powerShell || selectPowerShell(root);
      if (!powerShell) throw new Error('Falta PowerShell.');
      metadata.tools.powerShell = commandVersion(powerShell, ['-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()'], root);
      // pnpm is usually a .cmd shim on Windows; resolve it through its shell.
      metadata.tools.pnpm = commandVersion(powerShell, ['-NoProfile', '-Command', 'pnpm --version'], root);
      const native = (action, extra = []) => step(powerShell, ['-NoProfile', '-File', join(root, 'windows', 'scripts', 'windows.ps1'), '-Action', action, ...extra]);
      const mpvDir = process.env.SIDEB_MPV_DIR || join(root, 'windows', '.cache', 'mpv');
      if (!existsSync(join(mpvDir, 'libmpv-2.dll')) || !existsSync(join(mpvDir, 'mpv.lib'))) await native('bootstrap');
      await native('verify');
      await native('build', ['-Configuration', options.configuration]);
      const files = ['sideb-windows.exe', 'libmpv-2.dll', 'vulkan-1.dll', 'VulkanRT-License.txt'];
      for (const file of files) {
        const source = join(root, 'windows', 'src-tauri', 'target', options.configuration, file);
        if (!existsSync(source)) throw new Error(`Falta el archivo standalone: ${source}`);
        copyFileSync(source, join(build.directory, file));
      }
      artifact = join(build.directory, 'sideb-windows.exe');
    }
    metadata.sourceAfter = snapshot(root);
    metadata.sourceChangedDuringBuild = before.sourceSHA256 !== metadata.sourceAfter.sourceSHA256;
    // Hash the deliverable before adding the final metadata; logs aren't an artifact.
    metadata.artifactSHA256 = Object.fromEntries(Object.entries(hashes(build.directory))
      .filter(([name]) => !['BUILD.json', 'build.log'].includes(name)));
    metadata.artifact = relative(root, artifact).replaceAll('\\', '/');
    metadata.status = 'compiled';
    metadata.finishedAt = new Date().toISOString(); save();
  } catch (error) {
    metadata.status = 'failed'; metadata.error = error.message;
    metadata.finishedAt = new Date().toISOString(); save();
    throw new Error(`${error.message}\nDiagnóstico: ${build.directory}`);
  } finally { build.release(); }
  if (options.open) {
    try {
      if (options.platform === 'macos') await run('open', ['-n', artifact], { cwd: root, env: process.env, log });
      else await new Promise((accept, reject) => {
        const child = spawn(artifact, [], { cwd: build.directory, detached: true, stdio: 'ignore' });
        child.once('error', reject); child.once('spawn', () => { child.unref(); accept(); });
      });
      metadata.launch = 'requested'; save();
    } catch (error) { metadata.launchError = error.message; save(); throw new Error(`Build compilada, apertura fallida: ${error.message}`); }
  }
  process.stdout.write(`\nBuild conservada: ${artifact}\nRegistro: ${metadataPath}\n`);
  return { ...build, artifact, metadata };
}

if (process.argv[1] && resolve(process.argv[1]) === scriptPath) {
  try {
    const options = parseArguments(process.argv.slice(2));
    if (options.help) process.stdout.write(`${usage}\nPredeterminado: release. Conserva versiones; no publica releases.\n`);
    else {
      const [major, minor] = process.versions.node.split('.').map(Number);
      if (major < 22 || (major === 22 && minor < 12)) throw new Error('Se necesita Node.js 22.12 o superior.');
      await buildVersion(repository, options);
    }
  } catch (error) { process.stderr.write(`${error.message}\n`); process.exitCode = 1; }
}

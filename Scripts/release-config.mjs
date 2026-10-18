import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, appendFileSync, copyFileSync, mkdirSync } from 'node:fs';
import { basename, dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export function releaseConfig(root, tag) {
  const env = readFileSync(join(root, 'version.env'), 'utf8').replaceAll('\r\n', '\n');
  const version = env.match(/^MARKETING_VERSION="(\d+\.\d+\.\d+)"$/m)?.[1];
  const build = env.match(/^BUILD_NUMBER="(\d+)"$/m)?.[1];
  if (!version || !build) throw new Error('Invalid version.env');
  if (!new RegExp(`^v${version.replaceAll('.', '\\.')}(-beta\\.[1-9]\\d*)?$`).test(tag)) throw new Error('Release tag does not match version.env');
  for (const path of ['windows/package.json', 'windows/src-tauri/tauri.conf.json']) {
    if (JSON.parse(readFileSync(join(root, path), 'utf8')).version !== version) throw new Error(`Version mismatch: ${path}`);
  }
  const cargo = readFileSync(join(root, 'windows/src-tauri/Cargo.toml'), 'utf8').replaceAll('\r\n', '\n');
  const lock = readFileSync(join(root, 'windows/src-tauri/Cargo.lock'), 'utf8').replaceAll('\r\n', '\n');
  if (cargo.match(/^version = "([^"]+)"$/m)?.[1] !== version || !lock.includes(`name = "sideb-windows"\nversion = "${version}"`)) throw new Error('Windows Cargo version mismatch');
  const notes = `release-notes/${tag.slice(1)}.md`;
  if (!existsSync(join(root, notes))) throw new Error(`Missing release notes: ${notes}`);
  return { tag, version, build, notes, prerelease: tag.includes('-beta.') };
}

export function compiledBuild(root, platform, version, build, commit) {
  if (!['macos', 'windows'].includes(platform)) throw new Error('Invalid platform');
  const base = join(root, 'builds', platform);
  const ids = readdirSync(base, { withFileTypes: true }).filter(e => e.isDirectory() && /^build-\d{4,}$/.test(e.name)).map(e => e.name).sort((a,b) => Number(b.slice(6))-Number(a.slice(6)));
  if (!ids.length) throw new Error('No numbered build');
  const directory = join(base, ids[0]);
  const metadata = JSON.parse(readFileSync(join(directory, 'BUILD.json'), 'utf8'));
  if (metadata.status !== 'compiled' || metadata.configuration !== 'release' || metadata.sourceChangedDuringBuild !== false) throw new Error('Build is incomplete or sources changed');
  if (metadata.platform !== platform || metadata.publicVersion !== version || String(metadata.publicBuild) !== String(build)) throw new Error('Build version/platform mismatch');
  if (!commit || metadata.sourceBefore?.commit !== commit) throw new Error('Build commit mismatch');
  const hashes = Object.entries(metadata.artifactSHA256 ?? {});
  if (!hashes.length) throw new Error('Missing artifact hashes');
  for (const [name, expected] of hashes) {
    const path = resolve(directory, name);
    if (!path.startsWith(resolve(directory) + sep)) throw new Error('Artifact escapes build directory');
    const actual = createHash('sha256').update(readFileSync(path)).digest('hex');
    if (actual !== expected) throw new Error(`Artifact checksum mismatch: ${name}`);
  }
  const required = platform === 'windows' ? ['sideb-windows.exe','libmpv-2.dll','vulkan-1.dll','VulkanRT-License.txt'] : ['Side B.app/Contents/MacOS/Side B','Side B.app/Contents/Info.plist'];
  for (const name of required) if (!metadata.artifactSHA256[name]) throw new Error(`Required artifact not verified: ${name}`);
  return directory;
}

export function collectReleaseAssets(source, destination) {
  const required = ['SideB-macOS.zip', 'SideB-macOS-SHA256.txt', 'SideB-Windows-x64-setup.exe', 'SideB-windows-x64.zip', 'SideB-Windows-x64-SHA256.txt'];
  const found = new Map();
  function visit(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) { visit(path); continue; }
      if (!entry.isFile() || !required.includes(basename(path))) throw new Error(`Unexpected release asset: ${path}`);
      if (found.has(entry.name)) throw new Error(`Duplicate release asset: ${entry.name}`);
      if (!readFileSync(path).length) throw new Error(`Empty release asset: ${entry.name}`);
      found.set(entry.name, path);
    }
  }
  visit(source);
  for (const name of required) if (!found.has(name)) throw new Error(`Missing release asset: ${name}`);
  for (const [checksum, expected] of [
    ['SideB-macOS-SHA256.txt', ['SideB-macOS.zip']],
    ['SideB-Windows-x64-SHA256.txt', ['SideB-Windows-x64-setup.exe', 'SideB-windows-x64.zip']],
  ]) {
    const checked = new Set();
    for (const line of readFileSync(found.get(checksum), 'utf8').trim().split(/\r?\n/)) {
      const match = /^([a-fA-F0-9]{64})\s+\*?([^\r\n]+)$/.exec(line);
      if (!match || !expected.includes(match[2]) || checked.has(match[2])) throw new Error(`Invalid release checksums: ${checksum}`);
      const actual = createHash('sha256').update(readFileSync(found.get(match[2]))).digest('hex');
      if (actual !== match[1].toLowerCase()) throw new Error(`Release checksum mismatch: ${match[2]}`);
      checked.add(match[2]);
    }
    if (checked.size !== expected.length) throw new Error(`Incomplete release checksums: ${checksum}`);
  }
  if (existsSync(destination) && readdirSync(destination).length) throw new Error('Release destination must be empty');
  mkdirSync(destination, { recursive: true });
  for (const name of required) copyFileSync(found.get(name), join(destination, name));
  return resolve(destination);
}

const script = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === script) {
  try {
    const root = dirname(dirname(script));
    const config = releaseConfig(root, process.env.RELEASE_TAG);
    if (process.argv[2] === 'preflight') {
      const outputs = Object.entries(config).map(([key,value]) => `${key}=${value}`).join('\n')+'\n';
      if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, outputs);
      process.stdout.write(outputs);
    } else if (process.argv[2] === 'build') {
      const directory = compiledBuild(root, process.argv[3], config.version, config.build, process.env.GITHUB_SHA);
      if (process.env.GITHUB_ENV) appendFileSync(process.env.GITHUB_ENV, `RELEASE_BUILD_DIR=${directory}\n`);
      process.stdout.write(directory+'\n');
    } else if (process.argv[2] === 'assets' && process.argv[3] && process.argv[4]) {
      process.stdout.write(collectReleaseAssets(resolve(process.argv[3]), resolve(process.argv[4]))+'\n');
    } else throw new Error('Usage: node Scripts/release-config.mjs preflight|build <platform>|assets <source> <destination>');
  } catch (error) { process.stderr.write(error.message+'\n'); process.exitCode=1; }
}

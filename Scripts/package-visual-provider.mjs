#!/usr/bin/env node
// Forms the installable visual-provider package (JSON/stdio v1) for one platform.
// The same layout ships preinstalled in both apps and can be installed by hand:
//   <out>/manifest.json, <out>/<executable>, LICENSE, THIRD_PARTY_NOTICES.md, SHA256SUMS
// The host only ever copies manifest.json and the executable; the rest is for audit.
import { createHash } from 'node:crypto';
import { chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(import.meta.url);
const repository = dirname(dirname(script));
const usage = 'node Scripts/package-visual-provider.mjs --platform <macos-arm64|windows-x64> --binary <ejecutable> --out <carpeta nueva> [--provider spotify-canvas]';

// Hosts reject executables above this size (Swift VisualProviderHost.readManifest).
export const MAX_EXECUTABLE_BYTES = 128 * 1024 * 1024;
export const PLATFORMS = {
  'macos-arm64': { executable: /^[A-Za-z0-9._-]+$/ },
  'windows-x64': { executable: /^[A-Za-z0-9._-]+\.exe$/ },
};
const EXTRAS = ['LICENSE', 'THIRD_PARTY_NOTICES.md'];

export function parseArguments(args) {
  const options = { provider: 'spotify-canvas' };
  for (let i = 0; i < args.length; i++) {
    const name = args[i], value = args[i + 1];
    if (!['--platform', '--binary', '--out', '--provider'].includes(name) || value === undefined || value.startsWith('--')) throw new Error(usage);
    options[name.slice(2)] = value; i++;
  }
  if (!options.platform || !options.binary || !options.out) throw new Error(usage);
  return options;
}

function safeComponent(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 64 && value !== '.' && value !== '..' && /^[A-Za-z0-9._-]+$/.test(value);
}

export function cargoVersion(providerDirectory) {
  const version = /^version = "(\d+\.\d+\.\d+)"$/m.exec(readFileSync(join(providerDirectory, 'Cargo.toml'), 'utf8').replaceAll('\r\n', '\n'))?.[1];
  if (!version) throw new Error('Cargo.toml del proveedor sin versión.');
  return version;
}

// Machine-code sanity check so a wrong-architecture binary is never packaged under the right name.
export function checkExecutableFormat(platform, bytes) {
  if (platform === 'windows-x64') {
    // PE: "MZ", e_lfanew -> "PE\0\0", machine 0x8664 (AMD64).
    if (bytes.length < 0x40 || bytes[0] !== 0x4d || bytes[1] !== 0x5a) throw new Error('El ejecutable Windows no es un PE.');
    const pe = bytes.readUInt32LE(0x3c);
    if (pe + 6 > bytes.length || bytes.readUInt32LE(pe) !== 0x00004550 || bytes.readUInt16LE(pe + 4) !== 0x8664) throw new Error('El ejecutable Windows no es x64.');
  } else {
    // Mach-O 64-bit little endian, CPU_TYPE_ARM64 (0x0100000c).
    if (bytes.length < 8 || bytes.readUInt32LE(0) !== 0xfeedfacf || bytes.readUInt32LE(4) !== 0x0100000c) throw new Error('El ejecutable macOS no es Mach-O arm64.');
  }
}

export function packageProvider(root, { platform, binary, out, provider = 'spotify-canvas' }) {
  if (!Object.hasOwn(PLATFORMS, platform)) throw new Error(`Plataforma inválida: ${platform}`);
  if (!safeComponent(provider)) throw new Error('Proveedor inválido.');
  const source = join(root, 'extensions', provider);
  const manifestPath = join(source, 'package', `manifest.${platform}.json`);
  if (!existsSync(manifestPath)) throw new Error(`Falta el manifiesto de plataforma: ${manifestPath}`);
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const problems = [];
  if (manifest.protocolVersion !== 1) problems.push('protocolVersion debe ser 1');
  if (manifest.id !== provider) problems.push('id distinto del directorio');
  if (manifest.platform !== platform) problems.push('platform no coincide con el archivo');
  if (!safeComponent(manifest.executable) || !PLATFORMS[platform].executable.test(manifest.executable)) problems.push('executable inválido para la plataforma');
  if (manifest.version !== cargoVersion(source)) problems.push(`version ${manifest.version} distinta de Cargo.toml ${cargoVersion(source)}`);
  if (JSON.stringify(manifest).length > 8192) problems.push('manifiesto demasiado grande');
  if (problems.length) throw new Error(`Manifiesto ${platform} inválido: ${problems.join('; ')}`);

  const info = lstatSync(binary, { throwIfNoEntry: false });
  if (!info || !info.isFile() || info.isSymbolicLink()) throw new Error(`El ejecutable no es un archivo regular: ${binary}`);
  if (info.size === 0 || info.size > MAX_EXECUTABLE_BYTES) throw new Error('Tamaño de ejecutable fuera de rango.');
  const bytes = readFileSync(binary);
  checkExecutableFormat(platform, bytes);

  const destination = resolve(out);
  if (existsSync(destination) && readdirSync(destination).length) throw new Error(`El destino debe estar vacío: ${destination}`);
  mkdirSync(destination, { recursive: true });
  copyFileSync(manifestPath, join(destination, 'manifest.json'));
  writeFileSync(join(destination, manifest.executable), bytes);
  chmodSync(join(destination, manifest.executable), 0o755);
  for (const name of EXTRAS) {
    if (existsSync(join(source, name))) copyFileSync(join(source, name), join(destination, name));
  }
  const sums = {};
  for (const name of readdirSync(destination).sort()) sums[name] = createHash('sha256').update(readFileSync(join(destination, name))).digest('hex');
  writeFileSync(join(destination, 'SHA256SUMS'), Object.entries(sums).map(([name, hash]) => `${hash}  ${name}`).join('\n') + '\n');
  return { directory: destination, manifest, sha256: sums };
}

if (process.argv[1] && resolve(process.argv[1]) === script) {
  try {
    const result = packageProvider(repository, parseArguments(process.argv.slice(2)));
    process.stdout.write(`Proveedor ${result.manifest.id} ${result.manifest.version} (${result.manifest.platform}) empaquetado en ${result.directory}\n`);
  } catch (error) { process.stderr.write(`${error.message}\n`); process.exitCode = 1; }
}

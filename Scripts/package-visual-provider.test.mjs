import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { cargoVersion, checkExecutableFormat, packageProvider, parseArguments } from './package-visual-provider.mjs';

const repository = dirname(dirname(fileURLToPath(import.meta.url)));
const macBinary = () => { const b = Buffer.alloc(64); b.writeUInt32LE(0xfeedfacf, 0); b.writeUInt32LE(0x0100000c, 4); return b; };
const windowsBinary = (machine = 0x8664) => {
  const b = Buffer.alloc(256); b.write('MZ', 0, 'latin1'); b.writeUInt32LE(0x80, 0x3c);
  b.writeUInt32LE(0x00004550, 0x80); b.writeUInt16LE(machine, 0x84); return b;
};
function fixture(t, version = '0.2.0') {
  const root = mkdtempSync(join(tmpdir(), 'sideb-provider-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const source = join(root, 'extensions', 'spotify-canvas');
  mkdirSync(join(source, 'package'), { recursive: true });
  writeFileSync(join(source, 'Cargo.toml'), `[package]\nname = "sideb-spotify-canvas"\nversion = "${version}"\n`);
  writeFileSync(join(source, 'LICENSE'), 'MIT');
  writeFileSync(join(source, 'THIRD_PARTY_NOTICES.md'), 'notices');
  for (const [platform, executable] of [['macos-arm64', 'sideb-spotify-canvas'], ['windows-x64', 'sideb-spotify-canvas.exe']]) {
    writeFileSync(join(source, 'package', `manifest.${platform}.json`), JSON.stringify({ protocolVersion: 1, id: 'spotify-canvas', name: 'Spotify Canvas', version, platform, executable, credentialLabel: 'Token' }));
  }
  const binaries = join(root, 'bin'); mkdirSync(binaries);
  writeFileSync(join(binaries, 'mac'), macBinary()); writeFileSync(join(binaries, 'win.exe'), windowsBinary());
  return { root, source, binaries, out: join(root, 'out') };
}

test('arguments are strict', () => {
  assert.deepEqual(parseArguments(['--platform', 'macos-arm64', '--binary', 'a', '--out', 'b']), { provider: 'spotify-canvas', platform: 'macos-arm64', binary: 'a', out: 'b' });
  for (const args of [[], ['--platform', 'macos-arm64'], ['--platform', '--binary', 'a', '--out', 'b'], ['--typo', 'x', '--platform', 'p', '--binary', 'a', '--out', 'b']]) assert.throws(() => parseArguments(args));
});

test('both platforms produce the same layout with the platform executable and verifiable checksums', t => {
  const f = fixture(t);
  const mac = packageProvider(f.root, { platform: 'macos-arm64', binary: join(f.binaries, 'mac'), out: join(f.out, 'mac') });
  const win = packageProvider(f.root, { platform: 'windows-x64', binary: join(f.binaries, 'win.exe'), out: join(f.out, 'win') });
  assert.deepEqual(readdirSync(mac.directory).sort(), ['LICENSE', 'SHA256SUMS', 'THIRD_PARTY_NOTICES.md', 'manifest.json', 'sideb-spotify-canvas']);
  assert.deepEqual(readdirSync(win.directory).sort(), ['LICENSE', 'SHA256SUMS', 'THIRD_PARTY_NOTICES.md', 'manifest.json', 'sideb-spotify-canvas.exe']);
  assert.equal(JSON.parse(readFileSync(join(win.directory, 'manifest.json'), 'utf8')).executable, 'sideb-spotify-canvas.exe');
  for (const result of [mac, win]) {
    const lines = readFileSync(join(result.directory, 'SHA256SUMS'), 'utf8').trim().split('\n');
    assert.equal(lines.length, 4);
    for (const line of lines) {
      const [hash, name] = line.split('  ');
      assert.equal(createHash('sha256').update(readFileSync(join(result.directory, name))).digest('hex'), hash);
      assert.notEqual(name, 'SHA256SUMS');
    }
  }
});

test('refuses overwrite, version drift, wrong architecture, empty or symlinked binaries', t => {
  const f = fixture(t);
  const mac = { platform: 'macos-arm64', binary: join(f.binaries, 'mac'), out: f.out };
  packageProvider(f.root, mac);
  assert.throws(() => packageProvider(f.root, mac), /vacío/);
  writeFileSync(join(f.source, 'Cargo.toml'), '[package]\nversion = "0.3.0"\n');
  assert.throws(() => packageProvider(f.root, { ...mac, out: join(f.root, 'again') }), /distinta de Cargo/);
  writeFileSync(join(f.source, 'Cargo.toml'), '[package]\nversion = "0.2.0"\n');
  writeFileSync(join(f.binaries, 'x86'), Buffer.concat([Buffer.from([0xcf, 0xfa, 0xed, 0xfe, 0x07, 0x00, 0x00, 0x01]), Buffer.alloc(56)]));
  assert.throws(() => packageProvider(f.root, { ...mac, binary: join(f.binaries, 'x86'), out: join(f.root, 'x') }), /arm64/);
  writeFileSync(join(f.binaries, 'win32.exe'), windowsBinary(0x14c));
  assert.throws(() => packageProvider(f.root, { platform: 'windows-x64', binary: join(f.binaries, 'win32.exe'), out: join(f.root, 'w') }), /x64/);
  writeFileSync(join(f.binaries, 'empty'), '');
  assert.throws(() => packageProvider(f.root, { ...mac, binary: join(f.binaries, 'empty'), out: join(f.root, 'e') }), /fuera de rango/);
  assert.throws(() => packageProvider(f.root, { ...mac, binary: join(f.binaries, 'missing'), out: join(f.root, 'm') }), /archivo regular/);
  assert.equal(existsSync(join(f.root, 'x')), false);
});

test('rejects manifests whose executable name does not fit the platform', t => {
  const f = fixture(t);
  const path = join(f.source, 'package', 'manifest.windows-x64.json');
  const manifest = JSON.parse(readFileSync(path, 'utf8'));
  writeFileSync(path, JSON.stringify({ ...manifest, executable: 'sideb-spotify-canvas' }));
  assert.throws(() => packageProvider(f.root, { platform: 'windows-x64', binary: join(f.binaries, 'win.exe'), out: f.out }), /executable inválido/);
  writeFileSync(path, JSON.stringify({ ...manifest, executable: '../evil.exe' }));
  assert.throws(() => packageProvider(f.root, { platform: 'windows-x64', binary: join(f.binaries, 'win.exe'), out: f.out }), /executable inválido/);
  assert.throws(() => checkExecutableFormat('windows-x64', Buffer.from('not an exe')), /PE/);
});

test('the real manifests match Cargo.toml, protocol v1 and the executable names the hosts expect', () => {
  const source = join(repository, 'extensions', 'spotify-canvas');
  const version = cargoVersion(source);
  const expected = { 'macos-arm64': 'sideb-spotify-canvas', 'windows-x64': 'sideb-spotify-canvas.exe' };
  for (const [platform, executable] of Object.entries(expected)) {
    const manifest = JSON.parse(readFileSync(join(source, 'package', `manifest.${platform}.json`), 'utf8'));
    assert.deepEqual([manifest.protocolVersion, manifest.id, manifest.version, manifest.platform, manifest.executable], [1, 'spotify-canvas', version, platform, executable]);
    assert.equal(manifest.auth.type, 'webview');
    assert.ok(manifest.auth.loginUrl.startsWith('https://') && manifest.auth.tokenUrl.startsWith('https://'));
  }
  const mac = JSON.parse(readFileSync(join(source, 'package', 'manifest.macos-arm64.json'), 'utf8'));
  const win = JSON.parse(readFileSync(join(source, 'package', 'manifest.windows-x64.json'), 'utf8'));
  delete mac.platform; delete mac.executable; delete win.platform; delete win.executable;
  assert.deepEqual(mac, win, 'only platform and executable may differ between manifests');
});

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { releaseConfig, compiledBuild, collectReleaseAssets } from './release-config.mjs';

function fixture(t) {
  const root=mkdtempSync(join(tmpdir(),'sideb-release-'));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  for (const dir of ['windows/src-tauri','release-notes','builds/windows/build-0001']) mkdirSync(join(root,dir),{recursive:true});
  writeFileSync(join(root,'version.env'),'MARKETING_VERSION="1.2.0"\nBUILD_NUMBER="13"\n');
  for (const name of ['windows/package.json','windows/src-tauri/tauri.conf.json']) writeFileSync(join(root,name),'{"version":"1.2.0"}');
  writeFileSync(join(root,'windows/src-tauri/Cargo.toml'),'[package]\nversion = "1.2.0"\n');
  writeFileSync(join(root,'windows/src-tauri/Cargo.lock'),'name = "sideb-windows"\nversion = "1.2.0"\n');
  writeFileSync(join(root,'release-notes/1.2.0-beta.1.md'),'Feature parity beta');
  const directory=join(root,'builds/windows/build-0001'),artifactSHA256={};
  for (const name of ['sideb-windows.exe','libmpv-2.dll','vulkan-1.dll','VulkanRT-License.txt']) {
    writeFileSync(join(directory,name),name);artifactSHA256[name]=createHash('sha256').update(name).digest('hex');
  }
  const metadata={status:'compiled',configuration:'release',platform:'windows',publicVersion:'1.2.0',publicBuild:'13',sourceChangedDuringBuild:false,sourceBefore:{commit:'revision'},artifactSHA256};
  const save=()=>writeFileSync(join(directory,'BUILD.json'),JSON.stringify(metadata));save();
  return {root,directory,metadata,save};
}

test('beta tag, notes and all Windows versions agree',t=>{const f=fixture(t);assert.deepEqual(releaseConfig(f.root,'v1.2.0-beta.1'),{tag:'v1.2.0-beta.1',version:'1.2.0',build:'13',notes:'release-notes/1.2.0-beta.1.md',prerelease:true});});
test('accepts Windows checkout line endings without changing version validation',t=>{const f=fixture(t);for(const name of ['version.env','windows/src-tauri/Cargo.toml','windows/src-tauri/Cargo.lock']){const path=join(f.root,name);writeFileSync(path,readFileSync(path,'utf8').replaceAll('\n','\r\n'));}assert.equal(releaseConfig(f.root,'v1.2.0-beta.1').version,'1.2.0');});
test('rejects stale versions, wrong tags and tag injection',t=>{const f=fixture(t);for(const tag of ['v1.1.8','v1.2.0-beta.0','v1.2.0-beta.1\nmalicious','../notes'])assert.throws(()=>releaseConfig(f.root,tag));writeFileSync(join(f.root,'windows/package.json'),'{"version":"0.1.0"}');assert.throws(()=>releaseConfig(f.root,'v1.2.0-beta.1'),/Version mismatch/);});
test('requires the exact verified revision and complete runtime',t=>{const f=fixture(t);assert.equal(compiledBuild(f.root,'windows','1.2.0','13','revision'),f.directory);assert.throws(()=>compiledBuild(f.root,'windows','1.2.0','13','another'),/commit mismatch/);delete f.metadata.artifactSHA256['vulkan-1.dll'];f.save();assert.throws(()=>compiledBuild(f.root,'windows','1.2.0','13','revision'),/Required artifact/);});
test('rejects changed sources, wrong version and corrupted executable',t=>{const f=fixture(t);f.metadata.sourceChangedDuringBuild=true;f.save();assert.throws(()=>compiledBuild(f.root,'windows','1.2.0','13','revision'),/sources changed/);f.metadata.sourceChangedDuringBuild=false;f.save();assert.throws(()=>compiledBuild(f.root,'windows','1.1.8','13','revision'),/version\/platform/);writeFileSync(join(f.directory,'sideb-windows.exe'),'corrupted');assert.throws(()=>compiledBuild(f.root,'windows','1.2.0','13','revision'),/checksum/);});
test('does not fall back to an older successful build or accept outside artifacts',t=>{const f=fixture(t);f.metadata.artifactSHA256['../outside']='digest';f.save();assert.throws(()=>compiledBuild(f.root,'windows','1.2.0','13','revision'),/escapes/);mkdirSync(join(f.root,'builds/windows/build-0002'));writeFileSync(join(f.root,'builds/windows/build-0002/BUILD.json'),'{"status":"failed"}');assert.throws(()=>compiledBuild(f.root,'windows','1.2.0','13','revision'),/incomplete/);});

function downloadedAssets(t) {
  const root=mkdtempSync(join(tmpdir(),'sideb-assets-'));t.after(()=>rmSync(root,{recursive:true,force:true}));
  const source=join(root,'download'),nested=join(source,'build-0001'),destination=join(root,'flat');mkdirSync(nested,{recursive:true});
  const names=['SideB-macOS.zip','SideB-Windows-x64-setup.exe','SideB-windows-x64.zip'];
  for(const name of names)writeFileSync(join(nested,name),name);
  const line=name=>createHash('sha256').update(name).digest('hex')+'  '+name;
  writeFileSync(join(nested,'SideB-macOS-SHA256.txt'),line(names[0])+'\n');
  writeFileSync(join(nested,'SideB-Windows-x64-SHA256.txt'),names.slice(1).map(line).join('\r\n')+'\r\n');
  return {root,source,nested,destination,names};
}
test('collects the real numbered artifact layout into a verified flat upload directory',t=>{
  const f=downloadedAssets(t);assert.equal(existsSync(join(f.source,'SideB-macOS.zip')),false);
  assert.equal(collectReleaseAssets(f.source,f.destination),f.destination);
  for(const name of [...f.names,'SideB-macOS-SHA256.txt','SideB-Windows-x64-SHA256.txt'])assert.deepEqual(readFileSync(join(f.destination,name)),readFileSync(join(f.nested,name)));
});
test('refuses ambiguous numbered artifacts and missing packages',t=>{
  const f=downloadedAssets(t);const extra=join(f.source,'build-0002');mkdirSync(extra);writeFileSync(join(extra,f.names[0]),'duplicate');
  assert.throws(()=>collectReleaseAssets(f.source,f.destination),/Duplicate/);rmSync(extra,{recursive:true});rmSync(join(f.nested,f.names[1]));
  assert.throws(()=>collectReleaseAssets(f.source,f.destination),/Missing/);assert.equal(existsSync(f.destination),false);
});
test('rejects changed packages and checksum paths before creating upload output',t=>{
  const f=downloadedAssets(t);writeFileSync(join(f.nested,f.names[0]),'corrupted');
  assert.throws(()=>collectReleaseAssets(f.source,f.destination),/checksum mismatch/);assert.equal(existsSync(f.destination),false);
  writeFileSync(join(f.nested,f.names[0]),f.names[0]);writeFileSync(join(f.nested,'SideB-macOS-SHA256.txt'),'0'.repeat(64)+'  ../outside\n');
  assert.throws(()=>collectReleaseAssets(f.source,f.destination),/Invalid release checksums/);
});

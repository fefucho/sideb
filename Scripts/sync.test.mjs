import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const scripts = dirname(fileURLToPath(import.meta.url));
const env = { ...process.env, LC_ALL: 'C', GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: process.platform === 'win32' ? 'NUL' : '/dev/null', GIT_TERMINAL_PROMPT: '0' };
function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, env, encoding: 'utf8', windowsHide: true });
  if (result.error) throw result.error;
  return result;
}
function git(cwd, ...args) {
  const result = run('git', args, cwd);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result.stdout.trim();
}
const gitExecPath = git(scripts, '--exec-path');
const bash = process.platform === 'win32' ? join(dirname(dirname(dirname(gitExecPath))), 'bin', 'bash.exe') : 'bash';
function sync(cwd, action = 'status', remote = 'origin') {
  return run(bash, [join(cwd, 'Scripts', 'sync.sh').replaceAll('\\', '/'), action, remote], cwd);
}
function commit(cwd, content, message) {
  writeFileSync(join(cwd, 'code.txt'), content);
  git(cwd, 'add', '--', 'code.txt');
  git(cwd, '-c', 'commit.gpgsign=false', 'commit', '-m', message);
  return git(cwd, 'rev-parse', 'HEAD');
}
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'sideb-sync-'));
  t.after(() => {
    // Delete only the exact test directory created immediately under the temp root.
    assert.equal(dirname(resolve(root)), resolve(tmpdir()));
    assert.match(basename(root), /^sideb-sync-/);
    rmSync(root, { recursive: true, force: true });
  });
  const remote = join(root, 'remote.git'), first = join(root, 'work tree'), second = join(root, 'other pc');
  mkdirSync(remote); mkdirSync(first);
  git(remote, 'init', '--bare', '--initial-branch=main');
  git(first, 'init', '--initial-branch=main');
  git(first, 'config', 'user.name', 'Sync Test'); git(first, 'config', 'user.email', 'sync@example.invalid');
  git(first, 'config', 'core.autocrlf', 'false');
  mkdirSync(join(first, 'Scripts'));
  for (const name of ['sync.sh', 'sync.ps1']) copyFileSync(join(scripts, name), join(first, 'Scripts', name));
  writeFileSync(join(first, 'code.txt'), 'base');
  git(first, 'add', '--', 'Scripts', 'code.txt');
  git(first, '-c', 'commit.gpgsign=false', 'commit', '-m', 'base');
  git(first, 'remote', 'add', 'origin', remote);
  git(first, 'push', '-u', 'origin', 'main');
  git(root, 'clone', remote, second);
  git(second, 'config', 'user.name', 'Other PC'); git(second, 'config', 'user.email', 'other@example.invalid');
  git(second, 'config', 'core.autocrlf', 'false');
  return { root, remote, first, second };
}

test('push creates and tracks the current feature branch without changing main or release tags', t => {
  const { remote, first } = fixture(t);
  const main = git(remote, 'rev-parse', 'refs/heads/main');
  git(first, 'switch', '-c', 'codex/windows-fix');
  const head = commit(first, 'Windows fix', 'fix(windows): playlists');
  git(first, 'config', 'push.followTags', 'true');
  git(first, '-c', 'tag.gpgsign=false', 'tag', '-a', 'v9.9.9', '-m', 'Must stay local');
  const result = sync(first, 'push');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(git(remote, 'rev-parse', 'refs/heads/codex/windows-fix'), head);
  assert.equal(git(remote, 'rev-parse', 'refs/heads/main'), main);
  assert.equal(git(first, 'rev-parse', '--abbrev-ref', '@{upstream}'), 'origin/codex/windows-fix');
  assert.equal(git(remote, 'tag', '--list'), '');
});

test('pull fast-forwards the other PC and preserves the current branch', t => {
  const { first, second } = fixture(t);
  const head = commit(first, 'New code', 'fix: shared code');
  assert.equal(sync(first, 'push').status, 0);
  const result = sync(second, 'pull');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(git(second, 'rev-parse', 'HEAD'), head);
  assert.equal(git(second, 'branch', '--show-current'), 'main');
  assert.equal(readFileSync(join(second, 'code.txt'), 'utf8'), 'New code');
});

test('status fetches differences without changing local code or HEAD', t => {
  const { first, second } = fixture(t);
  const before = git(second, 'rev-parse', 'HEAD');
  commit(first, 'Remote code', 'fix: remote');
  assert.equal(sync(first, 'push').status, 0);
  const result = sync(second);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Commits remotos por traer: 1/);
  assert.equal(git(second, 'rev-parse', 'HEAD'), before);
  assert.equal(readFileSync(join(second, 'code.txt'), 'utf8'), 'base');
});

test('dirty tracked and untracked files block push and pull without losing work', t => {
  const { first, remote } = fixture(t);
  const before = git(remote, 'rev-parse', 'main');
  writeFileSync(join(first, 'code.txt'), 'unsaved');
  writeFileSync(join(first, 'new.txt'), 'private work');
  for (const action of ['push', 'pull']) {
    const result = sync(first, action);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /cambios sin guardar/);
  }
  assert.equal(git(remote, 'rev-parse', 'main'), before);
  assert.equal(readFileSync(join(first, 'code.txt'), 'utf8'), 'unsaved');
  assert.equal(readFileSync(join(first, 'new.txt'), 'utf8'), 'private work');
  assert.equal(sync(first, 'status').status, 0);
});

test('a PC behind the remote cannot push until it brings the new commits', t => {
  const { first, second, remote } = fixture(t);
  const remoteHead = commit(first, 'Remote change', 'fix: first PC');
  assert.equal(sync(first, 'push').status, 0);
  const result = sync(second, 'push');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /remoto tiene commits/);
  assert.equal(git(remote, 'rev-parse', 'main'), remoteHead);
});

test('divergence preserves both PCs commits and does not merge or force-push', t => {
  const { first, second, remote } = fixture(t);
  const remoteHead = commit(first, 'PC one', 'fix: first PC');
  assert.equal(sync(first, 'push').status, 0);
  const localHead = commit(second, 'PC two', 'fix: second PC');
  for (const action of ['pull', 'push']) assert.notEqual(sync(second, action).status, 0);
  assert.equal(git(second, 'rev-parse', 'HEAD'), localHead);
  assert.equal(git(remote, 'rev-parse', 'main'), remoteHead);
  assert.equal(git(second, 'rev-list', '--count', 'HEAD'), '2');
});

test('a detached HEAD cannot accidentally publish main', t => {
  const { first, remote } = fixture(t);
  const before = git(remote, 'rev-parse', 'main');
  git(first, 'switch', '--detach');
  const result = sync(first, 'push');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /HEAD está separado/);
  assert.equal(git(remote, 'rev-parse', 'main'), before);
});

test('pull of an unpublished branch fails without switching to main', t => {
  const { first } = fixture(t);
  git(first, 'switch', '-c', 'codex/new-work');
  const result = sync(first, 'pull');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /todavía no existe/);
  assert.equal(git(first, 'branch', '--show-current'), 'codex/new-work');
});

test('an explicit named remote is used instead of origin', t => {
  const { first } = fixture(t);
  git(first, 'remote', 'rename', 'origin', 'shared');
  const result = sync(first, 'push', 'shared');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(git(first, 'rev-parse', '--abbrev-ref', '@{upstream}'), 'shared/main');
});

test('invalid actions and remote options fail without modifying the repo', t => {
  const { first } = fixture(t);
  const before = git(first, 'rev-parse', 'HEAD');
  assert.notEqual(sync(first, 'release').status, 0);
  assert.notEqual(sync(first, 'push', '--all').status, 0);
  assert.equal(git(first, 'rev-parse', 'HEAD'), before);
});

test('scripts resolve their repository from their own location, including paths with spaces', t => {
  const { first, root } = fixture(t);
  const result = run(bash, [join(first, 'Scripts', 'sync.sh').replaceAll('\\', '/'), 'status'], root);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Rama: main/);
});

test('PowerShell wrapper passes push/pull and propagates failures', { skip: process.platform !== 'win32' }, t => {
  const { first, second, root } = fixture(t);
  const head = commit(first, 'PowerShell change', 'fix: wrapper');
  const script = join(first, 'Scripts', 'sync.ps1');
  const pushed = run('powershell.exe', ['-NoProfile', '-File', script, '-Action', 'push'], root);
  assert.equal(pushed.status, 0, pushed.stderr);
  const pulled = run('powershell.exe', ['-NoProfile', '-File', join(second, 'Scripts', 'sync.ps1'), 'pull'], root);
  assert.equal(pulled.status, 0, pulled.stderr);
  assert.equal(git(second, 'rev-parse', 'HEAD'), head);
  writeFileSync(join(first, 'code.txt'), 'not committed');
  assert.notEqual(run('powershell.exe', ['-NoProfile', '-File', script, 'push'], root).status, 0);
});

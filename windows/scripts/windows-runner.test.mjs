import assert from 'node:assert/strict';
import {test} from 'node:test';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const runner=fileURLToPath(new URL('./windows.ps1',import.meta.url));
const repo=fileURLToPath(new URL('../../',import.meta.url));
test('native verify isolates workspaces and restores the caller environment on success and failure', {skip:process.platform!=='win32'},()=>{
 const script=String.raw`
 $ErrorActionPreference='Stop'
 $tokens=$null; $errors=$null
 $ast=[System.Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($env:SIDEB_TEST_RUNNER),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw $errors[0]}
 $fn=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Cargo'},$true)
 . ([scriptblock]::Create($fn.Extent.Text))
 $script:RepoRoot=$env:SIDEB_TEST_REPO
 $script:failCargo=$false
 $script:calls=@()
 function cargo { $script:calls+=@{target=$env:CARGO_TARGET_DIR; cwd=(Get-Location).Path; arguments=@($args)}; $global:LASTEXITCODE=if($script:failCargo){17}else{0} }
 $before=(Get-Location).Path
 $env:CARGO_TARGET_DIR='D:\SideB-build-cache\fixture target'
 Invoke-Cargo -Arguments @('test','--locked')
 $successRestored=$env:CARGO_TARGET_DIR
 $script:failCargo=$true
 try { Invoke-Cargo -Arguments @('test'); throw 'expected failure' } catch { if($_ -notmatch 'falló \(17\)'){throw} }
 $failureRestored=$env:CARGO_TARGET_DIR
 $env:CARGO_TARGET_DIR=$null
 $script:failCargo=$false
 Invoke-Cargo -Arguments @('--version')
 @{calls=$script:calls; successRestored=$successRestored; failureRestored=$failureRestored; unsetRestored=($null -eq $env:CARGO_TARGET_DIR); locationRestored=($before -eq (Get-Location).Path)}|ConvertTo-Json -Depth 6 -Compress
 `;
 const result=JSON.parse(execFileSync('powershell.exe',['-NoProfile','-Command',script],{encoding:'utf8',env:{...process.env,SIDEB_TEST_RUNNER:runner,SIDEB_TEST_REPO:repo}}));
 assert.equal(result.successRestored,String.raw`D:\SideB-build-cache\fixture target`);
 assert.equal(result.failureRestored,result.successRestored);
 assert.equal(result.calls[0].target,result.successRestored+'\\core-verify');
 assert.deepEqual(result.calls[0].arguments,['test','--locked']);
 assert.equal(result.calls[1].target,result.calls[0].target);
 assert.equal(result.calls[2].target,null);
 assert.ok(result.unsetRestored&&result.locationRestored);
});

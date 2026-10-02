[CmdletBinding()]
param(
    [ValidateSet('status', 'push', 'pull')]
    [string] $Action = 'status',
    [string] $Remote = 'origin'
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git for Windows no esta instalado.' }
$gitExecPath = & git --exec-path
if ($LASTEXITCODE -ne 0) { throw 'No se pudo localizar Git for Windows.' }
$gitRoot = Split-Path (Split-Path (Split-Path $gitExecPath -Parent) -Parent) -Parent
$gitBash = Join-Path $gitRoot 'bin/bash.exe'
if (-not (Test-Path -LiteralPath $gitBash)) { throw 'No se encontro bash.exe en Git for Windows. Usá bash Scripts/sync.sh desde Git Bash.' }
$syncScript = (Join-Path $PSScriptRoot 'sync.sh').Replace('\', '/')
& $gitBash $syncScript $Action $Remote
exit $LASTEXITCODE

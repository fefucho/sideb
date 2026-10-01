[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('doctor', 'bootstrap', 'verify', 'build', 'package', 'dev')]
    [string] $Action = 'doctor',

    [ValidateSet('debug', 'release')]
    [string] $Configuration = 'release'
)

$ErrorActionPreference = 'Stop'
$script:WindowsDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:RepoRoot = (Resolve-Path (Join-Path $WindowsDir '..')).Path
$script:MpvVersion = 'mpv-dev-x86_64-20260928-git-e470f8986e'
$script:MpvAsset = "$($script:MpvVersion).7z"
$script:MpvUrl = "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260928/$($script:MpvAsset)"
$script:MpvSha256 = '81795d759e01016f1550fd71651a1a5d59ab5c28ef31c0b6793224e9cff39459'

function Get-MpvDir {
    if ($env:SIDEB_MPV_DIR) {
        $resolved = (Resolve-Path -LiteralPath $env:SIDEB_MPV_DIR).Path
        $env:SIDEB_MPV_DIR = $resolved
        if (-not (($env:PATH -split ';') | Where-Object { $_.TrimEnd('\\') -ieq $resolved.TrimEnd('\\') })) {
            $env:PATH = "$resolved;$env:PATH"
        }
        return $resolved
    }
    $defaultPath = Join-Path $WindowsDir '.cache\mpv'
    $env:SIDEB_MPV_DIR = $defaultPath
    if (-not (($env:PATH -split ';') | Where-Object { $_.TrimEnd('\\') -ieq $defaultPath.TrimEnd('\\') })) {
        $env:PATH = "$defaultPath;$env:PATH"
    }
    return $defaultPath
}

function Import-VsDevEnvironment {
    if ($script:VsEnvironmentImported) { return }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw "Visual Studio Installer/vswhere no encontrado: $vswhere" }
    $vsPath = & $vswhere -latest -version '[17.0,18.0)' -products '*' -property installationPath
    if (-not $vsPath) { throw 'No se encontró Visual Studio 2022 (versión 17.x), requerido para el toolchain MSVC.' }
    $vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path -LiteralPath $vcvars)) { throw "No se encontró vcvars64.bat en $vsPath" }

    # Capture vcvars once and import its process environment into this PowerShell process.
    $cmdline = 'call "{0}" >nul && set' -f $vcvars
    $lines = & $env:ComSpec /d /c $cmdline
    if ($LASTEXITCODE -ne 0) { throw "Falló la inicialización MSVC desde $vcvars" }
    foreach ($line in $lines) {
        if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process') }
    }
    $script:VsEnvironmentImported = $true
}

function Require-Command([string] $Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "No se encontró '$Name' en PATH." }
}

function Get-MpvExports([string] $DllPath) {
    $dumpbin = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
    if (-not $dumpbin) { throw 'dumpbin.exe no está disponible tras inicializar Visual Studio.' }
    $lines = & $dumpbin.Source /nologo /exports $DllPath
    if ($LASTEXITCODE -ne 0) { throw "dumpbin falló para $DllPath" }
    $names = foreach ($line in $lines) {
        # dumpbin columns: ordinal, hint, RVA, export name. Ignore forwarded/ordinal-only rows.
        if ($line -match '^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+([A-Za-z_?@$][A-Za-z0-9_?@$]*)\s*$') { $Matches[1] }
    }
    $names = @($names | Sort-Object -Unique)
    if (-not $names.Count) { throw "No se pudieron leer exports de $DllPath (formato dumpbin inesperado)." }
    return $names
}

function Ensure-MpvImportLibrary {
    $mpvDir = Get-MpvDir
    $dll = Join-Path $mpvDir 'libmpv-2.dll'
    if (-not (Test-Path -LiteralPath $dll)) { throw "Falta libmpv-2.dll en $mpvDir. Ejecuta la acción bootstrap." }
    if (Test-Path -LiteralPath (Join-Path $mpvDir 'mpv.lib')) { return }
    Import-VsDevEnvironment
    Require-Command 'lib.exe'
    $exports = Get-MpvExports $dll
    $defPath = Join-Path $mpvDir 'mpv-msvc.def'
    $libPath = Join-Path $mpvDir 'mpv.lib'
    @('LIBRARY libmpv-2.dll', 'EXPORTS') + @($exports | ForEach-Object { "  $_" }) |
        Set-Content -LiteralPath $defPath -Encoding ascii
    & lib.exe /nologo /def:$defPath /machine:x64 /out:$libPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $libPath)) { throw 'No se pudo crear mpv.lib desde los exports del DLL.' }
    Write-Host "Import library MSVC generada: $libPath ($($exports.Count) exports)"
}

function Invoke-Pnpm([string[]] $Arguments) {
    Push-Location $WindowsDir
    try { & pnpm @Arguments; if ($LASTEXITCODE -ne 0) { throw "pnpm $($Arguments -join ' ') falló ($LASTEXITCODE)." } }
    finally { Pop-Location }
}

function Ensure-FrontendDependencies {
    if (-not (Test-Path -LiteralPath (Join-Path $WindowsDir 'node_modules\.bin\tauri.cmd'))) {
        Invoke-Pnpm @('install', '--frozen-lockfile')
    }
}

function Invoke-Cargo([string[]] $Arguments) {
    Push-Location (Join-Path $RepoRoot 'core')
    try { & cargo @Arguments; if ($LASTEXITCODE -ne 0) { throw "cargo $($Arguments -join ' ') falló ($LASTEXITCODE)." } }
    finally { Pop-Location }
}

function Invoke-Tauri([string[]] $Arguments) {
    Push-Location $WindowsDir
    try { & pnpm tauri @Arguments; if ($LASTEXITCODE -ne 0) { throw "Tauri $($Arguments -join ' ') falló ($LASTEXITCODE)." } }
    finally { Pop-Location }
}

function Show-Doctor {
    Write-Host "Repository: $RepoRoot"
    Write-Host "Windows project: $WindowsDir"
    foreach ($name in @('node', 'pnpm', 'cargo', 'rustc')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { Write-Host ("{0}: {1}" -f $name, (& $name --version | Select-Object -First 1)) }
        else { Write-Host "${name}: MISSING" }
    }
    $mpvDir = Get-MpvDir
    Write-Host "SIDEB_MPV_DIR: $mpvDir"
    foreach ($file in @('libmpv-2.dll', 'mpv.lib')) { Write-Host ("{0}: {1}" -f $file, (Test-Path -LiteralPath (Join-Path $mpvDir $file))) }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) { Write-Host ("VS 2022: {0}" -f (& $vswhere -latest -version '[17.0,18.0)' -products '*' -property installationPath)) }
    else { Write-Host 'VS 2022: vswhere missing' }
}

function Bootstrap-Mpv {
    if ($env:SIDEB_MPV_DIR) {
        $providedMpvDir = Get-MpvDir
        Ensure-MpvImportLibrary
        Write-Host "Usando libmpv existente de SIDEB_MPV_DIR: $providedMpvDir"
        return
    }
    $mpvDir = Get-MpvDir
    New-Item -ItemType Directory -Force -Path $mpvDir | Out-Null
    $zip = Join-Path ([IO.Path]::GetTempPath()) $script:MpvAsset
    $staging = Join-Path ([IO.Path]::GetTempPath()) ("sideb-mpv-" + [guid]::NewGuid().ToString('N'))
    try {
        Write-Host "Descargando $($script:MpvAsset)"
        Invoke-WebRequest -Uri $script:MpvUrl -OutFile $zip
        $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $script:MpvSha256) { throw "SHA256 inválido: $actual (esperado $($script:MpvSha256)); no se extraerá el archivo." }
        New-Item -ItemType Directory -Force -Path $staging | Out-Null
        & tar.exe -xf $zip -C $staging
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo extraer el archivo libmpv verificado.' }
        $dll = Join-Path $staging 'libmpv-2.dll'
        if (-not (Test-Path -LiteralPath $dll)) { throw 'El asset verificado no contiene libmpv-2.dll.' }
        Copy-Item -LiteralPath $dll -Destination (Join-Path $mpvDir 'libmpv-2.dll') -Force
        Copy-Item -LiteralPath (Join-Path $staging 'include') -Destination $mpvDir -Recurse -Force
        Remove-Item -LiteralPath (Join-Path $mpvDir 'mpv.lib') -Force -ErrorAction SilentlyContinue
        Import-VsDevEnvironment
        Ensure-MpvImportLibrary
        Write-Host "libmpv $($script:MpvVersion) instalado en $mpvDir"
    } finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        $separator = [IO.Path]::DirectorySeparatorChar
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd($separator) + $separator
        $stageFullPath = [IO.Path]::GetFullPath($staging)
        if ($stageFullPath.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $stageFullPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-Verify {
    Require-Command pnpm; Require-Command cargo
    Ensure-MpvImportLibrary
    Import-VsDevEnvironment
    Invoke-Pnpm @('install', '--frozen-lockfile')
    Invoke-Pnpm @('check')
    Invoke-Pnpm @('test')
    Invoke-Pnpm @('build')
    Invoke-Cargo @('test', '--locked', '-p', 'innertube')
    Invoke-Cargo @('test', '--locked', '-p', 'sideb-core')
    Invoke-Cargo @('test', '--locked', '-p', 'player')
    Push-Location (Join-Path $WindowsDir 'src-tauri')
    try { & cargo test --locked --lib; if ($LASTEXITCODE -ne 0) { throw "cargo test --locked --lib falló ($LASTEXITCODE)." } }
    finally { Pop-Location }
}

switch ($Action) {
    'doctor' { Show-Doctor }
    'bootstrap' { Bootstrap-Mpv }
    'verify' { Invoke-Verify }
    'dev' {
        Require-Command pnpm; Ensure-MpvImportLibrary; Import-VsDevEnvironment
        Ensure-FrontendDependencies
        Invoke-Tauri @('dev')
    }
    'build' {
        Require-Command pnpm; Ensure-MpvImportLibrary; Import-VsDevEnvironment
        Ensure-FrontendDependencies
        # Publish the runnable executable plus its adjacent DLL; a bundle is disabled until it
        # has a real Tauri resource mapping and runtime DLL lookup configured.
        if ($Configuration -eq 'debug') { Invoke-Tauri @('build', '--debug', '--no-bundle', '--', '--locked') }
        else { Invoke-Tauri @('build', '--no-bundle', '--', '--locked') }
    }
    'package' {
        Require-Command pnpm; Ensure-MpvImportLibrary; Import-VsDevEnvironment
        Ensure-FrontendDependencies
        $mpvDir = Get-MpvDir
        $srcTauriDll = Join-Path $WindowsDir 'src-tauri\libmpv-2.dll'
        Copy-Item -LiteralPath (Join-Path $mpvDir 'libmpv-2.dll') -Destination $srcTauriDll -Force
        if ($Configuration -eq 'debug') { Invoke-Tauri @('build', '--debug', '--bundles', 'nsis', '--', '--locked') }
        else { Invoke-Tauri @('build', '--bundles', 'nsis', '--', '--locked') }
    }
}

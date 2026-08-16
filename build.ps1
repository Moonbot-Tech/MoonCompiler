[CmdletBinding()]
param(
  [Parameter(Position = 0, Mandatory = $true)]
  [string]$Target,

  [Parameter(Position = 1)]
  [string]$Profile,

  [string]$Bootstrap,
  [string]$Make
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = $PSScriptRoot
$State = Join-Path $Root '.moonbot'
$Toolchain = Join-Path $State 'toolchain'
$MmSource = Join-Path $Root 'runtime\mm\mormot.core.fpcx64mm.pas'
$MmUnit = 'mormot.core.fpcx64mm'
. (Join-Path $Root 'scripts\Publish-Toolchain.ps1')
. (Join-Path $Root 'scripts\Project-Profile.ps1')

function Invoke-Checked {
  param([string]$File, [string[]]$Arguments)
  & $File @Arguments
  If ($LASTEXITCODE -ne 0) {
    throw "command failed ($LASTEXITCODE): $File $($Arguments -join ' ')"
  }
}

function Find-Bootstrap {
  If ($Bootstrap) {
    return (Resolve-Path -LiteralPath $Bootstrap).Path
  }
  If ($env:MOONBOT_BOOTSTRAP_FPC) {
    return (Resolve-Path -LiteralPath $env:MOONBOT_BOOTSTRAP_FPC).Path
  }
  $found = Get-Command fpc.exe -ErrorAction SilentlyContinue
  If ($found) {
    return $found.Source
  }
  throw 'FPC 3.2.2 is required once. Pass -Bootstrap or set MOONBOT_BOOTSTRAP_FPC.'
}

function Find-Make([string]$BootstrapPath) {
  If ($Make) {
    return (Resolve-Path -LiteralPath $Make).Path
  }
  If ($env:MOONBOT_MAKE) {
    return (Resolve-Path -LiteralPath $env:MOONBOT_MAKE).Path
  }
  $nextToBootstrap = Join-Path (Split-Path -Parent $BootstrapPath) 'make.exe'
  If (Test-Path -LiteralPath $nextToBootstrap) {
    return $nextToBootstrap
  }
  throw 'GNU make.exe was not found. Pass -Make or set MOONBOT_MAKE.'
}

function Build-Compiler {
  $bootstrapPath = Find-Bootstrap
  If ((& $bootstrapPath -iV).Trim() -ne '3.2.2') {
    throw 'the bootstrap compiler must be FPC 3.2.2'
  }
  $makePath = Find-Make $bootstrapPath
  $bootstrapDir = Split-Path -Parent $bootstrapPath
  $fpcmkcfg = Join-Path $bootstrapDir 'fpcmkcfg.exe'
  If (-not (Test-Path -LiteralPath $fpcmkcfg)) {
    throw "fpcmkcfg.exe was not found beside bootstrap compiler: $bootstrapDir"
  }
  $oldPath = $env:Path
  $env:Path = "$bootstrapDir;$oldPath"

  New-Item -ItemType Directory -Force -Path $State | Out-Null
  $newToolchain = Join-Path $State "toolchain.new.$PID"
  $oldToolchain = Join-Path $State "toolchain.old.$PID"
  Remove-Item -LiteralPath $newToolchain, $oldToolchain -Recurse -Force `
    -ErrorAction SilentlyContinue
  try {
    foreach ($part in @('compiler', 'rtl', 'packages', 'utils')) {
      Invoke-Checked $makePath @(
        '-C', (Join-Path $Root $part), 'clean',
        "FPC=$bootstrapPath", 'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    }
    Get-ChildItem -Path (Join-Path $Root '*build-stamp*') -File |
      Remove-Item -Force
    Invoke-Checked $makePath @(
      '-C', $Root, '-j1', 'all', "FPC=$bootstrapPath", 'OPT=-O2',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', $Root, 'install', "FPC=$bootstrapPath", 'OPT=-O2',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "INSTALL_PREFIX=$newToolchain")

    $fpc = Join-Path $newToolchain 'bin\x86_64-win64\fpc.exe'
    $targetCompiler = Join-Path $newToolchain 'bin\x86_64-win64\ppcx64.exe'
    $config = Join-Path $newToolchain 'bin\x86_64-win64\fpc.cfg'
    If (-not (Test-Path -LiteralPath $fpc) -or
        -not (Test-Path -LiteralPath $targetCompiler)) {
      throw 'the installed Win64 toolchain is incomplete'
    }

    # Compiler/IDE tools keep their host representation.  The target RTL and
    # application-facing packages use the modern Delphi Unicode ABI.
    $unicodeOptions = 'OPT=-O2 -dUNICODERTL -dFPC_OS_UNICODE'
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'rtl'), 'clean', "FPC=$targetCompiler",
      'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'rtl'), '-j1', 'all', "FPC=$targetCompiler",
      $unicodeOptions, 'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'rtl'), 'install', "FPC=$targetCompiler",
      $unicodeOptions, 'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "INSTALL_PREFIX=$newToolchain")
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'packages'), 'clean', "FPC=$targetCompiler",
      'FPMAKEOPT=--NoIDE=1', 'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'packages'), '-j1', 'all',
      "FPC=$targetCompiler", $unicodeOptions, 'FPMAKEOPT=--NoIDE=1',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'packages'), 'install',
      "FPC=$targetCompiler", $unicodeOptions, 'FPMAKEOPT=--NoIDE=1',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "INSTALL_PREFIX=$newToolchain")

    Invoke-Checked $fpcmkcfg @(
      '-d', "basepath=$Toolchain", '-o', $config)
    Add-Content -LiteralPath $config -Encoding Ascii -Value @(
      '# Moon Compiler project ABI: Delphi String and Char are Unicode.',
      '-dMOONCOMPILER_UNICODE_DEFAULT')
    foreach ($tool in @('ar', 'as', 'ld', 'nm', 'objcopy', 'objdump', 'strip', 'windres')) {
      $source = Join-Path $bootstrapDir "x86_64-win64-$tool.exe"
      If (-not (Test-Path -LiteralPath $source)) {
        throw "Win64 binutil is missing from bootstrap toolchain: $source"
      }
      Copy-Item -LiteralPath $source `
        -Destination (Join-Path $newToolchain "bin\x86_64-win64\$tool.exe")
    }
    If (-not (Test-Path -LiteralPath $config)) {
      throw 'the installed Win64 toolchain has no fpc.cfg'
    }
    Publish-Toolchain -NewToolchain $newToolchain -Toolchain $Toolchain `
      -OldToolchain $oldToolchain
  } finally {
    $env:Path = $oldPath
    If ((Test-Path -LiteralPath $oldToolchain) -and
        -not (Test-Path -LiteralPath $Toolchain)) {
      Move-Item -LiteralPath $oldToolchain -Destination $Toolchain
    }
    Remove-Item -LiteralPath $newToolchain -Recurse -Force `
      -ErrorAction SilentlyContinue
    If (Test-Path -LiteralPath $Toolchain) {
      Remove-Item -LiteralPath $oldToolchain -Recurse -Force `
        -ErrorAction SilentlyContinue
    }
  }
  Write-Output "MoonBot Compiler installed in $Toolchain"
}

function Get-ProjectId([string]$Project) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Project))
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
  } finally {
    $sha.Dispose()
  }
}

function Build-Project([string]$Project, [string]$BuildProfile) {
  If ($BuildProfile -notin @('debug', 'release')) {
    throw 'project profile must be debug or release'
  }
  $projectPath = [IO.Path]::GetFullPath($Project)
  If (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
    throw "project does not exist: $projectPath"
  }
  If ([IO.Path]::GetExtension($projectPath) -ine '.dpr') {
    throw 'the project must be a .dpr file'
  }
  $fpc = Join-Path $Toolchain 'bin\x86_64-win64\fpc.exe'
  $config = Join-Path $Toolchain 'bin\x86_64-win64\fpc.cfg'
  If (-not (Test-Path -LiteralPath $fpc) -or
      -not (Test-Path -LiteralPath $config)) {
    throw 'MoonBot Compiler is not built. Run .\build.ps1 compiler first.'
  }

  $projectDir = Split-Path -Parent $projectPath
  $projectId = Get-ProjectId $projectPath
  $unitDir = Join-Path $State "units\win64\$projectId\$BuildProfile"
  $appUnitDir = Join-Path $unitDir 'app'
  New-Item -ItemType Directory -Force -Path $appUnitDir | Out-Null
  $namespaceOptions = @(
    '-FNSystem',
    '-UaSystem.SysUtils=SysUtils',
    '-UaSystem.Variants=Variants',
    '-UaSystem.Classes=Classes',
    '-UaSystem.DateUtils=DateUtils',
    '-UaSystem.Math=Math',
    '-UaSystem.Types=Types',
    '-UaSystem.TypInfo=TypInfo',
    '-UaSystem.Rtti=Rtti',
    '-UaSystem.StrUtils=StrUtils',
    '-UaSystem.Character=Character',
    '-UaSystem.SyncObjs=SyncObjs',
    '-UaSystem.Generics.Defaults=Generics.Defaults',
    '-UaSystem.Generics.Collections=Generics.Collections',
    '-UaSystem.IniFiles=IniFiles',
    '-UaSystem.SysConst=SysConst',
    '-UaSystem.RTLConsts=RTLConsts')
  If ($BuildProfile -eq 'debug') {
    $profileOptions = @('-O-', '-gl', '-gw3', '-Criot', '-Sa')
  } else {
    $profileOptions = @('-O3', '-gl', '-gw3')
  }
  $options = @(
    '-n', "@$config", '-Mdelphi',
    '-Municodestrings', '-MduplicateLocals', '-Madvancedrecords',
    '-Marrayoperators', '-Munderscoreisseparator', '-Mfunctionreferences',
    '-Manonymousfunctions', '-Minlinevars', '-Mimplicitgenerics', '-Mautoderef',
    '-Px86_64', '-Twin64', '-Rintel', '-B',
    '-dMOONBOT_MM_PROFILE_REQUIRED', '-dFPCMM_BOOSTER', '-dFPCMM_MOONSHARD',
    "--pinned-unit=$MmUnit=$MmSource",
    "--required-first-unit=$MmUnit")
  $options += $namespaceOptions
  $options += @("-FU$appUnitDir", "-FE$projectDir")

  $projectProfile = Resolve-ProjectProfile $projectPath $projectDir $State
  $options += $projectProfile.Options
  $options += $profileOptions

  Write-Output "building $projectPath ($BuildProfile, Win64 x86-64)"
  Invoke-Checked $fpc ($options + @($projectPath))
}

If ($Target -eq 'compiler') {
  If ($Profile) {
    throw 'usage: .\build.ps1 compiler'
  }
  Build-Compiler
} else {
  Build-Project $Target $Profile
}

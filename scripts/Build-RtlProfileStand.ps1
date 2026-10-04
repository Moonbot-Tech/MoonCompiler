[CmdletBinding()]
param(
  [string]$Bootstrap = 'R:\test\FPC\tools\fpc-3.2.2-win64\install\bin\i386-win32\fpc.exe',
  [string[]]$Variants = @('A', 'B', 'C', 'D'),
  [switch]$SkipBase
)

# RTL profile stand: one compiler, four installations of the product Unicode
# RTL and packages that differ only in the optimization flags of the RTL.
#
#   A  -O2                 exact current product profile
#   B  -O2 -OoCODEALIGN    placement only
#   C  -O3                 full O3 including CODEALIGN
#   D  -O3 -OoNOCODEALIGN  O3 without placement
#
# The compiler, fpcres and the ordinary FPC-ABI units are built once into
# stand\base; every variant is a copy of base whose Unicode RTL and
# packages are rebuilt with its own flags.  Nothing here touches
# toolchain.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
$Stand = Join-Path $Root 'stand'
$Base = Join-Path $Stand 'base'
$MmSource = Join-Path $Root 'runtime\mm\mormot.core.fpcx64mm.pas'
$MmUnit = 'mormot.core.fpcx64mm'
$VariantOpt = @{
  A = '-O2'
  B = '-O2 -OoCODEALIGN'
  C = '-O3'
  D = '-O3 -OoNOCODEALIGN'
  E = '-O3 -OaLOOP=64 -OaPROC=64'
  F = '-O3'
  H = '-O3'
  I = '-O3'
  J = '-O3'
  K = '-O3'
  L = '-O3'
  M = '-O3'
  N = '-O3'
  O = '-O3'
  P = '-O3'
  Q = '-O3'
  R = '-O3'
  S = '-O3'
  T = '-O3'
  U = '-O3'
  V = '-O3'
  W = '-O3'
}
$UnicodeCommon = '-n -gw3 -dMOONCOMPILER_VANILLA_RUNTIME -dUNICODERTL -dFPC_OS_UNICODE -dENABLE_DELPHI_RTTI -dMOONCOMPILER_DELPHI_CALLBACK_TYPES'

function Invoke-Checked {
  param([string]$File, [string[]]$Arguments)
  Write-Output ("+ " + $File + " " + ($Arguments -join ' '))
  & $File @Arguments
  If ($LASTEXITCODE -ne 0) {
    throw "command failed ($LASTEXITCODE): $File $($Arguments -join ' ')"
  }
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$bootstrapPath = (Resolve-Path -LiteralPath $Bootstrap).Path
If ((& $bootstrapPath -iV).Trim() -ne '3.2.2') {
  throw 'the bootstrap compiler must be FPC 3.2.2'
}
$bootstrapDir = Split-Path -Parent $bootstrapPath
$makePath = Join-Path $bootstrapDir 'make.exe'
$fpcmkcfg = Join-Path $bootstrapDir 'fpcmkcfg.exe'
$configTemplate = Join-Path $Root 'scripts\fpc.cfg.win64.template'
$bootstrapInstall = Join-Path $bootstrapDir 'ginstall.exe'
foreach ($required in @($makePath, $fpcmkcfg, $bootstrapInstall)) {
  If (-not (Test-Path -LiteralPath $required)) {
    throw "missing bootstrap tool: $required"
  }
}
$portableTools = Join-Path $Root 'tools'
New-Item -ItemType Directory -Force -Path $portableTools | Out-Null
$portableInstall = Join-Path $portableTools 'gcopy.exe'
Copy-Item -LiteralPath $bootstrapInstall -Destination $portableInstall -Force
$makeInstall = 'GINSTALL=' + ($portableInstall -replace '\\', '/')

$oldPath = $env:Path
$env:Path = "$bootstrapDir;$oldPath"
[Environment]::CurrentDirectory = $Root
Set-Location $Root
try {
  New-Item -ItemType Directory -Force -Path $Stand | Out-Null

  If (-not $SkipBase) {
    Write-Output "=== base: compiler + FPC-ABI units -> $Base"
    Remove-Item -LiteralPath $Base -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($part in @('compiler', 'rtl', 'packages', 'utils')) {
      Invoke-Checked $makePath @(
        '-C', (Join-Path $Root $part), 'clean',
        "FPC=$bootstrapPath", 'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    }
    Get-ChildItem -Path (Join-Path $Root '*build-stamp*') -File |
      Remove-Item -Force
    Invoke-Checked $makePath @(
      '-C', $Root, '-j1', 'all', "FPC=$bootstrapPath",
      'OPT=-O2 -dMOONCOMPILER_PRODUCT_RUNTIME -dMOONCOMPILER_VANILLA_RUNTIME',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', $Root, 'install', "FPC=$bootstrapPath",
      'OPT=-O2 -dMOONCOMPILER_PRODUCT_RUNTIME -dMOONCOMPILER_VANILLA_RUNTIME',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "INSTALL_PREFIX=$Base", $makeInstall)
    $baseFpc = Join-Path $Base 'bin\x86_64-win64\fpc.exe'
    $baseCompiler = Join-Path $Base 'bin\x86_64-win64\ppcx64.exe'
    $baseConfig = Join-Path $Base 'bin\x86_64-win64\moon-base.cfg'
    If (-not (Test-Path -LiteralPath $baseFpc) -or -not (Test-Path -LiteralPath $baseCompiler)) {
      throw 'the base Win64 toolchain is incomplete'
    }
    Invoke-Checked $fpcmkcfg @('-t', $configTemplate, '-d', "basepath=$Base", '-o', $baseConfig)
    $fpcresOptions = 'OPT=-O2 -n -dMOONCOMPILER_VANILLA_RUNTIME'
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'utils\fpcres'), 'clean', "FPC=$baseFpc",
      'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'utils\fpcres'), 'all', "FPC=$baseFpc",
      $fpcresOptions, 'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'utils\fpcres'), 'install', "FPC=$baseFpc",
      $fpcresOptions, 'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "INSTALL_PREFIX=$Base", $makeInstall)
    foreach ($tool in @('ar', 'as', 'ld', 'nm', 'objcopy', 'objdump', 'strip', 'windres')) {
      Copy-Item -LiteralPath (Join-Path $bootstrapDir "x86_64-win64-$tool.exe") `
        -Destination (Join-Path $Base "bin\x86_64-win64\$tool.exe")
    }
    Copy-Item -LiteralPath $fpcmkcfg -Destination (Join-Path $Base 'bin\x86_64-win64\fpcmkcfg.exe')
    Write-Output ("base compiler sha256 " + (Get-Sha256 $baseCompiler))
  }

  foreach ($variant in $Variants) {
    If (-not $VariantOpt.ContainsKey($variant)) {
      throw "unknown variant $variant"
    }
    $target = Join-Path $Stand $variant
    $opt = 'OPT=' + $VariantOpt[$variant] + ' ' + $UnicodeCommon
    Write-Output "=== variant $variant : $opt -> $target"
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $Base -Destination $target -Recurse
    $compiler = Join-Path $target 'bin\x86_64-win64\ppcx64.exe'
    $config = Join-Path $target 'bin\x86_64-win64\moon-base.cfg'

    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'rtl'), 'clean', "FPC=$compiler",
      'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'rtl'), '-j1', 'all', "FPC=$compiler",
      $opt, 'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'rtl'), 'install', "FPC=$compiler",
      $opt, 'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "INSTALL_PREFIX=$target", $makeInstall)
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'packages'), 'clean', "FPC=$compiler",
      'FPMAKEOPT=--NoIDE=1', 'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'packages'), '-j1', 'all',
      "FPC=$compiler", $opt, 'FPMAKEOPT=--NoIDE=1',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64')
    Invoke-Checked $makePath @(
      '-C', (Join-Path $Root 'packages'), 'install',
      "FPC=$compiler", $opt, 'FPMAKEOPT=--NoIDE=1',
      'CPU_TARGET=x86_64', 'OS_TARGET=win64',
      "INSTALL_PREFIX=$target", $makeInstall)

    Invoke-Checked $fpcmkcfg @('-t', $configTemplate, '-d', "basepath=$target", '-o', $config)
    Add-Content -LiteralPath $config -Encoding Ascii -Value @(
      '# MoonCompiler project ABI: Delphi String and Char are Unicode.',
      '-dMOONCOMPILER_UNICODE_DEFAULT',
      '# Product programs receive the bundled runtime prefix automatically.',
      '-dMOONBOT_MM_PROFILE_REQUIRED',
      '-dFPCMM_BOOSTER',
      '-dFPCMM_MOONSHARD',
      '-dNOPATCHRTL',
      "--pinned-unit=$MmUnit=$MmSource")
    $profile = @(
      "variant=$variant",
      "rtl_packages_opt=$opt",
      ("placement_draft=" + [int]($env:MOONCOMPILER_PLACEMENT -ceq '1' -and [string]::IsNullOrEmpty($env:MOONCOMPILER_NO_PLACEMENT))),
      "compiler_sha256=" + (Get-Sha256 $compiler),
      "sysutils_ppu_sha256=" + (Get-Sha256 (Join-Path $target 'units\x86_64-win64\rtl\sysutils.ppu')),
      "sysutils_o_sha256=" + (Get-Sha256 (Join-Path $target 'units\x86_64-win64\rtl\sysutils.o')),
      "generics_hashes_o_sha256=" + (Get-Sha256 (Join-Path $target 'units\x86_64-win64\rtl-generics\generics.hashes.o')),
      "rtl_asm_x86_64_sha256=" + (Get-Sha256 (Join-Path $Root 'rtl\x86_64\x86_64.inc')),
      "rtl_asm_strings_sha256=" + (Get-Sha256 (Join-Path $Root 'rtl\x86_64\strings.inc')),
      "rtl_asm_sets_sha256=" + (Get-Sha256 (Join-Path $Root 'rtl\x86_64\set.inc')),
      "rtl_asm_threadvar_sha256=" + (Get-Sha256 (Join-Path $Root 'rtl\win\systhrd.inc')),
      "rtl_asm_math_sha256=" + (Get-Sha256 (Join-Path $Root 'rtl\objpas\math.pp')),
      "rtl_asm_sysstrings_sha256=" + (Get-Sha256 (Join-Path $Root 'rtl\objpas\sysutils\sysstr.inc')),
      "rtl_asm_hashes_sha256=" + (Get-Sha256 (Join-Path $Root 'packages\rtl-generics\src\generics.hashes.pas')),
      "rtl_asm_astrings_sha256=" + (Get-Sha256 (Join-Path $Root 'rtl\inc\astrings.inc')),
      "rtl_asm_ustrings_sha256=" + (Get-Sha256 (Join-Path $Root 'rtl\inc\ustrings.inc')),
      "built_utc=" + [DateTime]::UtcNow.ToString('o'))
    Set-Content -LiteralPath (Join-Path $target 'profile.txt') -Value $profile -Encoding Ascii
    Write-Output ($profile -join "`n")
  }
  Write-Output 'STAND_BUILD_OK'
} finally {
  $env:Path = $oldPath
}

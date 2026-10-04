# build.ps1 - build one stand program with one installed MoonCompiler toolchain
# into build\<program>-<tag>-f<filler>, with the product Pulse options
# (-Mdelphi -O3, the bundled MM the toolchain pins, placement families
# through -dPULSE_FILLER_k like pulse.py).
#
#   .\build.ps1 -Toolchain <dir> -Tag baseline [-Program dict_bench] [-Fillers 0,1,2,3] [-Define ORACLE_ORDERFREE] [-Generics <src dir>]
#
# <dir> is an installed toolchain (bin\x86_64-win64\moon-base.cfg inside), for
# example <checkout>\toolchain or the toolchain of
# a worktree checked out at the baseline commit.  -Generics compiles the
# Generics units from that source tree instead of the toolchain's PPUs (a
# variant of packages/rtl-generics/src, e.g. the flat path with another hash).
param(
  [Parameter(Mandatory = $true)][string]$Toolchain,
  [Parameter(Mandatory = $true)][string]$Tag,
  [string]$Program = 'dict_bench',
  [string]$Fillers = '0',
  [string[]]$Define = @(),
  [string]$Generics = ''
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = (Resolve-Path (Join-Path $here '..\..\..\..')).Path
$common = Join-Path $root 'qualification\performance\common'
$bin = Join-Path $Toolchain 'bin\x86_64-win64'
$ppc = Join-Path $bin 'ppcx64.exe'
$cfg = Join-Path $bin 'moon-base.cfg'
foreach ($required in @($ppc, $cfg)) {
  If (-not (Test-Path -LiteralPath $required)) { throw "missing: $required" }
}
# the bundled MM is the one the toolchain's moon-base.cfg pins (a worktree toolchain
# pins its own copy; a second --pinned-unit with another path is rejected)
$mm = (Get-Content -LiteralPath $cfg | Where-Object { $_ -like '--pinned-unit=mormot.core.fpcx64mm=*' } |
  Select-Object -First 1) -replace '^--pinned-unit=mormot.core.fpcx64mm=', ''
If (-not $mm) { $mm = Join-Path $root 'runtime\mm\mormot.core.fpcx64mm.pas' }
If (-not (Test-Path -LiteralPath $mm)) { throw "missing MM source: $mm" }
foreach ($f in $Fillers.Split(',')) {
  $out = Join-Path $here "build\$Program-$Tag-f$f"
  If (Test-Path $out) { Remove-Item -Recurse -Force $out }
  New-Item -ItemType Directory -Force $out | Out-Null
  $args = @('-n', "@$cfg", '-Mdelphi', '-O3', '-B',
    "-Fu$common", "-Fi$common", "-Fo$common", "-Fu$here", "-Fi$here",
    "-FU$out", "-FE$out",
    '-uMOONCOMPILER_VANILLA_RUNTIME', '-dFPCMM_BOOSTER', '-dFPCMM_MOONSHARD', '-dNOPATCHRTL',
    '-dMOONBOT_MM_PROFILE_REQUIRED',
    "--pinned-unit=mormot.core.fpcx64mm=$mm", '--required-first-unit=mormot.core.fpcx64mm',
    "-Fu$(Split-Path $mm)")
  If ($Generics) { $args += @("-Fu$Generics", "-Fi$(Join-Path $Generics 'inc')") }
  foreach ($d in $Define) { $args += "-d$d" }
  If ($f -ne '0') { $args += "-dPULSE_FILLER_$f" }
  $args += (Join-Path $here "$Program.dpr")
  Write-Host "== $Program $Tag filler $f ($Toolchain)"
  & $ppc @args 2>&1 | Tee-Object -FilePath (Join-Path $out 'build.log') |
    Select-String -Pattern 'Error|Fatal' | Select-Object -First 8
  If (-not (Test-Path (Join-Path $out "$Program.exe"))) {
    Get-Content (Join-Path $out 'build.log') | Select-Object -Last 15
    throw "build failed: $out"
  }
}
Write-Host 'done'

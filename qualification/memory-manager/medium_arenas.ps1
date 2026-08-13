param(
  [string]$Compiler = "$PSScriptRoot\..\..\.moonbot\toolchain\bin\x86_64-win64\fpc.exe",
  [string]$Config = "$PSScriptRoot\..\..\.moonbot\toolchain\bin\x86_64-win64\fpc.cfg"
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
$Mm = Join-Path $Root 'runtime\mm\mormot.core.fpcx64mm.pas'
$Source = Join-Path $PSScriptRoot 'medium_arenas.dpr'
$Output = Join-Path $Root '.qualification\medium-arenas'

Remove-Item -LiteralPath $Output -Recurse -Force -ErrorAction SilentlyContinue
foreach ($Case in @(
    @{ Name = 'o2'; Options = @('-O2') },
    @{ Name = 'o3'; Options = @('-O3') },
    @{ Name = 'diagnostic'; Options = @('-O3', '-dFPCX64MM_DIAGNOSTIC') }
  )) {
  $CaseOutput = Join-Path $Output $Case.Name
  New-Item -ItemType Directory -Force -Path $CaseOutput | Out-Null
  $Options = @(
    '-n', "@$Config", '-Mdelphi', '-Twin64', '-Px86_64', '-B',
    '-dMOONBOT_MM_PROFILE_REQUIRED', '-dFPCMM_BOOSTER', '-dFPCMM_MOONSHARD',
    "--pinned-unit=mormot.core.fpcx64mm=$Mm",
    "-FU$CaseOutput", "-FE$CaseOutput") + $Case.Options + @($Source)
  & $Compiler @Options *> (Join-Path $CaseOutput 'build.log')
  If ($LASTEXITCODE -ne 0) {
    throw "medium arena $($Case.Name) did not compile"
  }
  & (Join-Path $CaseOutput 'medium_arenas.exe') `
    *> (Join-Path $CaseOutput 'run.log')
  If ($LASTEXITCODE -ne 0 -or
      -not (Select-String -LiteralPath (Join-Path $CaseOutput 'run.log') `
        -Pattern '^PASS owners=' -Quiet)) {
    throw "medium arena $($Case.Name) failed"
  }
}
Write-Output 'medium arenas Win64: PASS'

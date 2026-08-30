param(
  [string]$Compiler = "$PSScriptRoot\..\..\.moonbot\toolchain\bin\x86_64-win64\fpc.exe",
  [string]$Config = "$PSScriptRoot\..\..\.moonbot\toolchain\bin\x86_64-win64\fpc.cfg"
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
$Mm = Join-Path $Root 'runtime\mm\mormot.core.fpcx64mm.pas'
$Source = Join-Path $PSScriptRoot 'medium_single.dpr'
$Output = Join-Path $Root '.qualification\mm-profile-contract'

Remove-Item -LiteralPath $Output -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$Output\negative", `
  "$Output\disable", "$Output\standalone", "$Output\positive" | Out-Null

$Base = @(
  '-n', "@$Config", '-Mdelphi', '-Twin64', '-Px86_64', '-B',
  '-dMOONBOT_MM_PROFILE_REQUIRED',
  '-uFPCMM_BOOSTER', '-uFPCMM_MOONSHARD',
  '-uFPCMM_DISABLE', '-uFPCMM_STANDALONE',
  "--pinned-unit=mormot.core.fpcx64mm=$Mm",
  '--required-first-unit=mormot.core.fpcx64mm')

function Assert-Rejected([string]$Name, [string[]]$Defines, [string]$Diagnostic) {
  $Case = Join-Path $Output $Name
  & $Compiler @Base @Defines "-FU$Case" "-FE$Case" $Source *> "$Case.log"
  If ($LASTEXITCODE -eq 0) { throw "MM profile $Name was accepted" }
  If (-not (Select-String -LiteralPath "$Case.log" -SimpleMatch $Diagnostic -Quiet)) {
    throw "MM profile $Name failed for an unexpected reason"
  }
}

Assert-Rejected negative @() 'MoonBot MM profile requires FPCMM_BOOSTER'
Assert-Rejected disable @('-dFPCMM_BOOSTER', '-dFPCMM_MOONSHARD', `
  '-dFPCMM_DISABLE') 'MoonBot MM profile forbids FPCMM_DISABLE'
Assert-Rejected standalone @('-dFPCMM_BOOSTER', '-dFPCMM_MOONSHARD', `
  '-dFPCMM_STANDALONE') 'MoonBot MM profile forbids FPCMM_STANDALONE'

& $Compiler @Base '-dFPCMM_BOOSTER' '-dFPCMM_MOONSHARD' `
  "-FU$Output\positive" "-FE$Output\positive" $Source `
  *> "$Output\positive.log"
If ($LASTEXITCODE -ne 0) {
  throw 'the required MM profile did not compile'
}
& "$Output\positive\medium_single.exe" *> "$Output\positive.out"
If ($LASTEXITCODE -ne 0 -or
    -not (Select-String -LiteralPath "$Output\positive.out" `
      -SimpleMatch 'PASS' -Quiet)) {
  throw 'the required MM profile did not run successfully'
}

Write-Output 'MM profile contract: PASS'

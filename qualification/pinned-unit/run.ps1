param(
  [string]$Compiler = (Join-Path $PSScriptRoot `
    '..\..\.moonbot\toolchain\bin\x86_64-win64\ppcx64.exe')
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$FixtureRoot = (Resolve-Path $PSScriptRoot).Path
$Pinned = (Resolve-Path (Join-Path $PSScriptRoot 'pinned\PinFixture.pas')).Path
$Foreign = (Resolve-Path (Join-Path $PSScriptRoot 'foreign')).Path
$Rtl = Join-Path $Root 'rtl\units\x86_64-win64'
$Output = Join-Path $Root '.qualification\pinned-unit'
$StalePpu = Join-Path $Output 'stale-ppu'

Remove-Item -LiteralPath $Output -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $Output | Out-Null
New-Item -ItemType Directory -Path $StalePpu | Out-Null

& $Compiler -n -Mdelphi -O2 -B "-Fu$Rtl" "-FU$StalePpu" `
  (Join-Path $Foreign 'PinFixture.pas') *> (Join-Path $StalePpu 'build.log')
If ($LASTEXITCODE -ne 0) {
  throw 'could not prepare the stale PPU fixture'
}

function Invoke-Compile {
  param(
    [string]$Program,
    [string]$CaseName = '',
    [string[]]$ExtraOptions = @(),
    [switch]$MustFail,
    [string]$ExpectedDiagnostic = ''
  )

  $Case = If ($CaseName) { $CaseName } else { [IO.Path]::GetFileNameWithoutExtension($Program) }
  $CaseOutput = Join-Path $Output $Case
  New-Item -ItemType Directory -Path $CaseOutput | Out-Null
  $Options = @(
    '-n', '-Mdelphi', '-O2', '-B',
    "-Fu$Rtl", "-Fu$StalePpu", "-Fu$Foreign", "-FU$CaseOutput", "-FE$CaseOutput",
    "-o$(Join-Path $CaseOutput "$Case.exe")"
  ) + $ExtraOptions + (Join-Path $FixtureRoot $Program)
  & $Compiler @Options *> (Join-Path $CaseOutput 'build.log')
  $Succeeded = $LASTEXITCODE -eq 0
  If ($MustFail) {
    If ($Succeeded) {
      throw "$Program unexpectedly compiled"
    }
    If ($ExpectedDiagnostic -and
        ((Get-Content -Raw (Join-Path $CaseOutput 'build.log')) -notlike
          "*$ExpectedDiagnostic*")) {
      throw "$Program returned an unexpected diagnostic"
    }
    return
  }
  If (-not $Succeeded) {
    throw "$Program did not compile"
  }
  & (Join-Path $CaseOutput "$Case.exe")
  If ($LASTEXITCODE -ne 0) {
    throw "$Program returned $LASTEXITCODE"
  }
}

$PinOption = "--pinned-unit=PinFixture=$Pinned"
Invoke-Compile 'source_wins.dpr' 'source_wins' @($PinOption)
Invoke-Compile 'explicit_source_rejected.dpr' 'explicit_source_rejected' @($PinOption) `
  -MustFail -ExpectedDiagnostic 'cannot use explicit source file'
Invoke-Compile 'source_wins.dpr' 'missing_source_rejected' @('--pinned-unit=PinFixture=Z:\missing\PinFixture.pas') `
  -MustFail -ExpectedDiagnostic 'no sources available'
Invoke-Compile 'normal_lookup.dpr'
Invoke-Compile 'foreign_lookup.dpr'
Invoke-Compile 'source_wins.dpr' 'required_first' @(
  $PinOption, '--required-first-unit=PinFixture')
Invoke-Compile 'normal_lookup.dpr' 'required_missing' @(
  '--required-first-unit=PinFixture') -MustFail `
  -ExpectedDiagnostic 'first explicit unit is NORMALFIXTURE'
Invoke-Compile 'no_uses_rejected.dpr' 'required_no_uses' @(
  '--required-first-unit=PinFixture') -MustFail `
  -ExpectedDiagnostic 'first explicit unit is <none>'
Invoke-Compile 'second_unit_rejected.dpr' 'required_second' @(
  $PinOption, '--required-first-unit=PinFixture') -MustFail `
  -ExpectedDiagnostic 'first explicit unit is NORMALFIXTURE'
Invoke-Compile 'conditional_first_rejected.dpr' 'required_conditional' @(
  $PinOption, '--required-first-unit=PinFixture') -MustFail `
  -ExpectedDiagnostic 'first explicit unit is NORMALFIXTURE'

Write-Host 'pinned-unit: PASS'

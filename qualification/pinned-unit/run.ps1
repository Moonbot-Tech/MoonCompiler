param(
  [string]$Compiler = (Join-Path $PSScriptRoot `
    '..\..\.moonbot\toolchain\bin\x86_64-win64\ppcx64.exe')
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$FixtureRoot = (Resolve-Path $PSScriptRoot).Path
$Pinned = (Resolve-Path (Join-Path $PSScriptRoot 'pinned\PinFixture.pas')).Path
$Foreign = (Resolve-Path (Join-Path $PSScriptRoot 'foreign')).Path
$Mm = (Resolve-Path (Join-Path $Root 'runtime\mm\mormot.core.fpcx64mm.pas')).Path
$Rtl = Join-Path $Root 'rtl\units\x86_64-win64'
$MonitorUnits = Join-Path $Root '.moonbot\toolchain\units\x86_64-win64\rtl-objpas'
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
    [string]$ExpectedDiagnostic = '',
    [switch]$WithoutProductMmPin
  )

  $Case = If ($CaseName) { $CaseName } else { [IO.Path]::GetFileNameWithoutExtension($Program) }
  $CaseOutput = Join-Path $Output $Case
  New-Item -ItemType Directory -Path $CaseOutput | Out-Null
  $Options = @(
    '-n', '-Mdelphi', '-O2', '-B',
    "-Fu$Rtl", "-Fu$MonitorUnits", "-Fu$StalePpu", "-Fu$Foreign",
    "-FU$CaseOutput", "-FE$CaseOutput",
    "-o$(Join-Path $CaseOutput "$Case.exe")"
  )
  If (-not $WithoutProductMmPin) {
    $Options += "--pinned-unit=mormot.core.fpcx64mm=$Mm"
  }
  $Options += $ExtraOptions + (Join-Path $FixtureRoot $Program)
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
    throw "$Case did not compile"
  }
  & (Join-Path $CaseOutput "$Case.exe")
  If ($LASTEXITCODE -ne 0) {
    throw "$Program returned $LASTEXITCODE"
  }
}

$PinOption = "--pinned-unit=PinFixture=$Pinned"
$Vanilla = '-dMOONCOMPILER_VANILLA_RUNTIME'
Invoke-Compile 'source_wins.dpr' 'source_wins' @($PinOption)
Invoke-Compile 'explicit_source_rejected.dpr' 'explicit_source_rejected' @($PinOption) `
  -MustFail -ExpectedDiagnostic 'cannot use explicit source file'
Invoke-Compile 'source_wins.dpr' 'missing_source_rejected' @('--pinned-unit=PinFixture=Z:\missing\PinFixture.pas') `
  -MustFail -ExpectedDiagnostic 'no sources available'
Invoke-Compile 'normal_lookup.dpr'
Invoke-Compile 'foreign_lookup.dpr'
Invoke-Compile 'source_wins.dpr' 'required_first' @(
  $Vanilla, $PinOption, '--required-first-unit=PinFixture')
Invoke-Compile 'required_prefix.dpr' 'required_prefix' @(
  $Vanilla, $PinOption, '--required-first-unit=PinFixture,NormalFixture')
Invoke-Compile 'source_wins.dpr' 'required_prefix_missing_second' @(
  $Vanilla, $PinOption, '--required-first-unit=PinFixture,NormalFixture') -MustFail `
  -ExpectedDiagnostic 'explicit unit 2 is <none>'
Invoke-Compile 'normal_lookup.dpr' 'required_missing' @(
  $Vanilla, '--required-first-unit=PinFixture') -MustFail `
  -ExpectedDiagnostic 'first explicit unit is NORMALFIXTURE'
Invoke-Compile 'no_uses_rejected.dpr' 'required_no_uses' @(
  $Vanilla, '--required-first-unit=PinFixture') -MustFail `
  -ExpectedDiagnostic 'first explicit unit is <none>'
Invoke-Compile 'second_unit_rejected.dpr' 'required_second' @(
  $Vanilla, $PinOption, '--required-first-unit=PinFixture') -MustFail `
  -ExpectedDiagnostic 'first explicit unit is NORMALFIXTURE'
Invoke-Compile 'conditional_first_rejected.dpr' 'required_conditional' @(
  $Vanilla, $PinOption, '--required-first-unit=PinFixture') -MustFail `
  -ExpectedDiagnostic 'first explicit unit is NORMALFIXTURE'
Invoke-Compile 'no_uses_rejected.dpr' 'product_runtime_missing_pin' `
  -MustFail -WithoutProductMmPin `
  -ExpectedDiagnostic 'requires an exact --pinned-unit mapping'
Invoke-Compile 'no_uses_rejected.dpr' 'product_runtime_vanilla' `
  @($Vanilla) -WithoutProductMmPin
Invoke-Compile 'cmem_override.dpr' 'product_runtime_cmem_override' `
  -MustFail -ExpectedDiagnostic 'would replace the bundled product memory manager'
Invoke-Compile 'cmem_override.dpr' 'product_runtime_cmem_vanilla' @($Vanilla)
Invoke-Compile 'cmem_override.dpr' 'product_runtime_cmem_valgrind' @('-gv')

Write-Host 'pinned-unit: PASS'

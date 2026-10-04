[CmdletBinding()]
param(
  [int]$BuildTimeoutMinutes = 60,
  [int]$BuildPollSeconds = 20
)
# Variant E chain: wait for the E build, run the program-filler placement probe
# on C+app64 and E+app64, then the placement-controlled quick Pulse A vs E, then
# RTL-test and Light on E.  Writes stand\chain-E-summary.log.

$ErrorActionPreference = 'Continue'
$W = Split-Path -Parent $PSScriptRoot
[Environment]::CurrentDirectory = $W
Set-Location $W
$S = "$W\stand"
$L = "$S\chain-E-summary.log"
$uv = 'C:\files\utils\python\uv.exe'
$nm = 'C:\Files\utils\mingw64\bin\nm.exe'
$mm = "$W\runtime\mm\mormot.core.fpcx64mm.pas"

function Fail-Chain([string]$Stage, [int]$Code) {
  $env:PULSE_HOT_RTL_ADDR = $null
  $env:MOONBOT_TOOLCHAIN = $null
  If ($Code -eq 0) { $Code = 1 }
  "CHAIN_E_FAILED stage=$Stage exit=$Code" | Add-Content $L
  exit $Code
}

function Require-Success([string]$Stage, [int]$Code) {
  "$Stage exit=$Code $(Get-Date -Format s)" | Add-Content $L
  If ($Code -ne 0) { Fail-Chain $Stage $Code }
}

trap {
  "CHAIN_E_FAILED error=$($_.Exception.Message)" | Add-Content $L
  $env:PULSE_HOT_RTL_ADDR = $null
  $env:MOONBOT_TOOLCHAIN = $null
  exit 1
}
$ErrorActionPreference = 'Stop'
"chain E start $(Get-Date -Format s)" | Add-Content $L

$buildReady = $false
$deadline = (Get-Date).AddMinutes($BuildTimeoutMinutes)
while ((Get-Date) -lt $deadline) {
  If (Test-Path -LiteralPath "$S\build-win64-E.log") {
    If (Select-String -LiteralPath "$S\build-win64-E.log" -Pattern 'STAND_BUILD_OK' -Quiet) {
      $buildReady = $true
      break
    }
    If (Select-String -LiteralPath "$S\build-win64-E.log" -Pattern 'command failed' -Quiet) {
      Fail-Chain 'E build' 1
    }
  }
  Start-Sleep -Seconds $BuildPollSeconds
}
If (-not $buildReady) { Fail-Chain 'E build timeout' 124 }
"E build ready $(Get-Date -Format s)" | Add-Content $L

# --- program-filler probe: RTL C or E, program aligned to 64 ---
$env:PULSE_HOT_RTL_ADDR = '1'
$probe = "$S\probe-E-placement.md"
"| RTL | pf | asm mod64 | CompareText entry/loops mod64 | asm-equal-128 | asm-fold-12 | sametext-equal-128 | sametext-fold-12 |" | Set-Content $probe
"| --- | --- | ---: | --- | --- | --- | --- | --- |" | Add-Content $probe
foreach ($tcn in @('C', 'E')) {
  foreach ($pf in @(0, 1, 2, 3)) {
    $tc = "$S\$tcn"; $pp = "$tc\bin\x86_64-win64\ppcx64.exe"; $cfg = "$tc\bin\x86_64-win64\moon-base.cfg"
    $out = "$W\probe\pf64-$tcn-$pf"; New-Item -ItemType Directory -Force $out | Out-Null
    $extra = @('-OaLOOP=64', '-OaPROC=64'); if ($pf -gt 0) { $extra += "-dPULSE_PROGRAM_FILLER_$pf" }
    $a = @('-n', "@$cfg", '-Mdelphi', '-O3', '-B', '-gw3') + $extra + @("-Fu$W\qualification\performance\common", "-Fi$W\qualification\performance\common", "-Fu$W\qualification\performance\hot-rtl", "-Fi$W\qualification\performance\hot-rtl", "-Fo$W\qualification\performance\hot-rtl", "-FE$out", "-FU$out", '-uMOONCOMPILER_VANILLA_RUNTIME', '-dFPCMM_BOOSTER', '-dFPCMM_MOONSHARD', '-dNOPATCHRTL', '-dMOONBOT_MM_PROFILE_REQUIRED', "--pinned-unit=mormot.core.fpcx64mm=$mm", '--required-first-unit=mormot.core.fpcx64mm', "-Fu$W\runtime\mm", "$W\qualification\performance\hot-rtl\pulse_hot-rtl.dpr")
    $o = & $pp @a 2>&1
    Require-Success "probe build $tcn/$pf" $LASTEXITCODE
    $exe = "$out\pulse_hot-rtl.exe"
    $nmOutput = & $nm $exe
    Require-Success "probe nm $tcn/$pf" $LASTEXITCODE
    $asmAddress = $nmOutput | Select-String ' T asm_sametext_pair_content' |
      ForEach-Object { ($_.Line -split ' ')[0] } | Select-Object -First 1
    If (-not $asmAddress) { Fail-Chain "probe asm symbol $tcn/$pf" 1 }
    $asm = [Convert]::ToInt64($asmAddress, 16)
    & $uv run python qualification/performance/tools/code_placement.py scan $exe --match 'SYSUTILS_\$\$_COMPARETEXT\$UNICODESTRING\$UNICODESTRING' --json "$out\ct.json" --quiet | Out-Null
    Require-Success "probe placement $tcn/$pf" $LASTEXITCODE
    $ct = Get-Content "$out\ct.json" -Raw | ConvertFrom-Json
    If (-not $ct.procedures -or $ct.procedures.Count -ne 1) {
      Fail-Chain "probe placement identity $tcn/$pf" 1
    }
    $ctText = "e" + $ct.procedures[0].entry_mod64 + " l[" + (($ct.procedures[0].loops | ForEach-Object { $_.target_mod64 }) -join ',') + "]"
    $cells = @()
    foreach ($case in @('asm-sametext-equal-128', 'asm-sametext-fold-12', 'sametext-equal-128', 'sametext-fold-12')) {
      $vals = @()
      for ($r = 0; $r -lt 3; $r++) {
        $caseOutput = & $exe quick $case 2>$null
        Require-Success "probe case $tcn/$pf/$case/$r" $LASTEXITCODE
        $t = $caseOutput | Select-String 'PULSE_TOTAL' | ForEach-Object { $f = $_.Line -split ' '; $ops = [double](($f | Where-Object { $_ -like 'operations=*' }) -replace 'operations=', ''); $cy = [double](($f | Where-Object { $_ -like 'thread_cycles=*' }) -replace 'thread_cycles=', ''); [math]::Round($cy / $ops, 1) }
        If ($null -eq $t) { Fail-Chain "probe result $tcn/$pf/$case/$r" 1 }
        $vals += $t
      }
      $cells += ($vals -join '/')
    }
    "| $tcn | $pf | $($asm % 64) | $ctText | $($cells -join ' | ') |" | Add-Content $probe
  }
}
$env:PULSE_HOT_RTL_ADDR = $null
"probe done $(Get-Date -Format s)" | Add-Content $L

# --- placement-controlled quick Pulse: A family vs E family (program aligned to 64 for E) ---
& $uv run python qualification/performance/tools/pulse.py run --mode quick --programs hot-rtl,repairs,heartbeat --systems A,A1,A2,A3,E,E1,E2,E3 --moon-system A=stand/A --moon-system A1=stand/A --moon-system A2=stand/A --moon-system A3=stand/A --moon-system E=stand/E --moon-system E1=stand/E --moon-system E2=stand/E --moon-system E3=stand/E --moon-system-option A1=-dPULSE_FILLER_1 --moon-system-option A2=-dPULSE_FILLER_2 --moon-system-option A3=-dPULSE_FILLER_3 --moon-system-option E1=-dPULSE_FILLER_1 --moon-system-option E2=-dPULSE_FILLER_2 --moon-system-option E3=-dPULSE_FILLER_3 --moon-system-option E=-OaLOOP=64 --moon-system-option E=-OaPROC=64 --moon-system-option E1=-OaLOOP=64 --moon-system-option E1=-OaPROC=64 --moon-system-option E2=-OaLOOP=64 --moon-system-option E2=-OaPROC=64 --moon-system-option E3=-OaLOOP=64 --moon-system-option E3=-OaPROC=64 --moon-extra-option=-gw3 --tag stand-win64-filler-E *> "$S\pulse-win64-filler-E.log"
Require-Success 'filler pulse A vs E' $LASTEXITCODE
& $uv run python qualification/performance/tools/filler_summary.py qualification/performance/results/pulse/stand-win64-filler-E --left A --right E *> "$S\filler-win64-AvsE.md"
Require-Success 'filler summary A vs E' $LASTEXITCODE

# --- semantics on E ---
$env:MOONBOT_TOOLCHAIN = "$S\E"
& $uv run python RTL-test/run.py *> "$S\rtltest-E.log"
Require-Success 'RTL-test E' $LASTEXITCODE
& $uv run python qualification/suite/scripts/run_devil_targeted.py light --run-id stand-E-light *> "$S\light-E.log"
Require-Success 'light E' $LASTEXITCODE
$env:MOONBOT_TOOLCHAIN = $null
"CHAIN_E_DIAGNOSTIC_DONE evidence=quick-only" | Add-Content $L
exit 2

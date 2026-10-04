[CmdletBinding()]
param([string]$Variant = 'F', [string]$Baseline = 'C', [string]$Assert = 'R4', [string]$Run = (Get-Date -Format 'HHmm'), [string]$ExpectFaster = '', [string]$AllowSlower = '', [switch]$SkipSemantics)
# Variant chain for a compiler placement rule: config gate, compiler
# self-build gate, gate on the fixture, MM layout gate and MM profile matrix
# (qualification/memory-manager),
# medium Pulse (baseline family vs variant family, placement
# fillers), the acceptance gate (stand_ab_gate.py: quiet run, geomean not
# worse, the cases named in -ExpectFaster faster, no other case slower beyond
# placement unless named in -AllowSlower), placement statistics on the Pulse
# executables, RTL-test and Light on the variant.  Writes
# stand\chain-<Variant>-<Run>-summary.log.  The Linux twin is
# scripts/stand-chain.sh; a placement change is accepted only when the
# acceptance gate passes on both machines.

$ErrorActionPreference = 'Continue'
# the chain judges variants of the code placement draft, which is off by default
# (doc/OPTIMIZER.md, "Code placement"): every compile of the chain runs with it
$env:MOONCOMPILER_PLACEMENT = '1'
$W = Split-Path -Parent $PSScriptRoot
[Environment]::CurrentDirectory = $W
Set-Location $W
$S = "$W\stand"
$L = "$S\chain-$Variant-$Run-summary.log"
$uv = 'C:\files\utils\python\uv.exe'
$mm = "$W\runtime\mm\mormot.core.fpcx64mm.pas"
$tools = "$W\qualification\performance\tools"
$failedStages = [Collections.Generic.List[string]]::new()

If ([string]::IsNullOrWhiteSpace($ExpectFaster)) {
  "CHAIN_${Variant}_INCONCLUSIVE reason=no-expected-buyer" | Add-Content $L
  exit 2
}

function Record-Stage([string]$Name, [int]$Code) {
  "$Name exit=$Code" | Add-Content $L
  If ($Code -ne 0) { $failedStages.Add($Name) }
}

function Finish-Chain {
  If ($failedStages.Count -ne 0) {
    "CHAIN_${Variant}_FAILED stages=$($failedStages -join ',')" | Add-Content $L
    exit 1
  }
  "CHAIN_${Variant}_DONE" | Add-Content $L
  exit 0
}

"chain $Variant start $(Get-Date -Format s)" | Add-Content $L

# --- fixture gate ---
$tc = "$S\$Variant"; $pp = "$tc\bin\x86_64-win64\ppcx64.exe"; $cfg = "$tc\bin\x86_64-win64\moon-base.cfg"
& $uv run python qualification/build-driver/config_contract_gate.py --config $cfg --profile product --compiler $pp *>> $L
Record-Stage 'config gate' $LASTEXITCODE
$standMake = If ($env:MOONBOT_MAKE) { $env:MOONBOT_MAKE } Else { 'R:\test\FPC\tools\fpc-3.2.2-win64\install\bin\i386-win32\make.exe' }
$env:MOONBOT_MAKE = $standMake  # rtl_asm_layout_gate.py below rebuilds units with the RTL make's command lines
& $uv run python qualification/build-driver/rtl_profile_gate.py --toolchain $tc --no-declared --make $standMake *>> $L
Record-Stage 'rtl profile gate' $LASTEXITCODE
$baselineTc = "$S\$Baseline"
& $uv run python qualification/build-driver/rtl_profile_gate.py --toolchain $baselineTc --no-declared --make $standMake *>> $L
Record-Stage 'baseline rtl profile gate' $LASTEXITCODE
& $uv run python qualification/build-driver/compiler_selfbuild_gate.py --compiler $pp --config "$S\base\bin\x86_64-win64\moon-base.cfg" --product-config $cfg --msg2inc "$S\base\bin\x86_64-win64\msg2inc.exe" *> "$S\gate-selfbuild-$Variant-$Run.md"
Record-Stage 'compiler selfbuild gate' $LASTEXITCODE
Get-Content "$S\gate-selfbuild-$Variant-$Run.md" | Select-String '^ - |^ \* |GATE' | ForEach-Object { $_.Line } | Add-Content $L
$out = "$W\probe\fixture-$Variant-$Run"; New-Item -ItemType Directory -Force $out | Out-Null
& $pp -n "@$cfg" -Mdelphi -O3 -B -gw3 "-FE$out" "-FU$out" -uMOONCOMPILER_VANILLA_RUNTIME -dFPCMM_BOOSTER -dFPCMM_MOONSHARD -dNOPATCHRTL -dMOONBOT_MM_PROFILE_REQUIRED "--pinned-unit=mormot.core.fpcx64mm=$mm" '--required-first-unit=mormot.core.fpcx64mm' "-Fu$W\runtime\mm" "$tools\placement_fixture.dpr" *> "$out\build.log"
Record-Stage 'fixture build' $LASTEXITCODE
& "$out\placement_fixture.exe" | Add-Content $L
Record-Stage 'fixture run' $LASTEXITCODE
& $uv run python "$tools\check_placement_rules.py" "$out\placement_fixture.exe" --match 'P\$PLACEMENT_FIXTURE' --assert $Assert --list-violations *> "$S\gate-fixture-$Variant.md"
Record-Stage 'fixture gate' $LASTEXITCODE
Get-Content "$S\gate-fixture-$Variant.md" | Add-Content $L
& $uv run python qualification/memory-manager/mm_layout_gate.py --compiler $pp --config $cfg *> "$S\gate-mm-layout-$Variant.md"
Record-Stage 'mm layout gate' $LASTEXITCODE
Get-Content "$S\gate-mm-layout-$Variant.md" | Add-Content $L
& $uv run python qualification/build-driver/rtl_asm_layout_gate.py --compiler $pp --config $cfg *> "$S\gate-rtl-asm-layout-$Variant.md"
Record-Stage 'rtl asm layout gate' $LASTEXITCODE
Get-Content "$S\gate-rtl-asm-layout-$Variant.md" | Add-Content $L
& $uv run python qualification/memory-manager/mm_profile_matrix.py --compiler $pp --config $cfg *> "$S\gate-mm-matrix-$Variant.md"
Record-Stage 'mm profile matrix' $LASTEXITCODE
Get-Content "$S\gate-mm-matrix-$Variant.md" | Add-Content $L

# --- placement-controlled medium Pulse: baseline family vs variant family ---
$sysargs = @()
foreach ($fam in @($Baseline, $Variant)) {
  $sysargs += "--moon-system"; $sysargs += "$fam=stand/$fam"
  foreach ($k in 1..3) { $sysargs += "--moon-system"; $sysargs += "$fam$k=stand/$fam"; $sysargs += "--moon-system-option"; $sysargs += "$fam$k=-dPULSE_FILLER_$k" }
}
$systems = "$Baseline,${Baseline}1,${Baseline}2,${Baseline}3,$Variant,${Variant}1,${Variant}2,${Variant}3"
& $uv run python qualification/performance/tools/pulse.py run --mode medium --programs hot-rtl,repairs --systems $systems @sysargs --moon-extra-option=-gw3 --tag "stand-win64-filler-$Variant-$Run" *> "$S\pulse-win64-filler-$Variant-$Run.log"
Record-Stage "filler pulse $Baseline vs $Variant" $LASTEXITCODE
(Select-String -Path "$S\pulse-win64-filler-$Variant-$Run.log" -Pattern 'UnstablePairsError' | Measure-Object).Count | ForEach-Object { "unstable pairs errors: $_" } | Add-Content $L
& $uv run python "$tools\filler_summary.py" "qualification/performance/results/pulse/stand-win64-filler-$Variant-$Run" --left $Baseline --right $Variant *> "$S\filler-win64-${Baseline}vs$Variant-$Run.md"
Record-Stage 'filler summary' $LASTEXITCODE
$ab = @('--baseline', $Baseline, '--candidate', $Variant)
If ($ExpectFaster) { $ab += @('--expect-faster', $ExpectFaster) }
If ($AllowSlower) { $ab += @('--allow-slower', $AllowSlower) }
& $uv run python "$tools\stand_ab_gate.py" "qualification/performance/results/pulse/stand-win64-filler-$Variant-$Run" @ab *>> $L
Record-Stage 'ab gate' $LASTEXITCODE

# --- placement statistics on the Pulse executables (program unit and RTL units) ---
foreach ($fam in @($Baseline, $Variant)) {
  $exe = "$W\qualification\performance\hot-rtl\build-$fam\pulse_hot-rtl.exe"
  & $uv run python "$tools\check_placement_rules.py" $exe --match 'P\$PULSE_HOT_RTL' --list-violations *> "$S\gate-hotrtl-program-$fam.md"
  Record-Stage "placement stats $fam program" $LASTEXITCODE
  & $uv run python "$tools\check_placement_rules.py" $exe --match '^(SYSUTILS|CLASSES|STRUTILS|MATH|GENERICS)' --exclude 'asm' *> "$S\gate-hotrtl-rtl-$fam.md"
  Record-Stage "placement stats $fam rtl" $LASTEXITCODE
  "placement stats $fam program:" | Add-Content $L
  Get-Content "$S\gate-hotrtl-program-$fam.md" | Select-Object -First 10 | Add-Content $L
  "placement stats $fam rtl units:" | Add-Content $L
  Get-Content "$S\gate-hotrtl-rtl-$fam.md" | Select-Object -First 10 | Add-Content $L
}

# --- rule 4 and the target rule hold in the whole Pulse program of the variant, compiled and
#     hand-written code alike: no branch on a 32-byte boundary, no jump target of a loop in the
#     last 12 bytes of a line where the block in front could carry the pad.  Hand-written
#     routines nobody laid out would be listed in unlaid_asm_routines.txt (empty) ---
$exe = "$W\qualification\performance\hot-rtl\build-$Variant\pulse_hot-rtl.exe"
& $uv run python "$tools\check_placement_rules.py" $exe --match '^(P\$PULSE_HOT_RTL|SYSTEM|SYSUTILS|CLASSES|STRUTILS|MATH|GENERICS|RTTI|FGL|TYPINFO|FPC_|fpc_)' --exclude-file "$tools\unlaid_asm_routines.txt" --assert R4,RT --list-violations *> "$S\gate-compiled-r4-$Variant-$Run.md"
Record-Stage 'compiled code rules gate' $LASTEXITCODE
Get-Content "$S\gate-compiled-r4-$Variant-$Run.md" | Select-String '^R4 |^  R4:|^RT |^  RT:|PLACEMENT_GATE' | ForEach-Object { $_.Line } | Add-Content $L

# --- semantics on the variant ---
If ($SkipSemantics) {
  "CHAIN_${Variant}_INCONCLUSIVE reason=semantics-skipped" | Add-Content $L
  exit 2
}
$env:MOONBOT_TOOLCHAIN = "$S\$Variant"
& $uv run python RTL-test/run.py *> "$S\rtltest-$Variant-$Run.log"
Record-Stage "RTL-test $Variant" $LASTEXITCODE
& $uv run python qualification/suite/scripts/run_devil_targeted.py light --run-id "stand-$Variant-light-$Run" *> "$S\light-$Variant-$Run.log"
Record-Stage "light $Variant" $LASTEXITCODE
$env:MOONBOT_TOOLCHAIN = $null
Finish-Chain

param(
  [string]$Baseline = '',                             # installed toolchain directory of the baseline (layout of toolchain)
  [string]$Candidate = 'toolchain',          # installed toolchain directory of the candidate
  [string]$Programs = '',                             # comma list; empty = every Pulse program, the Moon-only ones included
  [string]$Cases = '',                                # comma list of program/case rows for a focused stand run
  [ValidateSet('quick', 'medium', 'long')][string]$Mode = 'medium',
  [string]$Tag = '',
  [string]$Result = '',                               # judge this existing result directory, do not run Pulse
  [int]$PulseExit = 0,                                # with -Result: the exit code of the Pulse that made it
  [string]$PulseLog = '',                             # with -Result: the log of that Pulse
  [string]$LegacyBaselineRevision = '',               # frozen source revision predating profile.txt; hashes remain mandatory
  [ValidateRange(1, 16)][int]$BuildJobs = 4,           # builds only; timed processes remain serial
  [string]$Uv = 'C:\files\utils\python\uv.exe'
)
# Placement-controlled Pulse of two toolchains over any set of programs.
#
# One linked executable is one placement of the code, and on a short case one placement can differ
# from the next by tens of percent with identical instructions (see doc/ASM_LAYOUT_RULES.md, "What
# is a coin, not a rule").  A baseline/candidate ratio taken from one executable of each side
# therefore mixes the toolchain with the address lottery.  Here each side is built four times: as
# it is and with -dPULSE_FILLER_k. Unit fillers move later units; the shared program prefix moves
# program-local procedures. The gate verifies every measured body against its image and records
# calls, branches and loops. Reports and acceptance use the same family estimator.
#
# Every Pulse program carries the three filler lines behind its memory manager unit.  With no
# -Programs the list comes from "pulse.py programs --all": pulse.py's own default leaves out the
# programs Delphi cannot build (repairs), and both sides here are Moon toolchains, so they run too.
# The gate is told the list and fails when a program that was asked for has no judged row.
#
# The exit code is the verdict: 0 accepted, 1 rejected or a step failed, 2 inconclusive evidence.
# A Pulse that failed is not judged, with one exception: when every run
# was collected and Pulse only found unstable process pairs (two runs of one executable apart,
# UnstablePairsError - the cause is not established), the families are still judged for information
# and the script returns 2, never 0.
#
# Do not run anything heavy on the machine meanwhile: the families are compared by medians of
# interleaved runs, but a loaded machine widens every spread and the gate then refuses to judge.
$root = (Resolve-Path "$PSScriptRoot\..").Path
Set-Location $root
$tools = "$root\qualification\performance\tools"
If (-not $Programs) {
  $Programs = (& $Uv run python "$tools\pulse.py" programs --all | Select-Object -Last 1).Trim()
  If ($LASTEXITCODE -ne 0 -or -not $Programs) {
    "cannot get the program list from pulse.py"
    exit 1
  }
}
"programs: $Programs"
If ($Result) {
  $resultDir = (Resolve-Path $Result).Path
  $Tag = Split-Path $resultDir -Leaf
  $pulseCode = $PulseExit
  $pulseLogPath = $PulseLog
} else {
  If (-not $Baseline) {
    "-Baseline is required unless -Result names a finished run"
    exit 1
  }
  If (-not $Tag) { $Tag = "family-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
  $base = (Resolve-Path $Baseline).Path
  $cand = (Resolve-Path $Candidate).Path
  $sysargs = @()
  foreach ($pair in @(@('B', $base), @('C', $cand))) {
    $fam, $dir = $pair
    # every toolchain pins its own memory manager source in its moon-base.cfg; Pulse has to pin the same
    # file, a second pin of another path is refused by the compiler
    $cfg = Join-Path $dir 'bin\x86_64-win64\moon-base.cfg'
    $pin = Select-String -Path $cfg -Pattern '^--pinned-unit=mormot\.core\.fpcx64mm=(.+)$' | Select-Object -First 1
    If (-not $pin) { throw "no pinned memory manager in $cfg" }
    $mm = $pin.Matches[0].Groups[1].Value.Trim().Replace('$FPCBINDIR', (Split-Path $cfg -Parent))
    $mm = (Resolve-Path -LiteralPath $mm).Path
    foreach ($name in @($fam, "${fam}1", "${fam}2", "${fam}3")) {
      $sysargs += '--moon-system'; $sysargs += "$name=$dir"
      $sysargs += '--moon-system-mm-source'; $sysargs += "$name=$mm"
    }
    foreach ($k in 1..3) { $sysargs += '--moon-system-option'; $sysargs += "$fam$k=-dPULSE_FILLER_$k" }
  }
  $run = @('run', 'python', "$tools\pulse.py", 'run', '--mode', $Mode, '--systems', 'B,B1,B2,B3,C,C1,C2,C3',
           '--programs', $Programs, '--build-jobs', $BuildJobs)
  If ($Cases) { $run += @('--cases', $Cases) }
  $run += $sysargs
  $run += @('--moon-extra-option=-gw3', '--tag', $Tag)
  $resultDir = "$root\qualification\performance\results\pulse\$Tag"
  New-Item -ItemType Directory -Force "$root\.qualification" | Out-Null
  $pulseLogPath = "$root\.qualification\pulse-family-$Tag.log"
  & $Uv @run 2>&1 |
    Tee-Object -FilePath $pulseLogPath |
    Where-Object {
      "$_" -match '^(BUILD_DONE|PULSE_PROGRESS|PULSE_RESULT|Traceback|.*(?:Fatal|Error|UnstablePairsError))'
    }
  $pulseCode = $LASTEXITCODE
  "pulse exit=$pulseCode  log .qualification\pulse-family-$Tag.log"
}
$unstableOnly = $false
If ($pulseCode -ne 0) {
  $unstableOnly = $pulseLogPath -and (Test-Path -LiteralPath $pulseLogPath) -and
    (Test-Path -LiteralPath "$resultDir\manifest.json") -and
    [bool](Select-String -LiteralPath $pulseLogPath -Pattern 'UnstablePairsError' -Quiet)
  If (-not $unstableOnly) {
    "Pulse failed: the result is not judged"
    exit 1
  }
  "Pulse collected every run and found unstable process pairs: judged for information, repeat the run"
  Select-String -LiteralPath $pulseLogPath -Pattern 'UnstablePairsError:' | ForEach-Object { $_.Line.Trim() }
}
New-Item -ItemType Directory -Force "$root\.qualification" | Out-Null
& $Uv run python "$tools\filler_summary.py" $resultDir --left B --right C | Tee-Object -FilePath "$root\.qualification\pulse-family-$Tag.md"
$summaryExit = $LASTEXITCODE
$gateArgs = @($resultDir, '--baseline', 'B', '--candidate', 'C', '--programs', $Programs)
If ($LegacyBaselineRevision) { $gateArgs += @('--legacy-baseline-revision', $LegacyBaselineRevision) }
& $Uv run python "$tools\stand_ab_gate.py" @gateArgs
$gateExit = $LASTEXITCODE
"summary exit=$summaryExit  ab gate exit=$gateExit  summary .qualification\pulse-family-$Tag.md"
If ($gateExit -ne 0 -and $gateExit -ne 2) { exit 1 }
If ($summaryExit -ne 0) { exit 1 }
If ($unstableOnly -or $gateExit -eq 2) { exit 2 }
exit 0

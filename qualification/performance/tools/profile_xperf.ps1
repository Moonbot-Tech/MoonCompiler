# profile_xperf.ps1 - timer-sampled profile of one command as an xperf text
# dump for opcache_sets.py (`--profile DUMP --process <exe name>`).
#
#   .\profile_xperf.ps1 -Out profile.txt -- <exe> [args...]
#   .\profile_xperf.ps1 -Out profile.txt -Command 'R:\...\dict_bench.exe update 256 25 int default'
#   .\profile_xperf.ps1 -Jobs jobs.txt
#
# Records PROC_THREAD+LOADER+PROFILE (1 kHz timer samples with the sampled
# instruction pointer and the image load rows that map the pointers back to
# the executable), runs the command, stops the trace and dumps it with the
# xperf dumper.  ETW needs an elevated process: when this shell is not
# elevated the script re-launches itself hidden with -Verb RunAs and waits, so
# the dump lands in -Out either way; the benchmark's own console output goes to
# <Out>.stdout.txt.  The trace (.etl) stays beside the dump.
#
# A series goes through one elevation: -Jobs names a file with one
# `<dump path><TAB><command>` line per run.  Each run still gets its own trace
# and dump, since opcache_sets.py tells processes apart only by exe name.
#
# One run of a quick Pulse case (about a second of hot loop) gives a few
# hundred samples inside the executable, enough for opcache_sets.py: a hot
# 64-byte window collects tens of samples, cold code none.
param(
  [string]$Out = '',
  [string]$Command = '',
  [string]$Jobs = '',
  [string]$WorkingDirectory = '',
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)
$ErrorActionPreference = 'Stop'
If (-not $Command) {
  $Command = ($Rest | Where-Object { $_ -ne '--' }) -join ' '
}
If ($Jobs) {
  $Jobs = [System.IO.Path]::GetFullPath($Jobs)
  $runs = @(Get-Content -LiteralPath $Jobs | Where-Object { $_.Trim() } | ForEach-Object {
    $fields = $_ -split "`t", 2
    If ($fields.Count -ne 2) { throw "job line is not <dump><TAB><command>: $_" }
    [pscustomobject]@{ Out = [System.IO.Path]::GetFullPath($fields[0]); Command = $fields[1] }
  })
} else {
  If (-not $Out) { throw 'give -Out with a command, or -Jobs' }
  If (-not $Command) { throw 'nothing to run: give -Command or the command after --' }
  $runs = @([pscustomobject]@{ Out = [System.IO.Path]::GetFullPath($Out); Command = $Command })
}
If (-not $WorkingDirectory) { $WorkingDirectory = (Get-Location).Path }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
If (-not $elevated) {
  $self = $MyInvocation.MyCommand.Path
  # Start-Process re-splits the argument list at spaces: quote every value
  $arguments = @('-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
    '-File', ('"' + $self + '"'), '-WorkingDirectory', ('"' + $WorkingDirectory + '"'))
  If ($Jobs) {
    $arguments += @('-Jobs', ('"' + $Jobs + '"'))
  } else {
    $arguments += @('-Out', ('"' + $runs[0].Out + '"'), '-Command', ('"' + $Command + '"'))
  }
  $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -Wait -PassThru
  If ($process.ExitCode -ne 0) { throw "elevated profile run failed ($($process.ExitCode)); see <dump>.log" }
  foreach ($run in $runs) {
    If (-not (Test-Path -LiteralPath $run.Out)) { throw "no dump was written: $($run.Out)" }
    Write-Output "profile dump: $($run.Out)"
  }
  exit 0
}
$xperf = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Windows Performance Toolkit\xperf.exe'
If (-not (Test-Path -LiteralPath $xperf)) { throw "xperf.exe not found (Windows Performance Toolkit): $xperf" }
foreach ($run in $runs) {
  $etl = [System.IO.Path]::ChangeExtension($run.Out, '.etl')
  $log = "$($run.Out).log"
  $stdout = "$($run.Out).stdout.txt"
  "start $(Get-Date)  command: $($run.Command)" | Out-File $log -Encoding utf8
  try {
    & $xperf -on PROC_THREAD+LOADER+PROFILE -f $etl 2>&1 | Out-File $log -Append -Encoding utf8
    If ($LASTEXITCODE -ne 0) { throw "xperf -on failed ($LASTEXITCODE)" }
    Push-Location $WorkingDirectory
    try {
      cmd /c "$($run.Command)" 2>&1 | Out-File $stdout -Encoding utf8
      "command exit code $LASTEXITCODE" | Out-File $log -Append -Encoding utf8
    } finally {
      Pop-Location
      & $xperf -stop 2>&1 | Out-File $log -Append -Encoding utf8
    }
    & $xperf -i $etl -o $run.Out -a dumper 2>&1 | Out-File $log -Append -Encoding utf8
    If (-not (Test-Path -LiteralPath $run.Out)) { throw 'xperf dumper produced no text' }
    "done $(Get-Date)" | Out-File $log -Append -Encoding utf8
  } catch {
    "failed: $_" | Out-File $log -Append -Encoding utf8
    exit 1
  }
}
exit 0

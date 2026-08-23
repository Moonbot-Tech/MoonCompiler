param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Runner = Join-Path $Root 'qualification\suite\runner.py'
$Python = $env:PYTHON
$PythonArgs = @()
If (-not $Python) {
  foreach ($Candidate in @('py', 'python3', 'python')) {
    $Command = Get-Command $Candidate -ErrorAction SilentlyContinue
    If (-not $Command) {
      continue
    }
    $CandidateArgs = @()
    If ($Candidate -eq 'py') {
      $CandidateArgs = @('-3')
    }
    & $Command.Source @CandidateArgs --version *> $null
    If ($LASTEXITCODE -eq 0) {
      $Python = $Command.Source
      $PythonArgs = $CandidateArgs
      break
    }
  }
}
If (-not $Python) {
  throw 'Python 3 was not found; install it or set PYTHON to its executable'
}
& $Python @PythonArgs $Runner prepare
If ($LASTEXITCODE -ne 0) {
  throw "Qualification dependency preparation failed with exit code $LASTEXITCODE"
}

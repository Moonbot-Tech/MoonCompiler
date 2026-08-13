param(
  [string]$Dcc64 = 'C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -Raw (Join-Path $root 'runner_manifest.json') | ConvertFrom-Json
$build = Join-Path $root 'results\delphi-fixture-oracles'
$output = Join-Path $root 'research\delphi_fixture_oracle_probe.json'
$lib = Join-Path (Split-Path -Parent (Split-Path -Parent $Dcc64)) 'lib\win64\release'
$testIds = @(
  'fpc-41451',
  'fpc-41558',
  'fpc-41564',
  'fpc-41589',
  'fpc-41711',
  'fpc-41808',
  'lab-001-constprop-absolute'
)
$directivePattern = '(?im)^\s*\{\$(?:mode|modeswitch|optimization|objectchecks)\b[^}]*\}\s*$'

New-Item -ItemType Directory -Force $build | Out-Null
$results = foreach ($testId in $testIds) {
  $fixture = $manifest.fixtures | Where-Object id -eq $testId
  if ($null -eq $fixture) {
    throw "Unknown fixture $testId"
  }
  $source = Join-Path $root $fixture.source
  $adapted = Join-Path $build ([IO.Path]::GetFileName($source))
  $text = [IO.File]::ReadAllText($source)
  $text = [regex]::Replace($text, $directivePattern, '')
  if ($testId -eq 'fpc-41451') {
    $text = $text.Replace('Initialize(var Value: TFoo)', 'Initialize(out Value: TFoo)')
  }
  if ($testId -eq 'lab-001-constprop-absolute') {
    $text = [regex]::Replace($text, '\bQWord\b', 'UInt64')
    $text = $text.Replace("WriteLn('FAIL lab-001 got=', HexStr(Got, 16));", "WriteLn('FAIL lab-001');")
  }
  [IO.File]::WriteAllText($adapted, $text, [Text.UTF8Encoding]::new($false))
  $log = Join-Path $build "$testId.log"
  & $Dcc64 -B -Q "-U$lib" '-NSSystem' "-E$build" "-N0$build" "-NU$build" $adapted 2>&1 |
    Set-Content $log
  $compileExit = $LASTEXITCODE
  $runExit = $null
  if ($compileExit -eq 0) {
    $executable = Join-Path $build (([IO.Path]::GetFileNameWithoutExtension($adapted)) + '.exe')
    & $executable
    $runExit = $LASTEXITCODE
  }
  [ordered]@{
    test_id = $testId
    source_sha256 = (Get-FileHash -Algorithm SHA256 $source).Hash.ToLower()
    adapted_source_sha256 = (Get-FileHash -Algorithm SHA256 $adapted).Hash.ToLower()
    compile_exit_code = $compileExit
    run_exit_code = $runExit
  }
}

$payload = [ordered]@{
  schema = 1
  compiler = 'Delphi 12.2 Win64 compiler 36.0'
  compiler_sha256 = (Get-FileHash -Algorithm SHA256 $Dcc64).Hash.ToLower()
  transformation = 'Remove FPC-only mode, modeswitch, optimization, and objectchecks directives'
  tests = $results
}
$json = $payload | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($output, $json + "`n", [Text.UTF8Encoding]::new($false))
if ($results.Where({ $_.compile_exit_code -ne 0 -or $_.run_exit_code -ne 0 }).Count -ne 0) {
  throw 'Delphi fixture oracle mismatch'
}
Write-Output "tests=$($results.Count) sha256=$((Get-FileHash -Algorithm SHA256 $output).Hash.ToLower())"

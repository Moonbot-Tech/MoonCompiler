param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId
)

$ErrorActionPreference = 'Stop'
$SuiteRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CompilerRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$SourceRoot = Join-Path $SuiteRoot 'tests\rtl-api'
$Run = Join-Path $SuiteRoot "results\runs\$RunId\rtl-api-surface"
$Cases = @(
  @{ Name = 'rtl_api_surface'; Expected = 'RTL_API_SURFACE_OK' },
  @{ Name = 'rtl_api_array_copy'; Expected = 'RTL_API_ARRAY_COPY_OK' }
)

If (Test-Path -LiteralPath $Run) { throw "run already exists: $Run" }
New-Item -ItemType Directory -Path $Run | Out-Null

foreach ($Case in $Cases) {
  foreach ($Profile in @('debug', 'release')) {
    $ProfileDir = Join-Path $Run "$($Case.Name)\$Profile"
    New-Item -ItemType Directory -Path $ProfileDir | Out-Null
    $Project = Join-Path $ProfileDir "$($Case.Name).dpr"
    Copy-Item -LiteralPath (Join-Path $SourceRoot "$($Case.Name).dpr") `
      -Destination $Project
    & (Join-Path $CompilerRoot 'build.ps1') $Project $Profile `
      *> (Join-Path $ProfileDir 'compile.log')
    If ($LASTEXITCODE -ne 0) {
      throw "$($Case.Name)/$Profile did not compile"
    }
    & (Join-Path $ProfileDir "$($Case.Name).exe") `
      *> (Join-Path $ProfileDir 'run.log')
    If (($LASTEXITCODE -ne 0) -or
        ((Get-Content -Raw (Join-Path $ProfileDir 'run.log')).Trim() -ne
          $Case.Expected)) {
      throw "$($Case.Name)/$Profile failed"
    }
  }
}

$Inputs = @(
  (Join-Path $SourceRoot 'rtl_api_surface.dpr'),
  (Join-Path $SourceRoot 'rtl_api_array_copy.dpr'),
  (Join-Path $CompilerRoot 'build.ps1'),
  (Join-Path $CompilerRoot 'runtime\mm\mormot.core.fpcx64mm.pas'),
  (Join-Path $CompilerRoot '.moonbot\toolchain\bin\x86_64-win64\fpc.exe'),
  (Join-Path $CompilerRoot '.moonbot\toolchain\bin\x86_64-win64\fpc.cfg'))
$Inputs += Get-ChildItem -File -Recurse -LiteralPath $Run |
  ForEach-Object { $_.FullName }
$Inputs | Sort-Object -Unique | ForEach-Object {
  $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()
  "$Hash *$([IO.Path]::GetFullPath($_))"
} | Set-Content -LiteralPath (Join-Path $Run 'SHA256SUMS') -Encoding ascii

Write-Output 'RTL_API_SURFACE_GATE_OK cases=2 profiles=2'

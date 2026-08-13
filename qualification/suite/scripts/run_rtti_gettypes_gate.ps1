param(
  [Parameter(Mandatory = $true)][string]$Compiler,
  [Parameter(Mandatory = $true)][string]$Config,
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SourceDir = Join-Path $Root 'tests\rtti'
$Source = Join-Path $SourceDir 'rtti_gettypes.dpr'
$Compiler = (Resolve-Path -LiteralPath $Compiler).Path
$Config = (Resolve-Path -LiteralPath $Config).Path
$Run = Join-Path $Root "results\runs\$RunId\rtti-gettypes"
If (Test-Path -LiteralPath $Run) { throw "run already exists: $Run" }

foreach ($Option in @('O2', 'O3')) {
  foreach ($Linking in @('normal', 'smart')) {
    $Out = Join-Path $Run "$Option-$Linking"
    $Units = Join-Path $Out 'units'
    New-Item -ItemType Directory -Force -Path $Units | Out-Null
    $Args = @('-n', "@$Config", '-Mdelphi', '-B', "-$Option", '-gl', '-gw3',
      "-Fu$SourceDir", "-FU$Units", "-FE$Out", "-o$Out\rtti_gettypes.exe")
    If ($Linking -eq 'smart') { $Args += @('-CX', '-XX') }
    & $Compiler @Args $Source *> (Join-Path $Out 'compile.log')
    If ($LASTEXITCODE -ne 0) { throw "$Option/$Linking did not compile" }
    & "$Out\rtti_gettypes.exe" *> (Join-Path $Out 'run.log')
    If (($LASTEXITCODE -ne 0) -or
        ((Get-Content -Raw (Join-Path $Out 'run.log')).Trim() -ne 'RTTI_GETTYPES_PASS')) {
      throw "$Option/$Linking failed"
    }
  }
}
$Inputs = @($Compiler, $Config)
$Inputs += Get-ChildItem -File -Recurse -LiteralPath $SourceDir |
  Where-Object { $_.Extension -in @('.pas', '.pp', '.inc', '.dpr') } |
  ForEach-Object { $_.FullName }
$Inputs += Get-ChildItem -File -Recurse -LiteralPath $Run |
  ForEach-Object { $_.FullName }
$Inputs | Sort-Object -Unique | ForEach-Object {
  $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()
  "$Hash *$([IO.Path]::GetFullPath($_))"
} | Set-Content -LiteralPath (Join-Path $Run 'SHA256SUMS') -Encoding ascii
Write-Output 'RTTI_GETTYPES_GATE_PASS rows=4'

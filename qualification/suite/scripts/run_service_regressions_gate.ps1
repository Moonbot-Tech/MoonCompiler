param(
  [Parameter(Mandatory = $true)][string]$Compiler,
  [Parameter(Mandatory = $true)][string]$Config,
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CompilerRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Compiler = (Resolve-Path -LiteralPath $Compiler).Path
$Config = (Resolve-Path -LiteralPath $Config).Path
$Run = Join-Path $Root "results\runs\$RunId\service-regressions"
If (Test-Path -LiteralPath $Run) { throw "run already exists: $Run" }
New-Item -ItemType Directory -Path $Run | Out-Null

function Invoke-Case([string]$Name, [string]$Expected, [string[]]$SourceArgs = @()) {
  foreach ($Option in @('O2', 'O3')) {
    $Out = Join-Path $Run "$Name-$($Option.ToLower())"
    New-Item -ItemType Directory -Path $Out | Out-Null
    $Log = Join-Path $Out 'compile.log'
    & $Compiler -n "@$Config" -B "-$Option" "-Fu$Root\tests\smoke" `
      @SourceArgs "-FU$Out" "-FE$Out" "-o$Out\$Name.exe" `
      "$Root\tests\smoke\$Name.pas" *> $Log
    If ($LASTEXITCODE -ne 0) { throw "$Name/$Option did not compile" }
    & "$Out\$Name.exe" *> (Join-Path $Out 'run.log')
    If (($LASTEXITCODE -ne 0) -or
        ((Get-Content -Raw (Join-Path $Out 'run.log')).Trim() -ne $Expected)) {
      throw "$Name/$Option failed"
    }
  }
}

function Invoke-Rejected(
  [string]$Name,
  [string]$Diagnostic = 'Error: (Incompatible types|Illegal type conversion)',
  [string[]]$SourceArgs = @()
) {
  foreach ($Option in @('O2', 'O3')) {
    $Out = Join-Path $Run "$Name-$($Option.ToLower())"
    New-Item -ItemType Directory -Path $Out | Out-Null
    $Log = Join-Path $Out 'compile.log'
    & $Compiler -n "@$Config" -B "-$Option" "-Fu$Root\tests\smoke" `
      @SourceArgs "-FU$Out" "-FE$Out" "$Root\tests\smoke\$Name.pas" *> $Log
    If ($LASTEXITCODE -eq 0) { throw "$Name/$Option unexpectedly compiled" }
    If ((Get-Content -Raw $Log) -notmatch $Diagnostic) {
      throw "$Name/$Option returned an unexpected diagnostic"
    }
  }
}

$Generics = Join-Path $CompilerRoot 'packages\rtl-generics'
$GenericArgs = @(
  "-Fu$Generics\namespaced", "-Fi$Generics\src", "-Fi$Generics\src\inc",
  '-UaSystem.Classes=Classes', '-UaSystem.SysUtils=SysUtils',
  '-UaSystem.TypInfo=TypInfo', '-UaSystem.Variants=Variants',
  '-UaSystem.Math=Math', '-UaSystem.CPU=CPU')
$Paszlib = Join-Path $CompilerRoot 'packages\paszlib'
$PaszlibArgs = @("-Fu$Paszlib\namespaced", "-Fi$Paszlib\src", '-UaSystem.SysUtils=SysUtils')

Invoke-Case service_compiler_regressions SERVICE_COMPILER_REGRESSIONS_OK
Invoke-Case variant_char_dispatch VARIANT_CHAR_DISPATCH_OK
Invoke-Rejected variant_char_dispatch 'Type is not automatable' `
  @('-dMOONBOT_OBJFPC_CONTROL')
Invoke-Rejected variant_distinct_objfpc_rejected
Invoke-Case dotted_unicode_comparer DOTTED_UNICODE_COMPARER_OK $GenericArgs
Invoke-Case paszlib_delphi_unicode PASZLIB_DELPHI_UNICODE_OK $PaszlibArgs
Invoke-Rejected anonymous_callback_var_rejected
Invoke-Rejected anonymous_callback_out_rejected
$Inputs = @(
  $Compiler, $Config,
  (Join-Path $Root 'tests\smoke\service_compiler_regressions.pas'),
  (Join-Path $Root 'tests\smoke\variant_char_dispatch.pas'),
  (Join-Path $Root 'tests\smoke\variant_distinct_objfpc_rejected.pas'),
  (Join-Path $Root 'tests\smoke\dotted_unicode_comparer.pas'),
  (Join-Path $Root 'tests\smoke\paszlib_delphi_unicode.pas'),
  (Join-Path $Root 'tests\smoke\anonymous_callback_var_rejected.pas'),
  (Join-Path $Root 'tests\smoke\anonymous_callback_out_rejected.pas'))
$Inputs += Get-ChildItem -File -Recurse -Path `
  (Join-Path $Generics 'src'), (Join-Path $Generics 'namespaced'), `
  (Join-Path $Paszlib 'src'), (Join-Path $Paszlib 'namespaced') `
  -Include *.pas,*.pp,*.inc | ForEach-Object { $_.FullName }
$Inputs += Get-ChildItem -File -Recurse -LiteralPath $Run |
  ForEach-Object { $_.FullName }
$Inputs | Sort-Object -Unique | ForEach-Object {
  $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()
  "$Hash *$([IO.Path]::GetFullPath($_))"
} | Set-Content -LiteralPath (Join-Path $Run 'SHA256SUMS') -Encoding ascii
Write-Output 'SERVICE_REGRESSIONS_GATE_OK positive=4 negative=4 modes=2'

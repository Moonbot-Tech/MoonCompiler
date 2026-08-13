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
  foreach ($Option in @('O-', 'O2', 'O3')) {
    $Tag = If ($Option -eq 'O-') { 'debug' } Else { $Option.ToLower() }
    $Out = Join-Path $Run "$Name-$Tag"
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
  foreach ($Option in @('O-', 'O2', 'O3')) {
    $Tag = If ($Option -eq 'O-') { 'debug' } Else { $Option.ToLower() }
    $Out = Join-Path $Run "$Name-rejected-$Tag"
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

function Invoke-AliasReplay {
  foreach ($Option in @('O-', 'O2', 'O3')) {
    $Tag = If ($Option -eq 'O-') { 'debug' } Else { $Option.ToLower() }
    $Out = Join-Path $Run "generic_alias_replay-$Tag"
    New-Item -ItemType Directory -Path $Out | Out-Null
    & $Compiler -n "@$Config" "-$Option" -Mdelphi `
      '-UaSystem.Generics.Collections=Generics.Collections' `
      "-FU$Out" "-FE$Out" `
      "$Root\tests\smoke\generic_alias_replay_unit.pas" `
      *> (Join-Path $Out 'unit.compile.log')
    If ($LASTEXITCODE -ne 0) { throw "generic alias unit/$Option did not compile" }
    Copy-Item -LiteralPath "$Root\tests\smoke\generic_alias_replay.pas" `
      -Destination $Out
    & $Compiler -n "@$Config" "-$Option" -Mdelphi `
      '-UaSystem.Generics.Collections=Generics.Collections' `
      "-Fu$Out" "-FU$Out" "-FE$Out" `
      (Join-Path $Out 'generic_alias_replay.pas') `
      *> (Join-Path $Out 'program.compile.log')
    If ($LASTEXITCODE -ne 0) { throw "generic alias PPU replay/$Option did not compile" }
    & "$Out\generic_alias_replay.exe" *> (Join-Path $Out 'run.log')
    If (($LASTEXITCODE -ne 0) -or
        ((Get-Content -Raw (Join-Path $Out 'run.log')).Trim() -ne
          'GENERIC_ALIAS_REPLAY_OK')) {
      throw "generic alias PPU replay/$Option failed"
    }
  }
}

$Generics = Join-Path $CompilerRoot 'packages\rtl-generics'
$GenericArgs = @(
  "-Fu$Generics\namespaced", "-Fi$Generics\src", "-Fi$Generics\src\inc",
  '-UaSystem.Classes=Classes', '-UaSystem.SysUtils=SysUtils',
  '-UaSystem.TypInfo=TypInfo', '-UaSystem.Variants=Variants',
  '-UaSystem.Math=Math', '-UaSystem.CPU=CPU')
$GenericSourceArgs = @(
  "-Fu$Generics\src", "-Fi$Generics\src", "-Fi$Generics\src\inc",
  '-UaSystem.Generics.Collections=Generics.Collections')
$Paszlib = Join-Path $CompilerRoot 'packages\paszlib'
$PaszlibArgs = @("-Fu$Paszlib\namespaced", "-Fi$Paszlib\src", '-UaSystem.SysUtils=SysUtils')

Invoke-Case service_compiler_regressions SERVICE_COMPILER_REGRESSIONS_OK
Invoke-Case variant_char_dispatch VARIANT_CHAR_DISPATCH_OK
Invoke-Rejected variant_char_dispatch 'Type is not automatable' `
  @('-dMOONBOT_OBJFPC_CONTROL')
Invoke-Rejected variant_distinct_objfpc_rejected
Invoke-Case dotted_unicode_comparer DOTTED_UNICODE_COMPARER_OK $GenericArgs
Invoke-Case paszlib_delphi_unicode PASZLIB_DELPHI_UNICODE_OK $PaszlibArgs
Invoke-Case delphi_tlist_arrayoft DELPHI_TLIST_ARRAYOFT_OK $GenericSourceArgs
Invoke-AliasReplay
Invoke-Case generic_return_alias GENERIC_RETURN_ALIAS_OK
Invoke-Case delphi_with_anonymous DELPHI_WITH_ANONYMOUS_OK
Invoke-Rejected anonymous_callback_var_rejected
Invoke-Rejected anonymous_callback_out_rejected
Invoke-Rejected generic_return_distinct_rejected `
  'Overloaded functions have the same parameter list'
Invoke-Rejected generic_return_mismatch_rejected `
  'Overloaded functions have the same parameter list'
Invoke-Rejected with_rvalue_write_rejected `
  "Can't assign values to const variable"
Invoke-Rejected inline_const_compiletime_rejected `
  "Can't evaluate constant expression"
$Inputs = @(
  $Compiler, $Config,
  (Join-Path $Root 'tests\smoke\service_compiler_regressions.pas'),
  (Join-Path $Root 'tests\smoke\variant_char_dispatch.pas'),
  (Join-Path $Root 'tests\smoke\variant_distinct_objfpc_rejected.pas'),
  (Join-Path $Root 'tests\smoke\dotted_unicode_comparer.pas'),
  (Join-Path $Root 'tests\smoke\paszlib_delphi_unicode.pas'),
  (Join-Path $Root 'tests\smoke\anonymous_callback_var_rejected.pas'),
  (Join-Path $Root 'tests\smoke\anonymous_callback_out_rejected.pas'),
  (Join-Path $Root 'tests\smoke\delphi_tlist_arrayoft.pas'),
  (Join-Path $Root 'tests\smoke\generic_alias_replay.pas'),
  (Join-Path $Root 'tests\smoke\generic_alias_replay_unit.pas'),
  (Join-Path $Root 'tests\smoke\generic_return_alias.pas'),
  (Join-Path $Root 'tests\smoke\generic_return_distinct_rejected.pas'),
  (Join-Path $Root 'tests\smoke\generic_return_mismatch_rejected.pas'),
  (Join-Path $Root 'tests\smoke\delphi_with_anonymous.pas'),
  (Join-Path $Root 'tests\smoke\with_rvalue_write_rejected.pas'),
  (Join-Path $Root 'tests\smoke\inline_const_compiletime_rejected.pas'))
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
Write-Output 'SERVICE_REGRESSIONS_GATE_OK positive=8 negative=8 modes=3'

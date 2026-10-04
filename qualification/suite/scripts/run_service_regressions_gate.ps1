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

function Invoke-MethodValueImplicitFinalizationReplay {
  foreach ($Option in @('O-', 'O2', 'O3')) {
    $Tag = If ($Option -eq 'O-') { 'debug' } Else { $Option.ToLower() }
    $Out = Join-Path $Run "method_value_implicit_finalization-$Tag"
    New-Item -ItemType Directory -Path $Out | Out-Null
    & $Compiler -n "@$Config" "-$Option" "-FU$Out" "-FE$Out" `
      "$Root\tests\smoke\method_value_implicit_finalization_unit.pas" `
      *> (Join-Path $Out 'unit.compile.log')
    If ($LASTEXITCODE -ne 0) { throw "implicit finalization unit/$Option did not compile" }
    Copy-Item -LiteralPath "$Root\tests\smoke\method_value_implicit_finalization.pas" -Destination $Out
    & $Compiler -n "@$Config" "-$Option" "-Fu$Out" "-FU$Out" "-FE$Out" `
      (Join-Path $Out 'method_value_implicit_finalization.pas') `
      *> (Join-Path $Out 'program.compile.log')
    If ($LASTEXITCODE -ne 0) { throw "implicit finalization PPU replay/$Option did not compile" }
    & "$Out\method_value_implicit_finalization.exe" *> (Join-Path $Out 'run.log')
    If (($LASTEXITCODE -ne 0) -or
        ((Get-Content -Raw (Join-Path $Out 'run.log')).Trim() -ne
          'METHOD_VALUE_IMPLICIT_FINALIZATION_OK')) {
      throw "implicit finalization PPU replay/$Option failed"
    }
  }
}

function Invoke-O3AutoinlineCycle {
  $Source = Join-Path $Root `
    'tests\compiler-crash\o3-indysecopenssl-provider'
  $Profiles = @(
    @{ Name = 'o2'; Args = @('-O2') },
    @{ Name = 'o2-autoinline'; Args = @('-O2', '-OoAUTOINLINE') },
    @{ Name = 'o3'; Args = @('-O3') })
  foreach ($Profile in $Profiles) {
    $Out = Join-Path $Run "o3-autoinline-cycle-$($Profile.Name)"
    New-Item -ItemType Directory -Path $Out | Out-Null
    & $Compiler -n "@$Config" -B @($Profile.Args) "-Fu$Source" `
      "-FU$Out" "-FE$Out" `
      "-o$Out\O3AutoinlineCycleCrash.exe" `
      (Join-Path $Source 'O3AutoinlineCycleCrash.dpr') `
      *> (Join-Path $Out 'compile.log')
    If ($LASTEXITCODE -ne 0) {
      throw "O3 AUTOINLINE unit cycle/$($Profile.Name) did not compile"
    }
    & "$Out\O3AutoinlineCycleCrash.exe" *> (Join-Path $Out 'run.log')
    If (($LASTEXITCODE -ne 0) -or
        ((Get-Content -Raw (Join-Path $Out 'run.log')).Trim() -ne
          'O3_AUTOINLINE_CYCLE_OK')) {
      throw "O3 AUTOINLINE unit cycle/$($Profile.Name) failed"
    }
  }
}

# A unit compiled by name next to the ppu of a unit that uses it in its implementation and that
# it uses itself, after the body of one of its routines changed: the used unit is compiled again
# and must not leave the first one, already compiled in this run, pointing at its old definitions
# (tests\compiler-crash\cyclic-unit-impl-change\README.md).
function Invoke-CyclicUnitImplChange {
  $Source = Join-Path $Root 'tests\compiler-crash\cyclic-unit-impl-change'
  foreach ($Option in @('O-', 'O2', 'O3')) {
    $Tag = If ($Option -eq 'O-') { 'debug' } Else { $Option.ToLower() }
    $Out = Join-Path $Run "cyclic-unit-impl-change-$Tag"
    New-Item -ItemType Directory -Path $Out | Out-Null
    & $Compiler -n "@$Config" "-$Option" "-Fu$Source" "-FU$Out" "-FE$Out" `
      (Join-Path $Source 'cycmain.dpr') *> (Join-Path $Out 'first.compile.log')
    If ($LASTEXITCODE -ne 0) { throw "cyclic unit/$Option did not compile" }
    & "$Out\cycmain.exe" *> (Join-Path $Out 'first.run.log')
    If (($LASTEXITCODE -ne 0) -or
        (Get-Content -Raw (Join-Path $Out 'first.run.log')).Trim() -ne
        'CYCLIC_UNIT_IMPL_CHANGE_OK 4') { throw "cyclic unit/$Option first run failed" }
    & $Compiler -n "@$Config" "-$Option" -dCYCREL_CHANGED "-Fu$Out" "-Fu$Source" `
      "-FU$Out" "-FE$Out" (Join-Path $Source 'cycrel.pas') `
      *> (Join-Path $Out 'unit.compile.log')
    If ($LASTEXITCODE -ne 0) {
      throw "cyclic unit/$Option - the unit compiled by name crashed the compiler"
    }
    & $Compiler -n "@$Config" "-$Option" -dCYCREL_CHANGED "-Fu$Source" "-FU$Out" "-FE$Out" `
      (Join-Path $Source 'cycmain.dpr') *> (Join-Path $Out 'second.compile.log')
    If ($LASTEXITCODE -ne 0) { throw "cyclic unit/$Option did not compile again" }
    & "$Out\cycmain.exe" *> (Join-Path $Out 'second.run.log')
    If (($LASTEXITCODE -ne 0) -or
        (Get-Content -Raw (Join-Path $Out 'second.run.log')).Trim() -ne
        'CYCLIC_UNIT_IMPL_CHANGE_OK 8') { throw "cyclic unit/$Option second run failed" }
  }
}

function Invoke-CdeclArrayConstPpuReplay {
  $Source = Join-Path $CompilerRoot 'tests\test\cg'
  foreach ($Option in @('O-', 'O2', 'O3')) {
    $Tag = If ($Option -eq 'O-') { 'debug' } Else { $Option.ToLower() }
    $Out = Join-Path $Run "cdecl-array-const-ppu-$Tag"
    New-Item -ItemType Directory -Path $Out | Out-Null
    & $Compiler -n "@$Config" "-$Option" "-FU$Out" "-FE$Out" `
      (Join-Path $Source 'ucdeclopenarray1.pas') `
      *> (Join-Path $Out 'unit.compile.log')
    If ($LASTEXITCODE -ne 0) { throw "cdecl array-of-const unit/$Option did not compile" }
    & $Compiler -n "@$Config" "-$Option" "-Fu$Out" "-FU$Out" "-FE$Out" `
      (Join-Path $Source 'tcdeclopenarrayppu1.pp') `
      *> (Join-Path $Out 'program.compile.log')
    If ($LASTEXITCODE -ne 0) { throw "cdecl array-of-const PPU consumer/$Option did not compile" }
    & "$Out\tcdeclopenarrayppu1.exe" *> (Join-Path $Out 'run.log')
    If ($LASTEXITCODE -ne 0) { throw "cdecl array-of-const PPU replay/$Option failed" }

    & $Compiler -n "@$Config" "-$Option" "-FU$Out" "-FE$Out" `
      (Join-Path $Source 'ucdeclcvarargs1.pas') `
      *> (Join-Path $Out 'c-unit.compile.log')
    If ($LASTEXITCODE -ne 0) { throw "C array-of-const unit/$Option did not compile" }
    & $Compiler -n "@$Config" "-$Option" "-Fu$Out" "-FU$Out" "-FE$Out" `
      (Join-Path $Source 'tcdeclcvarargsppu1.pp') `
      *> (Join-Path $Out 'c-program.compile.log')
    If ($LASTEXITCODE -ne 0) { throw "C array-of-const PPU consumer/$Option did not compile" }
    & "$Out\tcdeclcvarargsppu1.exe" *> (Join-Path $Out 'c-run.log')
    If ($LASTEXITCODE -ne 0) { throw "C array-of-const PPU replay/$Option failed" }

    $RejectedLog = Join-Path $Out 'mismatch.compile.log'
    & $Compiler -n "@$Config" "-$Option" "-Fu$Out" "-FU$Out" "-FE$Out" `
      (Join-Path $Source 'tcdeclarrayconstmismatch1.pp') *> $RejectedLog
    If ($LASTEXITCODE -eq 0) { throw "cdecl array-of-const ABI mismatch/$Option unexpectedly compiled" }
    If ((Get-Content -Raw $RejectedLog) -notmatch 'Error: Incompatible types') {
      throw "cdecl array-of-const ABI mismatch/$Option returned an unexpected diagnostic"
    }
  }
}

function Invoke-InlineForwardInlined {
  # "inline; forward;": the body known before UseAfter is inlined there at O3
  $Out = Join-Path $Run 'inline_forward-asm'
  New-Item -ItemType Directory -Path $Out | Out-Null
  & $Compiler -n "@$Config" -B -O3 -al "-FU$Out" "-FE$Out" `
    "$Root\tests\smoke\inline_forward.pas" *> (Join-Path $Out 'compile.log')
  If ($LASTEXITCODE -ne 0) { throw 'inline_forward/asm did not compile' }
  $Text = Get-Content -Raw (Join-Path $Out 'inline_forward.s')
  $Start = $Text.IndexOf('_USEAFTER$LONGINT$$LONGINT:')
  $End = $Text.IndexOf('PASCALMAIN', $Start)
  If ($Start -lt 0 -or $End -lt 0) { throw 'inline_forward/asm: cannot isolate UseAfter' }
  If ($Text.Substring($Start, $End - $Start) -match "`tcall`t") {
    throw 'inline_forward/asm: UseAfter still calls a routine declared "inline; forward;"'
  }
}

# packages\vcl-compat\tests\utthreading.pp passes a small method with @ to a
# "reference to" parameter; at O3 AUTOINLINE marks the method inline, and the
# call through its procedural type crashed the compiler
# (tests\smoke\procvar_copied_from_routine.pas)
function Invoke-VclCompatThreadingO3 {
  $Out = Join-Path $Run 'vcl-compat-utthreading-o3'
  New-Item -ItemType Directory -Path $Out | Out-Null
  & $Compiler -n "@$Config" -B -O3 "-FU$Out" "-FE$Out" `
    (Join-Path $CompilerRoot 'packages\vcl-compat\tests\utthreading.pp') `
    *> (Join-Path $Out 'compile.log')
  If ($LASTEXITCODE -ne 0) { throw 'vcl-compat utthreading/O3 did not compile' }
}

# A program run once per mode (its first parameter) has to end with the
# given exit code and print the marker of the mode (<NAME>_<MODE>)
function Invoke-ExitCode([string]$Name, [int]$Code, [string[]]$Modes) {
  # the program writes its report to the standard error: in this function a
  # line there is output, not an error of the script
  $ErrorActionPreference = 'Continue'
  foreach ($Option in @('O-', 'O2', 'O3')) {
    $Tag = If ($Option -eq 'O-') { 'debug' } Else { $Option.ToLower() }
    $Out = Join-Path $Run "$Name-$Tag"
    New-Item -ItemType Directory -Path $Out | Out-Null
    & $Compiler -n "@$Config" -B "-$Option" "-FU$Out" "-FE$Out" `
      "-o$Out\$Name.exe" "$Root\tests\smoke\$Name.pas" *> (Join-Path $Out 'compile.log')
    If ($LASTEXITCODE -ne 0) { throw "$Name/$Option did not compile" }
    foreach ($Mode in $Modes) {
      $Log = Join-Path $Out "run-$Mode.log"
      & "$Out\$Name.exe" $Mode *> $Log
      $Exit = $LASTEXITCODE
      If (($Exit -ne $Code) -or
          ((Get-Content -Raw $Log) -notmatch "$($Name.ToUpper())_$($Mode.ToUpper())")) {
        throw "$Name $Mode/$Option ended with $Exit"
      }
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
$VclCompat = Join-Path $CompilerRoot 'packages\vcl-compat\src'
$RtlObjPas = Join-Path $CompilerRoot 'packages\rtl-objpas\src'
# the mode switches the product driver passes (build.ps1 Build-Project)
$DriverModeArgs = @(
  '-Mdelphi', '-Municodestrings', '-MduplicateLocals', '-Madvancedrecords',
  '-Marrayoperators', '-Munderscoreisseparator', '-Mfunctionreferences',
  '-Manonymousfunctions', '-Minlinevars', '-Mimplicitgenerics', '-Mautoderef')

Invoke-Case service_compiler_regressions SERVICE_COMPILER_REGRESSIONS_OK
Invoke-Case message_client_list_clear MESSAGE_CLIENT_LIST_CLEAR_OK
Invoke-Case fmtbcd_variant_cast FMTBCD_VARIANT_CAST_OK
Invoke-Case variant_char_dispatch VARIANT_CHAR_DISPATCH_OK
Invoke-Rejected variant_char_dispatch 'Type is not automatable' `
  @('-dMOONBOT_OBJFPC_CONTROL')
Invoke-Rejected variant_distinct_objfpc_rejected
Invoke-Case dotted_unicode_comparer DOTTED_UNICODE_COMPARER_OK $GenericArgs
Invoke-Case paszlib_delphi_unicode PASZLIB_DELPHI_UNICODE_OK $PaszlibArgs
Invoke-Case delphi_tlist_arrayoft DELPHI_TLIST_ARRAYOFT_OK $GenericSourceArgs
Invoke-AliasReplay
Invoke-O3AutoinlineCycle
Invoke-CyclicUnitImplChange
Invoke-CdeclArrayConstPpuReplay
Invoke-Case generic_return_alias GENERIC_RETURN_ALIAS_OK
Invoke-Case delphi_with_anonymous DELPHI_WITH_ANONYMOUS_OK
Invoke-Case inline_var_aliasing INLINE_VAR_ALIASING_OK
Invoke-Case inline_var_element_actual INLINE_VAR_ELEMENT_ACTUAL_OK
Invoke-Case set_variable_bit_ops SET_VARIABLE_BIT_OPS_OK @('-al')
Invoke-Case array_of_const_dynamic ARRAY_OF_CONST_DYNAMIC_OK
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
Invoke-Rejected inline_const_var_parameter_rejected `
  "Can't assign values to const variable"
Invoke-Case inline_forward INLINE_FORWARD_OK
Invoke-InlineForwardInlined
Invoke-Case procvar_copied_from_routine PROCVAR_COPIED_FROM_ROUTINE_OK
Invoke-VclCompatThreadingO3
# a method, a procedure variable or a routine given to "reference to": in
# Delphi mode read at every call, like an anonymous method (Delphi 12.2
# oracle); in the FPC modes a procedure variable keeps its value per
# conversion; what cannot be captured is refused as Delphi refuses it
Invoke-Case funcref_value_sources FUNCREF_VALUE_SOURCES_OK
Invoke-Case funcref_value_snapshot_objfpc FUNCREF_VALUE_SNAPSHOT_OBJFPC_OK
Invoke-Rejected funcref_value_var_param_rejected 'Symbol "C" can not be captured'
Invoke-Rejected funcref_value_nested_call_rejected 'Symbol "GetC" can not be captured'
# ... where units meet: a method of another unit's class, a method of the
# class of a unit's interface in the unit's initialization, the main block
Invoke-Case funcref_value_units FUNCREF_VALUE_UNITS_OK
# a safecall routine written in assembler is wrapped like any safecall routine
Invoke-Case safecall_assembler SAFECALL_ASSEMBLER_OK
Invoke-Rejected safecall_nostackframe_rejected 'Procedure directive "NOSTACKFRAME" cannot be used with "SAFECALL"'
# an anonymous function held by a reference type written inside a generic
Invoke-Case generic_inline_funcref GENERIC_INLINE_FUNCREF_OK
# a method of a value (record, object, type of a helper) given to a method
# pointer: Self is the address of the value, which stays in memory - a
# variable in its own storage, a value that is no variable in a variable of
# the routine (Delphi 12.2 oracle); the same with @ in mode objfpc
Invoke-Case method_value_receivers METHOD_VALUE_RECEIVERS_OK
Invoke-Case method_value_receivers_objfpc METHOD_VALUE_RECEIVERS_OBJFPC_OK
# Class receivers attached by procvar conversion must be typed before first pass.
Invoke-Case method_class_receivers METHOD_CLASS_RECEIVERS_OK
# The class enumerator loop and exceptional cleanup keep the same object alive.
Invoke-Case forin_class_lifetime FORIN_CLASS_LIFETIME_OK
# ... and a value that is no variable lives as long as Delphi keeps it: to the
# end of its routine or of the main block, with the unit in the initialization
Invoke-Case method_value_lifetime METHOD_VALUE_LIFETIME_OK
Invoke-MethodValueImplicitFinalizationReplay
# what the finalization of a unit writes reaches the output in a file, as in
# Delphi 12.2
Invoke-Case finalization_output FINALIZATION_OUTPUT_OK
# ... also when the last finalization leaves an I/O error pending: the
# exit writes the standard files, as Delphi's Close does
Invoke-Case io_error_exit_flush IO_ERROR_EXIT_FLUSH_OK
# an I/O error left pending stops no I/O routine, as in Delphi 12.2: text,
# untyped and typed files, directories and the console do their work and
# the pending error survives every routine that succeeds
Invoke-Case io_pending_error IO_PENDING_ERROR_OK
# with I/O checks on, a Read or Write statement does all its items before
# it raises EInOutError, as in Delphi 12.2 (text and typed files)
Invoke-Case io_check_statement IO_CHECK_STATEMENT_OK
Invoke-Case compiler_cstream_setsize COMPILER_CSTREAM_SETSIZE_OK "-Fu$CompilerRoot\compiler"
# an exception that nobody handles ends the program with exit code 1 and
# its own report, as with Delphi 12.2's SysUtils: in the main block, in a
# thread of BeginThread, and with an I/O error left pending
Invoke-ExitCode unhandled_exit_code 1 @('main', 'thread', 'pending')
# the line information of a backtrace (-gl) does not depend on an I/O
# error the program left pending, and the error stays pending
Invoke-Case lineinfo_pending_io LINEINFO_PENDING_IO_OK @('-gl')
# an intrinsic of the compiler has no body and no address
Invoke-Rejected procvar_of_intrinsic_rejected `
  'The address of the compiler intrinsic "Abs" cannot be taken'
# a unit repeating $MODE Delphi under the driver's modes is compiled as without it ...
Invoke-Case mode_delphi_noop MODE_DELPHI_NOOP_OK $DriverModeArgs
# ... and from the FPC start mode the same directive still switches the mode:
# the unit's inline variable is then a syntax error
Invoke-Rejected mode_delphi_noop 'Syntax error'
& python "$PSScriptRoot\run_exit_runtime_gate.py" --compiler $Compiler --config $Config --results "$Run\exit-runtime"
If ($LASTEXITCODE -ne 0) { throw "exit runtime gate failed" }
$Inputs = @(
  $Compiler, $Config,
  (Join-Path $Root 'tests\smoke\service_compiler_regressions.pas'),
  (Join-Path $Root 'tests\smoke\message_client_list_clear.pas'),
  (Join-Path $Root 'tests\smoke\fmtbcd_variant_cast.pas'),
  (Join-Path $VclCompat 'system.messaging.pp'),
  (Join-Path $RtlObjPas 'inc\fmtbcd.pp'),
  (Join-Path $Root 'tests\smoke\variant_char_dispatch.pas'),
  (Join-Path $Root 'tests\smoke\variant_distinct_objfpc_rejected.pas'),
  (Join-Path $Root 'tests\smoke\dotted_unicode_comparer.pas'),
  (Join-Path $Root 'tests\smoke\paszlib_delphi_unicode.pas'),
  (Join-Path $Root 'tests\smoke\anonymous_callback_var_rejected.pas'),
  (Join-Path $Root 'tests\smoke\anonymous_callback_out_rejected.pas'),
  (Join-Path $Root 'tests\smoke\delphi_tlist_arrayoft.pas'),
  (Join-Path $Root 'tests\smoke\generic_alias_replay.pas'),
  (Join-Path $Root 'tests\smoke\generic_alias_replay_unit.pas'),
  (Join-Path $Root 'tests\compiler-crash\o3-indysecopenssl-provider\README.md'),
  (Join-Path $Root 'tests\compiler-crash\o3-indysecopenssl-provider\O3AutoinlineCycleA.pas'),
  (Join-Path $Root 'tests\compiler-crash\o3-indysecopenssl-provider\O3AutoinlineCycleB.pas'),
  (Join-Path $Root 'tests\compiler-crash\o3-indysecopenssl-provider\O3AutoinlineCycleCrash.dpr'),
  (Join-Path $Root 'tests\compiler-crash\cyclic-unit-impl-change\README.md'),
  (Join-Path $Root 'tests\compiler-crash\cyclic-unit-impl-change\cycrel.pas'),
  (Join-Path $Root 'tests\compiler-crash\cyclic-unit-impl-change\cyctypes.pas'),
  (Join-Path $Root 'tests\compiler-crash\cyclic-unit-impl-change\cycmain.dpr'),
  (Join-Path $CompilerRoot 'tests\test\cg\ucdeclopenarray1.pas'),
  (Join-Path $CompilerRoot 'tests\test\cg\tcdeclopenarrayppu1.pp'),
  (Join-Path $CompilerRoot 'tests\test\cg\ucdeclcvarargs1.pas'),
  (Join-Path $CompilerRoot 'tests\test\cg\tcdeclcvarargsppu1.pp'),
  (Join-Path $CompilerRoot 'tests\test\cg\tcdeclarrayconstmismatch1.pp'),
  (Join-Path $Root 'tests\smoke\generic_return_alias.pas'),
  (Join-Path $Root 'tests\smoke\generic_return_distinct_rejected.pas'),
  (Join-Path $Root 'tests\smoke\generic_return_mismatch_rejected.pas'),
  (Join-Path $Root 'tests\smoke\delphi_with_anonymous.pas'),
  (Join-Path $Root 'tests\smoke\inline_var_aliasing.pas'),
  (Join-Path $Root 'tests\smoke\inline_var_element_actual.pas'),
  (Join-Path $Root 'tests\smoke\set_variable_bit_ops.pas'),
  (Join-Path $Root 'tests\smoke\array_of_const_dynamic.pas'),
  (Join-Path $Root 'tests\smoke\with_rvalue_write_rejected.pas'),
  (Join-Path $Root 'tests\smoke\inline_const_compiletime_rejected.pas'),
  (Join-Path $Root 'tests\smoke\inline_const_var_parameter_rejected.pas'),
  (Join-Path $Root 'tests\smoke\inline_forward.pas'),
  (Join-Path $Root 'tests\smoke\procvar_copied_from_routine.pas'),
  (Join-Path $Root 'tests\smoke\funcref_value_sources.pas'),
  (Join-Path $Root 'tests\smoke\funcref_value_snapshot_objfpc.pas'),
  (Join-Path $Root 'tests\smoke\funcref_value_var_param_rejected.pas'),
  (Join-Path $Root 'tests\smoke\funcref_value_nested_call_rejected.pas'),
  (Join-Path $Root 'tests\smoke\funcref_value_units.pas'),
  (Join-Path $Root 'tests\smoke\funcref_value_units_class_unit.pas'),
  (Join-Path $Root 'tests\smoke\funcref_value_units_user_unit.pas'),
  (Join-Path $Root 'tests\smoke\safecall_assembler.pas'),
  (Join-Path $Root 'tests\smoke\safecall_nostackframe_rejected.pas'),
  (Join-Path $Root 'tests\smoke\generic_inline_funcref.pas'),
  (Join-Path $Root 'tests\smoke\method_value_receivers.pas'),
  (Join-Path $Root 'tests\smoke\method_value_receivers_unit.pas'),
  (Join-Path $Root 'tests\smoke\method_value_receivers_objfpc.pas'),
  (Join-Path $Root 'tests\smoke\method_class_receivers.pas'),
  (Join-Path $Root 'tests\smoke\forin_class_lifetime.pas'),
  (Join-Path $Root 'tests\smoke\method_value_lifetime.pas'),
  (Join-Path $Root 'tests\smoke\method_value_lifetime_unit.pas'),
  (Join-Path $Root 'tests\smoke\method_value_implicit_finalization.pas'),
  (Join-Path $Root 'tests\smoke\method_value_implicit_finalization_unit.pas'),
  (Join-Path $Root 'tests\smoke\finalization_output.pas'),
  (Join-Path $Root 'tests\smoke\finalization_output_unit.pas'),
  (Join-Path $Root 'tests\smoke\io_error_exit_flush.pas'),
  (Join-Path $Root 'tests\smoke\io_error_exit_flush_unit.pas'),
  (Join-Path $Root 'tests\smoke\io_pending_error.pas'),
  (Join-Path $Root 'tests\smoke\io_check_statement.pas'),
  (Join-Path $Root 'tests\smoke\compiler_cstream_setsize.pas'),
  (Join-Path $Root 'tests\smoke\unhandled_exit_code.pas'),
  (Join-Path $Root 'tests\smoke\lineinfo_pending_io.pas'),
  (Join-Path $Root 'tests\smoke\procvar_of_intrinsic_rejected.pas'),
  (Join-Path $CompilerRoot 'packages\vcl-compat\tests\utthreading.pp'),
  (Join-Path $Root 'tests\smoke\mode_delphi_noop.pas'),
  (Join-Path $Root 'tests\smoke\mode_delphi_noop_unit.pas'))
$Inputs += @((Join-Path $Root 'scripts\run_exit_runtime_gate.py'), (Join-Path $Root 'tests\smoke\exit_runtime_contract.pas'))
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
Write-Output 'SERVICE_REGRESSIONS_GATE_OK positive=39 negative=15 modes=3'

exit 0

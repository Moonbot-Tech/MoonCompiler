#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: scripts/run_service_regressions_gate.sh /path/to/fpc /path/to/moon-base.cfg run-id" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC=$(realpath "$1")
CFG=$(realpath "$2")
RUN="$ROOT/results/runs/$3/service-regressions"
COMPILER_ROOT=$(realpath "$ROOT/../..")

[[ -x "$FPC" && -f "$CFG" ]] || usage
[[ -d "$COMPILER_ROOT/packages/rtl-generics/namespaced" ]] || usage
[[ ! -e "$RUN" ]] || {
  echo "run already exists: $RUN" >&2
  exit 1
}
mkdir -p "$RUN"

run_case() {
  local source=$1 expected=$2 source_group=$3 option tag out
  local -a source_paths
  source_paths=()
  case "$source_group" in
    dotted-generics)
      source_paths=(
        -Fu"$COMPILER_ROOT/packages/rtl-generics/namespaced"
        -Fi"$COMPILER_ROOT/packages/rtl-generics/src"
        -Fi"$COMPILER_ROOT/packages/rtl-generics/src/inc"
        -UaSystem.Classes=Classes
        -UaSystem.SysUtils=SysUtils
        -UaSystem.TypInfo=TypInfo
        -UaSystem.Variants=Variants
        -UaSystem.Math=Math
        -UaSystem.CPU=CPU
      )
      ;;
    dotted-paszlib)
      source_paths=(
        -Fu"$COMPILER_ROOT/packages/paszlib/namespaced"
        -Fi"$COMPILER_ROOT/packages/paszlib/src"
        -UaSystem.SysUtils=SysUtils
      )
      ;;
    generic-source)
      source_paths=(
        -Fu"$COMPILER_ROOT/packages/rtl-generics/src"
        -Fi"$COMPILER_ROOT/packages/rtl-generics/src"
        -Fi"$COMPILER_ROOT/packages/rtl-generics/src/inc"
        -UaSystem.Generics.Collections=Generics.Collections
      )
      ;;
    external-asm)
      source_paths=(-al)
      ;;
    lineinfo)
      source_paths=(-gl)
      ;;
    driver-modes)
      # the mode switches the product driver passes (build configure_project_profile)
      source_paths=(
        -Mdelphi -Municodestrings -MduplicateLocals -Madvancedrecords
        -Marrayoperators -Munderscoreisseparator -Mfunctionreferences
        -Manonymousfunctions -Minlinevars -Mimplicitgenerics -Mautoderef
      )
      ;;
    compiler-streams)
      source_paths=(-Fu"$COMPILER_ROOT/compiler")
      ;;
  esac
  for option in O- O2 O3; do
    [[ "$option" == O- ]] && tag=debug || tag=${option,,}
    out="$RUN/$source-$tag"
    mkdir -p "$out"
    "$FPC" -n "@$CFG" -B "-$option" -Fu"$ROOT/tests/smoke" \
      "${source_paths[@]}" \
      -FU"$out" -FE"$out" "$ROOT/tests/smoke/$source.pas" \
      >"$RUN/$source-$tag.compile.log" 2>&1
    timeout 30 "$out/$source" >"$RUN/$source-$tag.run.log" 2>&1
    grep -qx "$expected" "$RUN/$source-$tag.run.log"
  done
}

run_rejected() {
  local source=$1 diagnostic=$2
  shift 2
  local option tag out log
  for option in O- O2 O3; do
    [[ "$option" == O- ]] && tag=debug || tag=${option,,}
    out="$RUN/$source-rejected-$tag"
    mkdir -p "$out"
    log="$RUN/$source-rejected-$tag.compile.log"
    if "$FPC" -n "@$CFG" -B "-$option" -Fu"$ROOT/tests/smoke" \
      "$@" -FU"$out" -FE"$out" "$ROOT/tests/smoke/$source.pas" \
      >"$log" 2>&1; then
      echo "$source unexpectedly compiled in $option" >&2
      exit 1
    fi
    grep -Eq "$diagnostic" "$log"
  done
}

run_inline_forward_inlined() {
  # "inline; forward;": the body known before UseAfter is inlined there at O3
  local out="$RUN/inline_forward-asm"
  mkdir -p "$out"
  "$FPC" -n "@$CFG" -B -O3 -al -FU"$out" -FE"$out" \
    "$ROOT/tests/smoke/inline_forward.pas" >"$out/compile.log" 2>&1
  awk '/_USEAFTER\$LONGINT\$\$LONGINT:/{inside=1} /PASCALMAIN/{inside=0} inside' \
    "$out/inline_forward.s" >"$out/useafter.s"
  [[ -s "$out/useafter.s" ]] || {
    echo "inline_forward/asm: cannot isolate UseAfter" >&2
    exit 1
  }
  if grep -q $'\tcall\t' "$out/useafter.s"; then
    echo 'inline_forward/asm: UseAfter still calls a routine declared "inline; forward;"' >&2
    exit 1
  fi
}

# packages/vcl-compat/tests/utthreading.pp passes a small method with @ to a
# "reference to" parameter; at O3 AUTOINLINE marks the method inline, and the
# call through its procedural type crashed the compiler
# (tests/smoke/procvar_copied_from_routine.pas)
run_vcl_compat_threading_o3() {
  local out="$RUN/vcl-compat-utthreading-o3"
  mkdir -p "$out"
  "$FPC" -n "@$CFG" -B -O3 -FU"$out" -FE"$out" \
    "$COMPILER_ROOT/packages/vcl-compat/tests/utthreading.pp" \
    >"$out/compile.log" 2>&1
}

# A program run once per mode (its first parameter) has to end with the
# given exit code and print the marker of the mode (<NAME>_<MODE>)
run_exit_code() {
  local source=$1 code=$2 option tag out mode rc
  shift 2
  for option in O- O2 O3; do
    [[ "$option" == O- ]] && tag=debug || tag=${option,,}
    out="$RUN/$source-$tag"
    mkdir -p "$out"
    "$FPC" -n "@$CFG" -B "-$option" -FU"$out" -FE"$out" \
      "$ROOT/tests/smoke/$source.pas" >"$RUN/$source-$tag.compile.log" 2>&1
    for mode in "$@"; do
      rc=0
      timeout 30 "$out/$source" "$mode" >"$RUN/$source-$mode-$tag.run.log" 2>&1 || rc=$?
      if [[ $rc -ne $code ]] ||
         ! grep -q "${source^^}_${mode^^}" "$RUN/$source-$mode-$tag.run.log"; then
        echo "$source $mode/$option ended with $rc" >&2
        exit 1
      fi
    done
  done
}

run_alias_replay() {
  local option tag out
  for option in O- O2 O3; do
    [[ "$option" == O- ]] && tag=debug || tag=${option,,}
    out="$RUN/generic_alias_replay-$tag"
    mkdir -p "$out"
    "$FPC" -n "@$CFG" "-$option" -Mdelphi \
      -UaSystem.Generics.Collections=Generics.Collections \
      -FU"$out" -FE"$out" \
      "$ROOT/tests/smoke/generic_alias_replay_unit.pas" \
      >"$out/unit.compile.log" 2>&1
    cp "$ROOT/tests/smoke/generic_alias_replay.pas" "$out/"
    "$FPC" -n "@$CFG" "-$option" -Mdelphi \
      -UaSystem.Generics.Collections=Generics.Collections \
      -Fu"$out" -FU"$out" -FE"$out" \
      "$out/generic_alias_replay.pas" \
      >"$out/program.compile.log" 2>&1
    timeout 30 "$out/generic_alias_replay" >"$out/run.log" 2>&1
    grep -qx GENERIC_ALIAS_REPLAY_OK "$out/run.log"
  done
}

run_method_value_implicit_finalization_replay() {
  local option tag out
  for option in O- O2 O3; do
    [[ "$option" == O- ]] && tag=debug || tag=${option,,}
    out="$RUN/method_value_implicit_finalization-$tag"
    mkdir -p "$out"
    "$FPC" -n "@$CFG" "-$option" -FU"$out" -FE"$out" \
      "$ROOT/tests/smoke/method_value_implicit_finalization_unit.pas" \
      >"$out/unit.compile.log" 2>&1
    cp "$ROOT/tests/smoke/method_value_implicit_finalization.pas" "$out/"
    "$FPC" -n "@$CFG" "-$option" -Fu"$out" -FU"$out" -FE"$out" \
      "$out/method_value_implicit_finalization.pas" \
      >"$out/program.compile.log" 2>&1
    timeout 30 "$out/method_value_implicit_finalization" >"$out/run.log" 2>&1
    grep -qx METHOD_VALUE_IMPLICIT_FINALIZATION_OK "$out/run.log"
  done
}

run_o3_autoinline_cycle() {
  local source profile tag out
  local -a profile_args
  source="$ROOT/tests/compiler-crash/o3-indysecopenssl-provider"
  for profile in o2 o2-autoinline o3; do
    case "$profile" in
      o2) profile_args=(-O2) ;;
      o2-autoinline) profile_args=(-O2 -OoAUTOINLINE) ;;
      o3) profile_args=(-O3) ;;
    esac
    out="$RUN/o3-autoinline-cycle-$profile"
    mkdir -p "$out"
    "$FPC" -n "@$CFG" -B "${profile_args[@]}" -Fu"$source" \
      -FU"$out" -FE"$out" -o"$out/O3AutoinlineCycleCrash" \
      "$source/O3AutoinlineCycleCrash.dpr" >"$out/compile.log" 2>&1
    timeout 30 "$out/O3AutoinlineCycleCrash" >"$out/run.log" 2>&1
    grep -qx O3_AUTOINLINE_CYCLE_OK "$out/run.log"
  done
}

# A unit compiled by name next to the ppu of a unit that uses it in its implementation and that
# it uses itself, after the body of one of its routines changed: the used unit is compiled again
# and must not leave the first one, already compiled in this run, pointing at its old definitions
# (tests/compiler-crash/cyclic-unit-impl-change/README.md).
run_cyclic_unit_impl_change() {
  local source option tag out
  source="$ROOT/tests/compiler-crash/cyclic-unit-impl-change"
  for option in O- O2 O3; do
    [[ "$option" == O- ]] && tag=debug || tag=${option,,}
    out="$RUN/cyclic-unit-impl-change-$tag"
    mkdir -p "$out"
    "$FPC" -n "@$CFG" "-$option" -Fu"$source" -FU"$out" -FE"$out" \
      "$source/cycmain.dpr" >"$out/first.compile.log" 2>&1
    timeout 30 "$out/cycmain" >"$out/first.run.log" 2>&1
    grep -qx 'CYCLIC_UNIT_IMPL_CHANGE_OK 4' "$out/first.run.log"
    "$FPC" -n "@$CFG" "-$option" -dCYCREL_CHANGED -Fu"$out" -Fu"$source" -FU"$out" -FE"$out" \
      "$source/cycrel.pas" >"$out/unit.compile.log" 2>&1
    "$FPC" -n "@$CFG" "-$option" -dCYCREL_CHANGED -Fu"$source" -FU"$out" -FE"$out" \
      "$source/cycmain.dpr" >"$out/second.compile.log" 2>&1
    timeout 30 "$out/cycmain" >"$out/second.run.log" 2>&1
    grep -qx 'CYCLIC_UNIT_IMPL_CHANGE_OK 8' "$out/second.run.log"
  done
}

run_cdecl_array_const_ppu_replay() {
  local source option tag out
  source="$COMPILER_ROOT/tests/test/cg"
  for option in O- O2 O3; do
    [[ "$option" == O- ]] && tag=debug || tag=${option,,}
    out="$RUN/cdecl-array-const-ppu-$tag"
    mkdir -p "$out"
    "$FPC" -n "@$CFG" "-$option" -FU"$out" -FE"$out" \
      "$source/ucdeclopenarray1.pas" >"$out/unit.compile.log" 2>&1
    "$FPC" -n "@$CFG" "-$option" -Fu"$out" -FU"$out" -FE"$out" \
      "$source/tcdeclopenarrayppu1.pp" >"$out/program.compile.log" 2>&1
    timeout 30 "$out/tcdeclopenarrayppu1" >"$out/run.log" 2>&1

    "$FPC" -n "@$CFG" "-$option" -FU"$out" -FE"$out" \
      "$source/ucdeclcvarargs1.pas" >"$out/c-unit.compile.log" 2>&1
    "$FPC" -n "@$CFG" "-$option" -Fu"$out" -FU"$out" -FE"$out" \
      "$source/tcdeclcvarargsppu1.pp" >"$out/c-program.compile.log" 2>&1
    timeout 30 "$out/tcdeclcvarargsppu1" >"$out/c-run.log" 2>&1

    if "$FPC" -n "@$CFG" "-$option" -Fu"$out" -FU"$out" -FE"$out" \
      "$source/tcdeclarrayconstmismatch1.pp" >"$out/mismatch.compile.log" 2>&1; then
      echo "cdecl array-of-const ABI mismatch unexpectedly compiled in $option" >&2
      exit 1
    fi
    grep -q 'Error: Incompatible types' "$out/mismatch.compile.log"
  done
}

run_case service_compiler_regressions SERVICE_COMPILER_REGRESSIONS_OK plain
run_case message_client_list_clear MESSAGE_CLIENT_LIST_CLEAR_OK plain
run_case fmtbcd_variant_cast FMTBCD_VARIANT_CAST_OK plain
run_case timezone_fd0 TIMEZONE_FD0_OK plain
run_case variant_char_dispatch VARIANT_CHAR_DISPATCH_OK plain
run_rejected variant_char_dispatch 'Type is not automatable' \
  -dMOONBOT_OBJFPC_CONTROL
run_rejected variant_distinct_objfpc_rejected \
  'Error: (Incompatible types|Illegal type conversion)'
run_case dotted_unicode_comparer DOTTED_UNICODE_COMPARER_OK dotted-generics
run_case paszlib_delphi_unicode PASZLIB_DELPHI_UNICODE_OK dotted-paszlib
run_case delphi_tlist_arrayoft DELPHI_TLIST_ARRAYOFT_OK generic-source
run_alias_replay
run_o3_autoinline_cycle
run_cyclic_unit_impl_change
run_cdecl_array_const_ppu_replay
run_case generic_return_alias GENERIC_RETURN_ALIAS_OK plain
run_case delphi_with_anonymous DELPHI_WITH_ANONYMOUS_OK plain
run_case inline_var_aliasing INLINE_VAR_ALIASING_OK plain
run_case inline_var_element_actual INLINE_VAR_ELEMENT_ACTUAL_OK plain
run_case set_variable_bit_ops SET_VARIABLE_BIT_OPS_OK external-asm
run_case array_of_const_dynamic ARRAY_OF_CONST_DYNAMIC_OK plain
run_rejected anonymous_callback_var_rejected \
  'Error: (Incompatible types|Illegal type conversion)'
run_rejected anonymous_callback_out_rejected \
  'Error: (Incompatible types|Illegal type conversion)'
run_rejected generic_return_distinct_rejected \
  'Overloaded functions have the same parameter list'
run_rejected generic_return_mismatch_rejected \
  'Overloaded functions have the same parameter list'
run_rejected with_rvalue_write_rejected \
  "Can't assign values to const variable"
run_rejected inline_const_compiletime_rejected \
  "Can't evaluate constant expression"
run_rejected inline_const_var_parameter_rejected \
  "Can't assign values to const variable"
run_case inline_forward INLINE_FORWARD_OK plain
run_inline_forward_inlined
run_case procvar_copied_from_routine PROCVAR_COPIED_FROM_ROUTINE_OK plain
run_vcl_compat_threading_o3
# a method, a procedure variable or a routine given to "reference to": in
# Delphi mode read at every call, like an anonymous method (Delphi 12.2
# oracle); in the FPC modes a procedure variable keeps its value per
# conversion; what cannot be captured is refused as Delphi refuses it
run_case funcref_value_sources FUNCREF_VALUE_SOURCES_OK plain
run_case funcref_value_snapshot_objfpc FUNCREF_VALUE_SNAPSHOT_OBJFPC_OK plain
run_rejected funcref_value_var_param_rejected 'Symbol "C" can not be captured'
run_rejected funcref_value_nested_call_rejected 'Symbol "GetC" can not be captured'
# ... where units meet: a method of another unit's class, a method of the
# class of a unit's interface in the unit's initialization, the main block
run_case funcref_value_units FUNCREF_VALUE_UNITS_OK plain
# a safecall routine written in assembler is wrapped like any safecall routine
run_case safecall_assembler SAFECALL_ASSEMBLER_OK plain
run_rejected safecall_nostackframe_rejected 'Procedure directive "NOSTACKFRAME" cannot be used with "SAFECALL"'
# an anonymous function held by a reference type written inside a generic
run_case generic_inline_funcref GENERIC_INLINE_FUNCREF_OK plain
# a method of a value (record, object, type of a helper) given to a method
# pointer: Self is the address of the value, which stays in memory - a
# variable in its own storage, a value that is no variable in a variable of
# the routine (Delphi 12.2 oracle); the same with @ in mode objfpc
run_case method_value_receivers METHOD_VALUE_RECEIVERS_OK plain
run_case method_value_receivers_objfpc METHOD_VALUE_RECEIVERS_OBJFPC_OK plain
# Class receivers attached by procvar conversion must be typed before first pass.
run_case method_class_receivers METHOD_CLASS_RECEIVERS_OK plain
# The class enumerator loop and exceptional cleanup keep the same object alive.
run_case forin_class_lifetime FORIN_CLASS_LIFETIME_OK plain
# ... and a value that is no variable lives as long as Delphi keeps it: to the
# end of its routine or of the main block, with the unit in the initialization
run_case method_value_lifetime METHOD_VALUE_LIFETIME_OK plain
run_method_value_implicit_finalization_replay
# what the finalization of a unit writes reaches the output in a file, as in
# Delphi 12.2
run_case finalization_output FINALIZATION_OUTPUT_OK plain
# ... also when the last finalization leaves an I/O error pending: the
# exit writes the standard files, as Delphi's Close does
run_case io_error_exit_flush IO_ERROR_EXIT_FLUSH_OK plain
# an I/O error left pending stops no I/O routine, as in Delphi 12.2: text,
# untyped and typed files, directories and the console do their work and
# the pending error survives every routine that succeeds
run_case io_pending_error IO_PENDING_ERROR_OK plain
# with I/O checks on, a Read or Write statement does all its items before
# it raises EInOutError, as in Delphi 12.2 (text and typed files)
run_case io_check_statement IO_CHECK_STATEMENT_OK plain
run_case compiler_cstream_setsize COMPILER_CSTREAM_SETSIZE_OK compiler-streams
# an exception that nobody handles ends the program with exit code 1 and
# its own report, as with Delphi 12.2's SysUtils: in the main block, in a
# thread of BeginThread, and with an I/O error left pending
run_exit_code unhandled_exit_code 1 main thread pending
# the line information of a backtrace (-gl) does not depend on an I/O
# error the program left pending, and the error stays pending
run_case lineinfo_pending_io LINEINFO_PENDING_IO_OK lineinfo
# an intrinsic of the compiler has no body and no address
run_rejected procvar_of_intrinsic_rejected \
  'The address of the compiler intrinsic "Abs" cannot be taken'
# a unit repeating $MODE Delphi under the driver's modes is compiled as without it ...
run_case mode_delphi_noop MODE_DELPHI_NOOP_OK driver-modes
# ... and from the FPC start mode the same directive still switches the mode:
# the unit's inline variable is then a syntax error
run_rejected mode_delphi_noop 'Syntax error'

python3 "$ROOT/scripts/run_exit_runtime_gate.py" --compiler "$FPC" --config "$CFG" --results "$RUN/exit-runtime"
{
  sha256sum "$FPC" "$CFG" "$ROOT/scripts/run_exit_runtime_gate.py" "$ROOT/tests/smoke/exit_runtime_contract.pas" \
    "$ROOT/tests/smoke/service_compiler_regressions.pas" \
    "$ROOT/tests/smoke/message_client_list_clear.pas" \
    "$ROOT/tests/smoke/fmtbcd_variant_cast.pas" \
    "$ROOT/tests/smoke/timezone_fd0.pas" \
    "$COMPILER_ROOT/rtl/unix/timezone.inc" \
    "$COMPILER_ROOT/packages/vcl-compat/src/system.messaging.pp" \
    "$COMPILER_ROOT/packages/rtl-objpas/src/inc/fmtbcd.pp" \
    "$ROOT/tests/smoke/variant_char_dispatch.pas" \
    "$ROOT/tests/smoke/variant_distinct_objfpc_rejected.pas" \
    "$ROOT/tests/smoke/dotted_unicode_comparer.pas" \
    "$ROOT/tests/smoke/paszlib_delphi_unicode.pas" \
    "$ROOT/tests/smoke/anonymous_callback_var_rejected.pas" \
    "$ROOT/tests/smoke/anonymous_callback_out_rejected.pas" \
    "$ROOT/tests/smoke/delphi_tlist_arrayoft.pas" \
    "$ROOT/tests/smoke/generic_alias_replay.pas" \
    "$ROOT/tests/smoke/generic_alias_replay_unit.pas" \
    "$ROOT/tests/compiler-crash/o3-indysecopenssl-provider/README.md" \
    "$ROOT/tests/compiler-crash/o3-indysecopenssl-provider/O3AutoinlineCycleA.pas" \
    "$ROOT/tests/compiler-crash/o3-indysecopenssl-provider/O3AutoinlineCycleB.pas" \
    "$ROOT/tests/compiler-crash/o3-indysecopenssl-provider/O3AutoinlineCycleCrash.dpr" \
    "$ROOT/tests/compiler-crash/cyclic-unit-impl-change/README.md" \
    "$ROOT/tests/compiler-crash/cyclic-unit-impl-change/cycrel.pas" \
    "$ROOT/tests/compiler-crash/cyclic-unit-impl-change/cyctypes.pas" \
    "$ROOT/tests/compiler-crash/cyclic-unit-impl-change/cycmain.dpr" \
    "$COMPILER_ROOT/tests/test/cg/ucdeclopenarray1.pas" \
    "$COMPILER_ROOT/tests/test/cg/tcdeclopenarrayppu1.pp" \
    "$COMPILER_ROOT/tests/test/cg/ucdeclcvarargs1.pas" \
    "$COMPILER_ROOT/tests/test/cg/tcdeclcvarargsppu1.pp" \
    "$COMPILER_ROOT/tests/test/cg/tcdeclarrayconstmismatch1.pp" \
    "$ROOT/tests/smoke/generic_return_alias.pas" \
    "$ROOT/tests/smoke/generic_return_distinct_rejected.pas" \
    "$ROOT/tests/smoke/generic_return_mismatch_rejected.pas" \
    "$ROOT/tests/smoke/delphi_with_anonymous.pas" \
    "$ROOT/tests/smoke/inline_var_aliasing.pas" \
    "$ROOT/tests/smoke/inline_var_element_actual.pas" \
    "$ROOT/tests/smoke/set_variable_bit_ops.pas" \
    "$ROOT/tests/smoke/array_of_const_dynamic.pas" \
    "$ROOT/tests/smoke/with_rvalue_write_rejected.pas" \
    "$ROOT/tests/smoke/inline_const_compiletime_rejected.pas" \
    "$ROOT/tests/smoke/inline_const_var_parameter_rejected.pas" \
    "$ROOT/tests/smoke/inline_forward.pas" \
    "$ROOT/tests/smoke/procvar_copied_from_routine.pas" \
    "$ROOT/tests/smoke/funcref_value_sources.pas" \
    "$ROOT/tests/smoke/funcref_value_snapshot_objfpc.pas" \
    "$ROOT/tests/smoke/funcref_value_var_param_rejected.pas" \
    "$ROOT/tests/smoke/funcref_value_nested_call_rejected.pas" \
    "$ROOT/tests/smoke/funcref_value_units.pas" \
    "$ROOT/tests/smoke/funcref_value_units_class_unit.pas" \
    "$ROOT/tests/smoke/funcref_value_units_user_unit.pas" \
    "$ROOT/tests/smoke/safecall_assembler.pas" \
    "$ROOT/tests/smoke/safecall_nostackframe_rejected.pas" \
    "$ROOT/tests/smoke/generic_inline_funcref.pas" \
    "$ROOT/tests/smoke/method_value_receivers.pas" \
    "$ROOT/tests/smoke/method_value_receivers_unit.pas" \
    "$ROOT/tests/smoke/method_value_receivers_objfpc.pas" \
    "$ROOT/tests/smoke/method_class_receivers.pas" \
    "$ROOT/tests/smoke/forin_class_lifetime.pas" \
    "$ROOT/tests/smoke/method_value_lifetime.pas" \
    "$ROOT/tests/smoke/method_value_lifetime_unit.pas" \
    "$ROOT/tests/smoke/method_value_implicit_finalization.pas" \
    "$ROOT/tests/smoke/method_value_implicit_finalization_unit.pas" \
    "$ROOT/tests/smoke/finalization_output.pas" \
    "$ROOT/tests/smoke/finalization_output_unit.pas" \
    "$ROOT/tests/smoke/io_error_exit_flush.pas" \
    "$ROOT/tests/smoke/io_error_exit_flush_unit.pas" \
    "$ROOT/tests/smoke/io_pending_error.pas" \
    "$ROOT/tests/smoke/io_check_statement.pas" \
    "$ROOT/tests/smoke/compiler_cstream_setsize.pas" \
    "$ROOT/tests/smoke/unhandled_exit_code.pas" \
    "$ROOT/tests/smoke/lineinfo_pending_io.pas" \
    "$ROOT/tests/smoke/procvar_of_intrinsic_rejected.pas" \
    "$COMPILER_ROOT/packages/vcl-compat/tests/utthreading.pp" \
    "$ROOT/tests/smoke/mode_delphi_noop.pas" \
    "$ROOT/tests/smoke/mode_delphi_noop_unit.pas"
  find "$COMPILER_ROOT/packages/rtl-generics/src" \
    "$COMPILER_ROOT/packages/rtl-generics/namespaced" \
    "$COMPILER_ROOT/packages/paszlib/src" \
    "$COMPILER_ROOT/packages/paszlib/namespaced" -type f \
    \( -name '*.pas' -o -name '*.pp' -o -name '*.inc' \) \
    -print0 | sort -z | xargs -0 -r sha256sum
  find "$RUN" -type f ! -name SHA256SUMS -print0 |
    sort -z | xargs -0 -r sha256sum
} >"$RUN/SHA256SUMS"
echo "SERVICE_REGRESSIONS_GATE_OK positive=40 negative=15 modes=3"

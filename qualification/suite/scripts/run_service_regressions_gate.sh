#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: scripts/run_service_regressions_gate.sh /path/to/fpc /path/to/fpc.cfg run-id" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC=$(realpath "$1")
CFG=$(realpath "$2")
RUN="$ROOT/results/runs/$3/service-regressions"
COMPILER_ROOT=$(realpath "$(dirname "$FPC")/../../..")

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

run_case service_compiler_regressions SERVICE_COMPILER_REGRESSIONS_OK plain
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
run_case generic_return_alias GENERIC_RETURN_ALIAS_OK plain
run_case delphi_with_anonymous DELPHI_WITH_ANONYMOUS_OK plain
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

{
  sha256sum "$FPC" "$CFG" \
    "$ROOT/tests/smoke/service_compiler_regressions.pas" \
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
    "$ROOT/tests/smoke/generic_return_alias.pas" \
    "$ROOT/tests/smoke/generic_return_distinct_rejected.pas" \
    "$ROOT/tests/smoke/generic_return_mismatch_rejected.pas" \
    "$ROOT/tests/smoke/delphi_with_anonymous.pas" \
    "$ROOT/tests/smoke/with_rvalue_write_rejected.pas" \
    "$ROOT/tests/smoke/inline_const_compiletime_rejected.pas" \
    "$ROOT/tests/smoke/inline_const_var_parameter_rejected.pas"
  find "$COMPILER_ROOT/packages/rtl-generics/src" \
    "$COMPILER_ROOT/packages/rtl-generics/namespaced" \
    "$COMPILER_ROOT/packages/paszlib/src" \
    "$COMPILER_ROOT/packages/paszlib/namespaced" -type f \
    \( -name '*.pas' -o -name '*.pp' -o -name '*.inc' \) \
    -print0 | sort -z | xargs -0 -r sha256sum
  find "$RUN" -type f ! -name SHA256SUMS -print0 |
    sort -z | xargs -0 -r sha256sum
} >"$RUN/SHA256SUMS"
echo "SERVICE_REGRESSIONS_GATE_OK positive=9 negative=9 modes=3"

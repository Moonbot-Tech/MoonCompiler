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
  local source=$1 expected=$2 source_group=$3 option out
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
  esac
  for option in O2 O3; do
    out="$RUN/$source-${option,,}"
    mkdir -p "$out"
    "$FPC" -n "@$CFG" -B "-$option" -Fu"$ROOT/tests/smoke" \
      "${source_paths[@]}" \
      -FU"$out" -FE"$out" "$ROOT/tests/smoke/$source.pas" \
      >"$RUN/$source-${option,,}.compile.log" 2>&1
    timeout 30 "$out/$source" >"$RUN/$source-${option,,}.run.log" 2>&1
    grep -qx "$expected" "$RUN/$source-${option,,}.run.log"
  done
}

run_rejected() {
  local source=$1 diagnostic=$2
  shift 2
  local option out log
  for option in O2 O3; do
    out="$RUN/$source-${option,,}"
    mkdir -p "$out"
    log="$RUN/$source-${option,,}.compile.log"
    if "$FPC" -n "@$CFG" -B "-$option" -Fu"$ROOT/tests/smoke" \
      "$@" -FU"$out" -FE"$out" "$ROOT/tests/smoke/$source.pas" \
      >"$log" 2>&1; then
      echo "$source unexpectedly compiled in $option" >&2
      exit 1
    fi
    grep -Eq "$diagnostic" "$log"
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
run_rejected anonymous_callback_var_rejected \
  'Error: (Incompatible types|Illegal type conversion)'
run_rejected anonymous_callback_out_rejected \
  'Error: (Incompatible types|Illegal type conversion)'

{
  sha256sum "$FPC" "$CFG" \
    "$ROOT/tests/smoke/service_compiler_regressions.pas" \
    "$ROOT/tests/smoke/variant_char_dispatch.pas" \
    "$ROOT/tests/smoke/variant_distinct_objfpc_rejected.pas" \
    "$ROOT/tests/smoke/dotted_unicode_comparer.pas" \
    "$ROOT/tests/smoke/paszlib_delphi_unicode.pas" \
    "$ROOT/tests/smoke/anonymous_callback_var_rejected.pas" \
    "$ROOT/tests/smoke/anonymous_callback_out_rejected.pas"
  find "$COMPILER_ROOT/packages/rtl-generics/src" \
    "$COMPILER_ROOT/packages/rtl-generics/namespaced" \
    "$COMPILER_ROOT/packages/paszlib/src" \
    "$COMPILER_ROOT/packages/paszlib/namespaced" -type f \
    \( -name '*.pas' -o -name '*.pp' -o -name '*.inc' \) \
    -print0 | sort -z | xargs -0 -r sha256sum
  find "$RUN" -type f ! -name SHA256SUMS -print0 |
    sort -z | xargs -0 -r sha256sum
} >"$RUN/SHA256SUMS"
echo "SERVICE_REGRESSIONS_GATE_OK positive=4 negative=4 modes=2"

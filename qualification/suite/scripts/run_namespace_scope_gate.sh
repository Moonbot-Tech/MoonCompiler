#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: scripts/run_namespace_scope_gate.sh /path/to/fpc /path/to/fpc.cfg run-id" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC=$(realpath "$1")
CFG=$(realpath "$2")
RUN="$ROOT/results/runs/$3/namespace-scope"
FIXTURES="$ROOT/tests/mega/omni/namespace_scope"

[[ -x "$FPC" && -f "$CFG" ]] || usage
[[ ! -e "$RUN" ]] || {
  echo "run already exists: $RUN" >&2
  exit 1
}
mkdir -p "$RUN"

run_fixture() {
  local name=$1 option=$2 source_dir out mode log
  source_dir="$FIXTURES/$name"
  out="$RUN/$name-${option,,}"
  mkdir -p "$out"

  for mode in clean reuse; do
    log="$RUN/$name-${option,,}-$mode.compile.log"
    if [[ "$mode" == clean ]]; then
      rebuild=(-B)
    else
      rebuild=()
    fi
    "$FPC" -n "@$CFG" -Mdelphi "-$option" -FN"ScopeX" \
      "${rebuild[@]}" -Fu"$source_dir" -Fu"$out" -FU"$out" -FE"$out" \
      "$source_dir/namespace_scope_$name.dpr" >"$log" 2>&1
    "$out/namespace_scope_$name" >"$RUN/$name-${option,,}-$mode.run.log"
    grep -q "NAMESPACE_SCOPE_${name^^}_PASS" \
      "$RUN/$name-${option,,}-$mode.run.log"
  done
}

run_alias_case() {
  local option=$1 source_dir out mode log
  source_dir="$FIXTURES/alias_case"
  out="$RUN/alias_case-${option,,}"
  mkdir -p "$out"

  for mode in clean reuse; do
    log="$RUN/alias_case-${option,,}-$mode.compile.log"
    if [[ "$mode" == clean ]]; then
      rebuild=(-B)
    else
      rebuild=()
    fi
    "$FPC" -n "@$CFG" -Mdelphi "-$option" -FNScopeX -UaFoo=Bar \
      "${rebuild[@]}" -Fu"$source_dir" -Fu"$out" -FU"$out" -FE"$out" \
      "$source_dir/namespace_scope_alias_case.dpr" >"$log" 2>&1
    "$out/namespace_scope_alias_case" >"$RUN/alias_case-${option,,}-$mode.run.log"
    grep -qx NAMESPACE_SCOPE_ALIAS_CASE_PASS \
      "$RUN/alias_case-${option,,}-$mode.run.log"
  done
}

run_reverse_alias_case() {
  local option=$1 source_dir out mode log
  source_dir="$FIXTURES/reverse_alias"
  out="$RUN/reverse_alias-${option,,}"
  mkdir -p "$out"

  for mode in clean reuse; do
    log="$RUN/reverse_alias-${option,,}-$mode.compile.log"
    if [[ "$mode" == clean ]]; then
      rebuild=(-B)
    else
      rebuild=()
    fi
    "$FPC" -n "@$CFG" -Mdelphi "-$option" -FNScopeX \
      -UaScopeX.AliasTarget=AliasTarget \
      "${rebuild[@]}" -Fu"$source_dir" -Fu"$out" -FU"$out" -FE"$out" \
      "$source_dir/namespace_scope_reverse_alias.dpr" >"$log" 2>&1
    "$out/namespace_scope_reverse_alias" \
      >"$RUN/reverse_alias-${option,,}-$mode.run.log"
    grep -qx NAMESPACE_SCOPE_REVERSE_ALIAS_PASS \
      "$RUN/reverse_alias-${option,,}-$mode.run.log"
  done
}

for option in O2 O3; do
  run_fixture fallback "$option"
  run_fixture partial "$option"
  run_fixture precedence "$option"
  run_fixture nested_generic "$option"
  run_alias_case "$option"
  run_reverse_alias_case "$option"
done

sha256sum "$FPC" "$CFG" \
  "$FIXTURES"/*/*.pas "$FIXTURES"/*/*.dpr \
  "$RUN"/*.compile.log "$RUN"/*.run.log >"$RUN/SHA256SUMS"
echo "NAMESPACE_SCOPE_GATE_OK modes=2 builds=24"

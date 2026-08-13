#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: scripts/run_exception_capture_gate.sh /path/to/fpc /path/to/fpc.cfg run-id" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
TEST_ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_FPC=$(realpath "$1")
TEST_CFG=$(realpath "$2")
TEST_RUN="$TEST_ROOT/results/runs/$3/exception-capture"

[[ -x "$TEST_FPC" && -f "$TEST_CFG" ]] || usage
[[ ! -e "$TEST_RUN" ]] || {
  echo "run already exists: $TEST_RUN" >&2
  exit 1
}
mkdir -p "$TEST_RUN"

run_case() {
  local source_dir=$1
  local source_name=$2
  local expected=$3
  local option output_dir compile_log run_log
  local -a assembler_option

  for option in O- O2 O3; do
    output_dir="$TEST_RUN/$source_name-${option,,}"
    compile_log="$TEST_RUN/$source_name-${option,,}.compile.log"
    run_log="$TEST_RUN/$source_name-${option,,}.run.log"
    mkdir -p "$output_dir"
    assembler_option=()
    if [[ "$source_name" == anonymous_exception_capture_matrix && "$option" == O3 ]]; then
      assembler_option=(-al)
    fi
    "$TEST_FPC" -n "@$TEST_CFG" -Mdelphi "-$option" \
      "${assembler_option[@]}" \
      -Fu"$TEST_ROOT/tests/smoke" \
      -FU"$output_dir" -FE"$output_dir" \
      "$TEST_ROOT/tests/$source_dir/$source_name.pas" >"$compile_log" 2>&1
    "$output_dir/$source_name" >"$run_log" 2>&1
    diff -u <(printf '%s' "$expected") "$run_log"
  done
}

run_case known anonymous_exception_capture_once $'once\n'
run_case known anonymous_exception_capture_twice $'first\nsecond\n'
run_case smoke anonymous_exception_capture_matrix $'EXCEPTION_CAPTURE_MATRIX_OK\n'
run_case smoke exception_capture_initfinal $'unit-init\nprogram-body\nunit-final\n'

for option in o- o2 o3; do
  matrix_log="$TEST_RUN/anonymous_exception_capture_matrix-$option.compile.log"
  if grep -Eq '(Invoke|InvokeCast|HasProc|CopyProc).*not inlined' "$matrix_log"; then
    echo "function-reference wrapper lost inline eligibility in $option" >&2
    exit 1
  fi
done

matrix_asm="$TEST_RUN/anonymous_exception_capture_matrix-o3/anonymous_exception_capture_matrix.s"
[[ -f "$matrix_asm" ]] || {
  echo "O3 assembly proof is missing" >&2
  exit 1
}
if grep -Eiq 'call[^#]*(INVOKECAST|INVOKE|HASPROC|COPYPROC)' "$matrix_asm"; then
  echo "O3 still contains a direct call to an inline wrapper" >&2
  exit 1
fi

{
  sha256sum "$TEST_FPC" "$TEST_CFG" \
    "$TEST_ROOT/tests/known/anonymous_exception_capture_once.pas" \
    "$TEST_ROOT/tests/known/anonymous_exception_capture_twice.pas" \
    "$TEST_ROOT/tests/smoke/anonymous_exception_capture_matrix.pas" \
    "$TEST_ROOT/tests/smoke/exception_capture_initfinal.pas" \
    "$TEST_ROOT/tests/smoke/exception_capture_initfinal_unit.pas"
  find "$TEST_RUN" -type f ! -name SHA256SUMS -print0 |
    sort -z | xargs -0 -r sha256sum
} >"$TEST_RUN/SHA256SUMS"
echo "EXCEPTION_CAPTURE_GATE_OK forms=4 modes=3"

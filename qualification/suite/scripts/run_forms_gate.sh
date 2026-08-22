#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: scripts/run_forms_gate.sh /path/to/fpc /path/to/fpc.cfg run-id" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC=$(realpath "$1")
CFG=$(realpath "$2")
RUN="$ROOT/results/runs/$3/forms"
SUMMARY_ORACLE="$ROOT/tests/mega/forms_expected.tsv"
SEEDS=(1 2 3 7885642623054963745 11400714819323198485 18446744073709551615)
EXPECTED_COMMON=(
  fb1-nan-not-ge
  fb1-nan-not-lt
  fb3-braid-demorgan
  fb3-neg-zero-plus-zero
  fb3-ord-complement-sum
  fb3-ord-mux-nan
  fty-anon-varpart-arm-hi
  fty-anon-varpart-arm-lo
  zoo-stoned-cur-litfloat
)
EXPECTED_OMNI=()

[[ -x "$FPC" && -f "$CFG" ]] || usage
[[ ! -e "$RUN" ]] || {
  echo "run already exists: $RUN" >&2
  exit 1
}
mkdir -p "$RUN"
printf '%s\n' "${EXPECTED_COMMON[@]}" | sort -u >"$RUN/expected-mega_forms.txt"
printf '%s\n' "${EXPECTED_COMMON[@]}" "${EXPECTED_OMNI[@]}" | sort -u \
  >"$RUN/expected-omni_forms.txt"

validate_run() {
  local name=$1 option=$2 seed=$3 log=$4 rc=$5
  local observed expected expected_count terminal expected_terminal
  observed="$log.observed"
  expected="$RUN/expected-$name.txt"
  expected_count=$(wc -l <"$expected")
  grep '^FORMS_FAILURE ' "$log" | sed 's/^FORMS_FAILURE //' | sort >"$observed"
  if ! diff -u "$expected" "$observed" >"$log.diff"; then
    echo "$name $option seed=$seed produced a different failure set" >&2
    cat "$log.diff" >&2
    exit 1
  fi
  [[ $rc -eq 1 ]] || {
    echo "$name $option seed=$seed exited $rc instead of 1" >&2
    exit 1
  }
  terminal=$(tail -n 1 "$log")
  expected_terminal=$(awk -F '\t' -v name="$name" -v seed="$seed" \
    '$1 == name && $2 == seed { print $3 }' "$SUMMARY_ORACLE")
  [[ -n "$expected_terminal" ]] || {
    echo "no terminal oracle for $name seed=$seed" >&2
    exit 1
  }
  [[ "$terminal" == "$expected_terminal" ]] || {
    echo "$name $option seed=$seed has a different terminal summary" >&2
    printf 'expected: %s\nobserved: %s\n' "$expected_terminal" "$terminal" >&2
    exit 1
  }
}

run_program() {
  local name=$1 source=$2 option out seed log rc
  for option in O2 O3; do
    out="$RUN/$name-${option,,}"
    mkdir -p "$out"
    "$FPC" -n "@$CFG" -Mdelphi "-$option" -dHAS_INLINEVAR \
    -dTRY_OLEVARIANT_UTF8 -dTRY_VARIANT_RESERVED_MEMBER \
      -dTRY_VARIANT_DISTINCT_ORDINAL \
      -dTRY_DELPHI_EQUALITY_COMPARER \
      -FU"$out" -FE"$out" -o"$out/$name" "$ROOT/$source" \
      >"$RUN/$name-${option,,}.compile.log" 2>&1
    for seed in "${SEEDS[@]}"; do
      log="$RUN/$name-${option,,}.seed-$seed.log"
      set +e
      timeout 180 "$out/$name" "$seed" >"$log" 2>&1
      rc=$?
      set -e
      printf '%s\n' "$rc" >"$log.exit"
      validate_run "$name" "$option" "$seed" "$log" "$rc"
    done
  done
}

run_public_rtti_known_repro() {
  local option out log expected
  expected="$RUN/rtti-public-method.expected"
  printf '%s\n' 'METHOD=1' 'CODE=1' 'CALLED=1' >"$expected"
  for option in O2 O3; do
    out="$RUN/rtti-public-method-${option,,}"
    mkdir -p "$out"
    "$FPC" -n "@$CFG" -Mdelphi -B "-$option" \
      -FU"$out" -FE"$out" \
      "$ROOT/tests/known/rtti_public_method_code_address.pas" \
      >"$out/compile.log" 2>&1
    log="$out/run.log"
    timeout 30 "$out/rtti_public_method_code_address" >"$log" 2>&1
    diff -u "$expected" "$log"
  done
}

run_program omni_forms tests/mega/omni/omni_forms.dpr
run_program mega_forms tests/mega/integrated-001/mega_forms.dpr
run_public_rtti_known_repro

{
  sha256sum "$FPC" "$CFG" "$SUMMARY_ORACLE" \
    "$ROOT/tests/known/rtti_public_method_code_address.pas"
  find "$ROOT/tests/mega/omni" "$ROOT/tests/mega/integrated-001" -type f \
    \( -name '*.pas' -o -name '*.pp' -o -name '*.inc' -o -name '*.dpr' \) \
    -print0 | sort -z | xargs -0 -r sha256sum
  find "$RUN" -type f ! -name SHA256SUMS -print0 |
    sort -z | xargs -0 -r sha256sum
} >"$RUN/SHA256SUMS"
echo "FORMS_GATE_OK common=${#EXPECTED_COMMON[@]} omni_extra=${#EXPECTED_OMNI[@]} modes=2 seeds=${#SEEDS[@]} programs=2 standalone=2"

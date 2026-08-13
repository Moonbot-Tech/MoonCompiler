#!/usr/bin/env bash
set -euo pipefail

root=${1:?test root is required}
fpc=${2:?current compiler path is required}
cfg=${3:?current compiler test config path is required}
tool_dir=$(cd "$(dirname "$0")" && pwd)
src=$root/src
build=$root/build
results=$root/results

if [[ -e "$build" || -e "$results" ]]; then
  echo "speed root already contains results: $root" >&2
  exit 2
fi

mkdir -p "$build" "$results"
cp "$cfg" "$root/fpc-lab.cfg"
lab_cfg=$root/fpc-lab.cfg
sha256sum \
  "$src/baseline/mormot.core.fpcx64mm.pas" \
  "$src/candidate/mormot.core.fpcx64mm.pas" \
  "$src/mm_crossmachine.dpr" \
  "$src/memory_small_arena_collision.dpr" \
  "$tool_dir/compare_mm_pair.py" \
  "$tool_dir/compare_mm_threeway.py" >"$root/INPUTS.sha256"

compile_variant() {
  local variant=$1
  local out=$build/$variant
  mkdir -p "$out/units"
  "$fpc" -n "@$lab_cfg" -B -O3 \
    -dFPCMM_BOOSTER -dFPCMM_MOONSHARD \
    -Fu"$src/$variant" -FU"$out/units" -FE"$out" \
    -o"mm-cross-$variant" "$src/mm_crossmachine.dpr" \
    >"$out/mm-cross-build.log" 2>&1
  "$fpc" -n "@$lab_cfg" -B -O3 \
    -dFPCMM_BOOSTER -dFPCMM_MOONSHARD -dFPCMM_STANDALONE \
    -dFPCMM_SMALLLASTFREE_TEST \
    -Fu"$src/$variant" -FU"$out/units" -FE"$out" \
    -o"arena-collision-$variant" "$src/memory_small_arena_collision.dpr" \
    >"$out/arena-collision-build.log" 2>&1
}

compile_variant baseline
compile_variant candidate

run_focus() {
  local variant=$1
  local sample=$2
  taskset -c 0,4,8,12 "$build/$variant/mm-cross-$variant" 10 64 focus \
    >"$results/$variant-focus-$sample.txt"
}

# Reverse the order in the middle pair so slow host drift cannot favor one side.
run_focus baseline 1
run_focus candidate 1
run_focus candidate 2
run_focus baseline 2
run_focus baseline 3
run_focus candidate 3

python3 "$tool_dir/compare_mm_pair.py" \
  --left "$results"/baseline-focus-*.txt \
  --right "$results"/candidate-focus-*.txt \
  --left-label baseline --right-label arena-fix \
  >"$results/profile-comparison.md"

run_collision() {
  local variant=$1
  local sample=$2
  set +e
  taskset -c 0 "$build/$variant/arena-collision-$variant" \
    >"$results/$variant-collision-$sample.txt" 2>&1
  local status=$?
  set -e
  printf '%s\n' "$status" >"$results/$variant-collision-$sample.status"
}

run_collision baseline 1
run_collision candidate 1
run_collision candidate 2
run_collision baseline 2
run_collision baseline 3
run_collision candidate 3

for status in "$results"/baseline-collision-*.status; do
  grep -qx '10' "$status"
done
for status in "$results"/candidate-collision-*.status; do
  grep -qx '0' "$status"
done

{
  printf 'captured_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'compiler=%s\n' "$($fpc -iV)"
  uname -a
  lscpu
} >"$root/PROVENANCE.txt"
printf 'ARENA_SPEED_PAIR_PASS\n' >"$root/SUMMARY.txt"
cat "$results/profile-comparison.md"

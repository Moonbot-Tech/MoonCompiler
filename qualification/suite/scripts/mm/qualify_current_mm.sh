#!/usr/bin/env bash
set -euo pipefail

root=${1:?qualification root is required}
fpc=${2:?current compiler path is required}
cfg=${3:?current compiler test config path is required}
mm=${4:?bundled memory-manager source is required}
seed=${5:-5579800982869324342}
tool_dir=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$tool_dir/../../tests/memory" && pwd)
mm=$(realpath "$mm")
mm_dir=$(dirname "$mm")
build=$root/build
results=$root/results

if [[ -e "$build" || -e "$results" || -e "$root/EVIDENCE.sha256" ]]; then
  echo "qualification root already contains results: $root" >&2
  exit 2
fi
mkdir -p "$build" "$results"
mkdir -p "$root/toolchain"
cp "$fpc" "$root/toolchain/fpc-exact"
cp "$cfg" "$root/toolchain/fpc.cfg"
# Standalone allocator probes use the ordinary compiler/RTL config, without
# the product-only MM link contract.
cp "$cfg" "$root/toolchain/fpc-lab.cfg"
lab_cfg=$root/toolchain/fpc-lab.cfg

compile_test() {
  local profile=$1
  local name=$2
  local source=$3
  shift 3
  local out=$build/$name
  local profile_args=()
  case "$profile" in
    product)
      profile_args=(
        -dMOONBOT_MM_PROFILE_REQUIRED -dFPCMM_BOOSTER -dFPCMM_MOONSHARD
      )
      ;;
    standalone)
      ;;
    *)
      echo "invalid MM test profile: $profile" >&2
      exit 2
      ;;
  esac
  mkdir -p "$out/units"
  "$fpc" -n "@$lab_cfg" -B -O3 -gl \
    "${profile_args[@]}" \
    "--pinned-unit=mormot.core.fpcx64mm=$mm" \
    -Fu"$src" -Fu"$mm_dir" -FU"$out/units" -FE"$out" -o"$name" \
    "$@" "$src/$source" >"$out/build.log" 2>&1
  sha256sum "$out/$name" "$src/$source" \
    "$mm" >"$out/INPUTS.sha256"
}

run_one() {
  local name=$1
  shift
  local out=$results/$name
  mkdir -p "$out"
  set +e
  /usr/bin/time -v -o "$out/run.time" timeout 480s "$@" \
    >"$out/run.log" 2>&1
  local status=$?
  set -e
  printf '%s\n' "$status" >"$out/run.status"
  return "$status"
}

repeat_test() {
  local name=$1
  local binary=$2
  local out=$results/$name-100
  "$(dirname "$0")/run_historical_repeats.sh" \
    "$binary" "$out" 100 4 ignored 0 60
  grep -qx 'passed=100' "$out/SUMMARY.txt"
  grep -qx 'failed=0' "$out/SUMMARY.txt"
  test ! -s "$out/FAILURES"
}

compile_test standalone small-pool-finalize memory_small_pool_last_free_finalize.dpr \
  -dFPCMM_STANDALONE -dFPCMM_MEDIUMLASTFREE_TEST
compile_test standalone medium-finalize memory_medium_last_free_finalize.dpr \
  -dFPCMM_STANDALONE -dFPCMM_MEDIUMLASTFREE_TEST
compile_test standalone small-finalize memory_small_last_free_finalize.dpr \
  -dFPCMM_STANDALONE -dFPCMM_SMALLLASTFREE_TEST
compile_test product small-pool-leak-report memory_small_pool_last_free_finalize.dpr \
  -dFPCMM_REPORTMEMORYLEAKS -dFPCMM_MEDIUMLASTFREE_TEST
compile_test product memory-large-boundary memory_large_boundary.dpr
compile_test product memory-mega memory_mega.dpr
compile_test product memory-chaos memory_chaos.dpr
compile_test product memory-chaos-diagnostic memory_chaos.dpr \
  -dFPCX64MM_DIAGNOSTIC -dFPCX64MM_DIAGNOSTIC_LARGE
compile_test product memory-mm-diagnostic memory_mm_diagnostic.dpr \
  -dFPCX64MM_DIAGNOSTIC -dFPCMM_SMALLLASTFREE_TEST \
  -dFPCMM_MEDIUMLASTFREE_TEST

repeat_test small-pool-finalize \
  "$build/small-pool-finalize/small-pool-finalize"
repeat_test medium-finalize "$build/medium-finalize/medium-finalize"
repeat_test small-finalize "$build/small-finalize/small-finalize"

run_one small-pool-leak-report \
  "$build/small-pool-leak-report/small-pool-leak-report"
grep -q 'SMALL_POOL_LAST_FREE_REPORT_PENDING' \
  "$results/small-pool-leak-report/run.log"
if grep -q 'medium block leak' "$results/small-pool-leak-report/run.log"; then
  echo 'pending small pool was falsely reported as a medium leak' >&2
  exit 1
fi
run_one memory-large-boundary \
  "$build/memory-large-boundary/memory-large-boundary"
grep -q 'MEMORY_LARGE_BOUNDARY_PASS' \
  "$results/memory-large-boundary/run.log"
run_one memory-mega-full "$build/memory-mega/memory-mega" full "$seed"
grep -q 'MEMORY_MEGA_PASS' "$results/memory-mega-full/run.log"
run_one memory-chaos-release "$build/memory-chaos/memory-chaos" \
  all "$seed" 5 8
grep -q 'CHAOS_PASS' "$results/memory-chaos-release/run.log"
run_one memory-chaos-diagnostic \
  "$build/memory-chaos-diagnostic/memory-chaos-diagnostic" \
  all "$seed" 5 8
grep -q 'CHAOS_PASS' "$results/memory-chaos-diagnostic/run.log"
grep -q 'FPCX64MM_DIAGNOSTIC verify live=0 large=0 small-pending=0 medium-pending=0' \
  "$results/memory-chaos-diagnostic/run.log"

diag=$build/memory-mm-diagnostic/memory-mm-diagnostic
for mode in healthy leak; do
  run_one "diagnostic-$mode" "$diag" "$mode"
done
grep -q 'MEMORY_MM_DIAGNOSTIC_PASS healthy' \
  "$results/diagnostic-healthy/run.log"
grep -q 'FPCX64MM_DIAGNOSTIC tagged-live' \
  "$results/diagnostic-leak/run.log"
for mode in doublefree size foreign owner guardlink queue mediumqueue worker; do
  if run_one "diagnostic-$mode" "$diag" "$mode"; then
    echo "diagnostic negative mode unexpectedly returned zero: $mode" >&2
    exit 1
  fi
  test "$(cat "$results/diagnostic-$mode/run.status")" = 218
  grep -q 'FPCX64MM_DIAGNOSTIC first-violation' \
    "$results/diagnostic-$mode/run.log"
done

{
  printf 'captured_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  uname -a
  printf 'compiler_version=%s\n' "$("$fpc" -iV)"
  printf 'compiler_target_cpu=%s\n' "$("$fpc" -iTP)"
  printf 'compiler_target_os=%s\n' "$("$fpc" -iTO)"
  printf 'nproc=%s\n' "$(nproc)"
  printf 'page_size=%s\n' "$(getconf PAGESIZE)"
  lscpu
  printf '\nmeminfo\n'
  cat /proc/meminfo
  printf '\nvm_settings\n'
  for setting in /proc/sys/vm/overcommit_memory \
    /proc/sys/vm/overcommit_ratio \
    /sys/kernel/mm/transparent_hugepage/enabled; do
    printf '%s=' "$setting"
    cat "$setting"
  done
} >"$root/PROVENANCE.txt"

(
  cd "$root"
  sha256sum toolchain/fpc-exact toolchain/fpc.cfg toolchain/fpc-lab.cfg
) >"$root/TOOLCHAIN.sha256"
printf 'CURRENT_MM_QUALIFICATION_PASS\n' >"$root/SUMMARY.txt"
(
  cd "$root"
  find . -type f ! -name EVIDENCE.sha256 -print0 | sort -z | \
    xargs -0 sha256sum
) >"$root/EVIDENCE.sha256"
cat "$root/SUMMARY.txt"

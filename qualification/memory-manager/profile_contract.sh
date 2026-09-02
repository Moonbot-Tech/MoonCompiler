#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
COMPILER=${1:-$ROOT/.moonbot/toolchain/bin/fpc}
CONFIG=${2:-$ROOT/.moonbot/toolchain/etc/fpc.cfg}
MM=$ROOT/runtime/mm/mormot.core.fpcx64mm.pas
SOURCE=$ROOT/qualification/memory-manager/medium_single.dpr
REUSE_SOURCE=$ROOT/qualification/suite/tests/memory/memory_hot_small_pool.dpr
OUTPUT=$ROOT/.qualification/mm-profile-contract

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/negative" "$OUTPUT/disable" "$OUTPUT/standalone" \
  "$OUTPUT/positive"

base=(
  -n "@$CONFIG" -Mdelphi -Tlinux -Px86_64 -B
  -dMOONBOT_MM_PROFILE_REQUIRED
  -uFPCMM_BOOSTER -uFPCMM_MOONSHARD
  -uFPCMM_DISABLE -uFPCMM_STANDALONE
  "--pinned-unit=mormot.core.fpcx64mm=$MM"
  --required-first-unit=mormot.core.fpcx64mm
)

reject() {
  local name=$1 diagnostic=$2
  shift 2
  if "$COMPILER" "${base[@]}" "$@" -FU"$OUTPUT/$name" -FE"$OUTPUT/$name" \
      "$SOURCE" >"$OUTPUT/$name.log" 2>&1; then
    echo "MM profile $name was accepted" >&2
    exit 1
  fi
  grep -Fq "$diagnostic" "$OUTPUT/$name.log" || {
    echo "MM profile $name failed for an unexpected reason" >&2
    exit 1
  }
}

reject negative 'MoonBot MM profile requires FPCMM_BOOSTER'
reject disable 'MoonBot MM profile forbids FPCMM_DISABLE' \
  -dFPCMM_BOOSTER -dFPCMM_MOONSHARD -dFPCMM_DISABLE
reject standalone 'MoonBot MM profile forbids FPCMM_STANDALONE' \
  -dFPCMM_BOOSTER -dFPCMM_MOONSHARD -dFPCMM_STANDALONE

"$COMPILER" "${base[@]}" -dFPCMM_BOOSTER -dFPCMM_MOONSHARD \
  -FU"$OUTPUT/positive" -FE"$OUTPUT/positive" "$SOURCE" \
  >"$OUTPUT/positive.log" 2>&1
"$OUTPUT/positive/medium_single" >"$OUTPUT/positive.out"
grep -qx PASS "$OUTPUT/positive.out"

reuse_base=(
  -n "@$CONFIG" -Mdelphi -Tlinux -Px86_64 -B
  -dMOONCOMPILER_VANILLA_RUNTIME -dFPCMM_SMALLPOOL_REUSE_TEST
  -uMOONBOT_MM_PROFILE_REQUIRED -uFPCMM_SERVER
  -uFPCMM_BOOSTER -uFPCMM_MOONSHARD
  "--pinned-unit=mormot.core.fpcx64mm=$MM"
)

reuse_profile() {
  local name=$1
  shift
  local case_dir=$OUTPUT/reuse-$name
  mkdir -p "$case_dir"
  "$COMPILER" "${reuse_base[@]}" "$@" -FU"$case_dir" -FE"$case_dir" \
    "$REUSE_SOURCE" >"$case_dir.log" 2>&1
  "$case_dir/memory_hot_small_pool" >"$case_dir.out"
  grep -Fq MEMORY_HOT_SMALL_POOL_PASS "$case_dir.out"
}

reuse_profile default
reuse_profile server -dFPCMM_SERVER
reuse_profile booster -dFPCMM_BOOSTER
reuse_profile product -dMOONBOT_MM_PROFILE_REQUIRED \
  -dFPCMM_BOOSTER -dFPCMM_MOONSHARD

echo 'MM profile contract: PASS'

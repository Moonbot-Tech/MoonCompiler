#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
COMPILER=${1:-$ROOT/.moonbot/toolchain/bin/fpc}
CONFIG=${2:-$ROOT/.moonbot/toolchain/etc/fpc.cfg}
MM=$ROOT/runtime/mm/mormot.core.fpcx64mm.pas
SOURCE=$ROOT/qualification/memory-manager/medium_single.dpr
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
echo 'MM profile contract: PASS'

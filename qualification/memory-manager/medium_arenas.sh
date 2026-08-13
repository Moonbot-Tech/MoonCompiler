#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
COMPILER=${1:-$ROOT/.moonbot/toolchain/bin/fpc}
CONFIG=${2:-$ROOT/.moonbot/toolchain/etc/fpc.cfg}
MM=$ROOT/runtime/mm/mormot.core.fpcx64mm.pas
SOURCE=$ROOT/qualification/memory-manager/medium_arenas.dpr
OUTPUT=$ROOT/.qualification/medium-arenas

rm -rf "$OUTPUT"
for entry in 'o2:-O2' 'o3:-O3' 'diagnostic:-O3 -dFPCX64MM_DIAGNOSTIC'; do
  name=${entry%%:*}
  read -r -a options <<<"${entry#*:}"
  target=$OUTPUT/$name
  mkdir -p "$target"
  "$COMPILER" -n "@$CONFIG" -Mdelphi -Tlinux -Px86_64 -B \
    -dMOONBOT_MM_PROFILE_REQUIRED -dFPCMM_BOOSTER -dFPCMM_MOONSHARD \
    "--pinned-unit=mormot.core.fpcx64mm=$MM" \
    -FU"$target" -FE"$target" "${options[@]}" "$SOURCE" \
    >"$target/build.log" 2>&1
  "$target/medium_arenas" >"$target/run.log"
  grep -q '^PASS owners=' "$target/run.log"
done
echo 'medium arenas Linux: PASS'

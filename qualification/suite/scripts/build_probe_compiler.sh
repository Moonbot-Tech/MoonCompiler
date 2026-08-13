#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 LABEL OFFICIAL_REPOSITORY_URL COMMIT" >&2
  exit 2
fi

LAB_ROOT=$(cd "$(dirname "$0")/.." && pwd)
LABEL=$1
REPOSITORY_URL=$2
COMMIT=$3

case "$LABEL" in
  *[!a-zA-Z0-9._-]*|'') echo "invalid label" >&2; exit 2 ;;
esac
case "$REPOSITORY_URL" in
  https://gitlab.com/freepascal.org/fpc/source.git|https://github.com/UnleashedPascal/compiler.git) ;;
  *) echo "repository is outside the official FPC/Unleashed source policy" >&2; exit 2 ;;
esac
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "commit must be a full SHA-1" >&2; exit 2; }

CHECKOUT="$LAB_ROOT/checkouts/$LABEL"
LOG_DIR="$LAB_ROOT/results/build/$LABEL"
if [[ -e "$CHECKOUT" || -e "$LOG_DIR" ]]; then
  echo "refusing to overwrite existing checkout or log directory for $LABEL" >&2
  exit 2
fi

mkdir -p "$LOG_DIR"
git clone --filter=blob:none --no-checkout "$REPOSITORY_URL" "$CHECKOUT" \
  >"$LOG_DIR/clone.log" 2>&1
git -C "$CHECKOUT" checkout --detach "$COMMIT" >>"$LOG_DIR/clone.log" 2>&1
test "$(git -C "$CHECKOUT" rev-parse HEAD)" = "$COMMIT"
test -z "$(git -C "$CHECKOUT" status --porcelain)"

nice -n 15 ionice -c2 -n7 timeout 1800s \
  make -C "$CHECKOUT" -j1 compiler_cycle FPC=/usr/bin/fpc OPT=-O2 \
  >"$LOG_DIR/compiler-cycle.log" 2>&1

test -x "$CHECKOUT/compiler/ppcx64"
nice -n 15 ionice -c2 -n7 timeout 600s \
  make -C "$CHECKOUT/rtl" -j1 clean all \
  FPC="$CHECKOUT/compiler/ppcx64" OPT=-O2 \
  >"$LOG_DIR/rtl-no-wpo.log" 2>&1
test -f "$CHECKOUT/rtl/units/x86_64-linux/system.ppu"
"$CHECKOUT/compiler/ppcx64" -iVSPTPSOTODW >"$LOG_DIR/compiler-info.txt"
printf '%s\n' "$COMMIT" >"$LOG_DIR/commit.txt"
printf 'built probe %s at %s\n' "$LABEL" "$COMMIT"

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
PREFIX="$LAB_ROOT/toolchains/$LABEL"
LOG_DIR="$LAB_ROOT/results/build/$LABEL"

if [[ -e "$CHECKOUT" || -e "$PREFIX" || -e "$LOG_DIR" ]]; then
  echo "refusing to overwrite existing checkout, toolchain, or log directory for $LABEL" >&2
  exit 2
fi

mkdir -p "$LOG_DIR"
git clone --filter=blob:none --no-checkout "$REPOSITORY_URL" "$CHECKOUT" \
  >"$LOG_DIR/clone.log" 2>&1
git -C "$CHECKOUT" checkout --detach "$COMMIT" >>"$LOG_DIR/clone.log" 2>&1
test "$(git -C "$CHECKOUT" rev-parse HEAD)" = "$COMMIT"
test -z "$(git -C "$CHECKOUT" status --porcelain)"

nice -n 15 ionice -c2 -n7 timeout 2700s \
  make -C "$CHECKOUT" -j1 all FPC=/usr/bin/fpc OPT=-O2 \
  >"$LOG_DIR/make.log" 2>&1
nice -n 15 ionice -c2 -n7 timeout 1800s \
  make -C "$CHECKOUT" -j1 install FPC=/usr/bin/fpc OPT=-O2 INSTALL_PREFIX="$PREFIX" \
  >"$LOG_DIR/install.log" 2>&1

VERSION_DIR=$(find "$PREFIX/lib/fpc" -mindepth 1 -maxdepth 1 -type d \
  -name '[0-9]*' -printf '%f\n')
if [[ -z "$VERSION_DIR" || "$VERSION_DIR" == *$'\n'* ]]; then
  echo "could not resolve one installed compiler version directory" >&2
  exit 1
fi
ln -s "../lib/fpc/$VERSION_DIR/ppcx64" "$PREFIX/bin/ppcx64"
mkdir -p "$PREFIX/etc"
"$PREFIX/bin/fpcmkcfg" -d "basepath=$PREFIX/lib/fpc/$VERSION_DIR" \
  -o "$PREFIX/etc/fpc.cfg" >"$LOG_DIR/fpcmkcfg.log" 2>&1

PATH="$PREFIX/bin:$PATH" "$PREFIX/bin/fpc" -n "@$PREFIX/etc/fpc.cfg" -iVSPTPSOTODW \
  >"$LOG_DIR/compiler-info.txt"
printf '%s\n' "$COMMIT" >"$LOG_DIR/commit.txt"
printf 'built %s at %s\n' "$LABEL" "$COMMIT"

#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$ROOT/../.." && pwd)
FPC=${1:-$REPO/.moonbot/toolchain/bin/fpc}
CFG=${2:-$REPO/.moonbot/toolchain/etc/fpc.cfg}
OUT=$REPO/.qualification/extra-corpus

rm -rf "$OUT"
for option in O2 O3; do
  target=$OUT/$option
  mkdir -p "$target"
  if "$FPC" -n "@$CFG" -B "-$option" -Mobjfpc \
      -FU"$target" -FE"$target" "$ROOT/tests/corpus-extra/tgeneric131.pp" \
      >"$target/tgeneric131.log" 2>&1; then
    echo "tgeneric131 $option unexpectedly lost its recorded deviation" >&2
    exit 1
  fi
  grep -q 'Interface type Intf has no valid GUID' "$target/tgeneric131.log" || {
    echo "tgeneric131 $option failed differently" >&2
    exit 1
  }
  "$FPC" -n "@$CFG" -B "-$option" -Mdelphi \
    -FU"$target" -FE"$target" "$ROOT/tests/corpus-extra/delphi_tb0728.pas" \
    >"$target/delphi_tb0728.log" 2>&1
  "$target/delphi_tb0728" >"$target/delphi_tb0728.out"
  grep -qx DELPHI_TB0728_OK "$target/delphi_tb0728.out"
done
echo 'extra corpus Linux: PASS'

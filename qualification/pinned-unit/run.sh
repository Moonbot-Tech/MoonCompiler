#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
FIXTURES=$ROOT/qualification/pinned-unit
COMPILER=${1:-$ROOT/.moonbot/toolchain/bin/ppcx64}
RTL=$ROOT/rtl/units/x86_64-linux
OUTPUT=$ROOT/.qualification/pinned-unit
PINNED=$FIXTURES/pinned/PinFixture.pas
FOREIGN=$FIXTURES/foreign

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/stale-ppu"
"$COMPILER" -n -Mdelphi -O2 -B -Fu"$RTL" -FU"$OUTPUT/stale-ppu" \
  "$FOREIGN/PinFixture.pas" >"$OUTPUT/stale-ppu/build.log" 2>&1

compile() {
  local program=$1 name=$2 expected=$3 diagnostic=$4
  shift 4
  local target=$OUTPUT/$name
  mkdir -p "$target"
  set +e
  "$COMPILER" -n -Mdelphi -O2 -B -Fu"$RTL" \
    -Fu"$OUTPUT/stale-ppu" -Fu"$FOREIGN" -FU"$target" -FE"$target" \
    -o"$target/$name" "$@" "$FIXTURES/$program" >"$target/build.log" 2>&1
  local status=$?
  set -e
  if [[ "$expected" == fail ]]; then
    (( status != 0 )) || { echo "$program unexpectedly compiled" >&2; exit 1; }
    [[ -z "$diagnostic" ]] || grep -Fq "$diagnostic" "$target/build.log" || {
      echo "$program returned an unexpected diagnostic" >&2
      exit 1
    }
  else
    (( status == 0 )) || { echo "$program did not compile" >&2; exit 1; }
    "$target/$name"
  fi
}

pin="--pinned-unit=PinFixture=$PINNED"
compile source_wins.dpr source_wins pass '' "$pin"
compile explicit_source_rejected.dpr explicit_source_rejected fail \
  'cannot use explicit source file' "$pin"
compile source_wins.dpr missing_source_rejected fail 'no sources available' \
  '--pinned-unit=PinFixture=/missing/PinFixture.pas'
compile normal_lookup.dpr normal_lookup pass ''
compile foreign_lookup.dpr foreign_lookup pass ''
echo 'pinned-unit: PASS'

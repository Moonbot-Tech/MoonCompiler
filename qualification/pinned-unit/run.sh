#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
FIXTURES=$ROOT/qualification/pinned-unit
COMPILER=${1:-$ROOT/.moonbot/toolchain/bin/fpc}
CONFIG=${2:-$ROOT/.moonbot/toolchain/etc/fpc.cfg}
RTL=$ROOT/rtl/units/x86_64-linux
OUTPUT=$ROOT/.qualification/pinned-unit
PINNED=$FIXTURES/pinned/PinFixture.pas
FOREIGN=$FIXTURES/foreign
MM=$ROOT/runtime/mm/mormot.core.fpcx64mm.pas
NO_PIN_CONFIG=$OUTPUT/fpc-without-product-mm-pin.cfg

[[ -x "$COMPILER" ]] || { echo "compiler not found: $COMPILER" >&2; exit 2; }
[[ -f "$CONFIG" ]] || { echo "compiler config not found: $CONFIG" >&2; exit 2; }

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT/stale-ppu"
grep -v '^--pinned-unit=mormot\.core\.fpcx64mm=' "$CONFIG" > "$NO_PIN_CONFIG"
if cmp -s "$CONFIG" "$NO_PIN_CONFIG"; then
  echo "product MM pin not found in compiler config: $CONFIG" >&2
  exit 2
fi
"$COMPILER" -n "@$CONFIG" -Mdelphi -O2 -B -Fu"$RTL" -FU"$OUTPUT/stale-ppu" \
  "$FOREIGN/PinFixture.pas" >"$OUTPUT/stale-ppu/build.log" 2>&1

compile() {
  local program=$1 name=$2 expected=$3 diagnostic=$4
  shift 4
  local pin_product=1
  local active_config=$CONFIG
  if [[ ${1:-} == --without-product-mm-pin ]]; then
    pin_product=0
    active_config=$NO_PIN_CONFIG
    shift
  fi
  local target=$OUTPUT/$name
  mkdir -p "$target"
  set +e
  local command=("$COMPILER" -n "@$active_config" -Mdelphi -O2 -B -Fu"$RTL"
    -Fu"$OUTPUT/stale-ppu" -Fu"$FOREIGN" -FU"$target" -FE"$target"
    -o"$target/$name")
  if (( pin_product )); then
    command+=("--pinned-unit=mormot.core.fpcx64mm=$MM")
  fi
  command+=("$@" "$FIXTURES/$program")
  "${command[@]}" >"$target/build.log" 2>&1
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
vanilla=-dMOONCOMPILER_VANILLA_RUNTIME
compile source_wins.dpr source_wins pass '' "$pin"
compile explicit_source_rejected.dpr explicit_source_rejected fail \
  'cannot use explicit source file' "$pin"
compile source_wins.dpr missing_source_rejected fail 'no sources available' \
  '--pinned-unit=PinFixture=/missing/PinFixture.pas'
compile normal_lookup.dpr normal_lookup pass ''
compile foreign_lookup.dpr foreign_lookup pass ''
compile source_wins.dpr required_first pass '' "$vanilla" "$pin" \
  --required-first-unit=PinFixture
compile required_prefix.dpr required_prefix pass '' "$vanilla" "$pin" \
  --required-first-unit=PinFixture,NormalFixture
compile source_wins.dpr required_prefix_missing_second fail \
  'explicit unit 2 is <none>' "$vanilla" "$pin" \
  --required-first-unit=PinFixture,NormalFixture
compile normal_lookup.dpr required_missing fail \
  'first explicit unit is NORMALFIXTURE' "$vanilla" \
  --required-first-unit=PinFixture
compile no_uses_rejected.dpr required_no_uses fail \
  'first explicit unit is <none>' "$vanilla" \
  --required-first-unit=PinFixture
compile second_unit_rejected.dpr required_second fail \
  'first explicit unit is NORMALFIXTURE' "$vanilla" "$pin" \
  --required-first-unit=PinFixture
compile conditional_first_rejected.dpr required_conditional fail \
  'first explicit unit is NORMALFIXTURE' "$vanilla" "$pin" \
  --required-first-unit=PinFixture
compile no_uses_rejected.dpr product_runtime_missing_pin fail \
  'requires an exact --pinned-unit mapping' --without-product-mm-pin
compile no_uses_rejected.dpr product_runtime_vanilla pass '' \
  --without-product-mm-pin "$vanilla"
compile cmem_override.dpr product_runtime_cmem_override fail \
  'would replace the bundled product memory manager'
compile cmem_override.dpr product_runtime_cmem_vanilla pass '' "$vanilla"
compile cmem_override.dpr product_runtime_cmem_valgrind pass '' -gv
echo 'pinned-unit: PASS'

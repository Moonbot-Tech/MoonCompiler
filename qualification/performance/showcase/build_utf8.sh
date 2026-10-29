#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p bin units-utf8
sdk="${MOON_SDK:-$PWD/sdk}"
mormot="${MORMOT_ROOT:?Set MORMOT_ROOT to the matching MoonORMot checkout}"
for program in dictionary_slice_probe trade_slice_contract showcase_moon; do
  "$sdk/bin/fpc" -dRELEASE -O3 -Fucommon -Fuunits-utf8 -Fu"$mormot/core" -Fi"$mormot/core" \
    -Fl"$mormot/static/x86_64-linux" -FEbin -FUunits-utf8 "$program.dpr" > "build-$program.log" 2>&1
done
"$HOME/.cargo/bin/cargo" build --release --offline --locked > build-rust.log 2>&1
cp target/release/showcase_rust bin/
bin/trade_slice_contract
sha256sum bin/* common/*.pas *.dpr showcase.rs Cargo.lock > UTF8_BUILD.sha256

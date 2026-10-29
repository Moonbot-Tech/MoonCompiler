#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p bin units
: "${MOON_COMPILER:?Path to ppcx64}"
: "${MOON_CONFIG:?Path to the matching product.cfg}"
: "${MORMOT_ROOT:?Matching MoonORMot directory}"
# Existing compatible PPU files may be reused; all newly built files stay here.
extra=()
if [ -n "${MOON_UNITS:-}" ]; then extra+=("-Fu$MOON_UNITS"); fi
"$MOON_COMPILER" -n "@$MOON_CONFIG" -dRELEASE -O3 \
  "-Fu$MORMOT_ROOT/core" "-Fi$MORMOT_ROOT/core" \
  "-Fl$MORMOT_ROOT/static/x86_64-linux" "${extra[@]}" \
  -FUunits -FEbin orderbook_moon.dpr > build-moon.log 2>&1
"$HOME/.cargo/bin/cargo" build --release --offline --locked > build-rust.log 2>&1
cp "${CARGO_TARGET_DIR:-target}/release/orderbook_rust" bin/
{
  sha256sum bin/orderbook_moon bin/orderbook_rust "$MOON_COMPILER" "$MOON_CONFIG"
  git -C "$MORMOT_ROOT" rev-parse HEAD
  "$HOME/.cargo/bin/rustc" --version
  printf '%s\n' "Moon: -n @product.cfg -dRELEASE -O3; Rust: Cargo release opt-level=3"
} > build-identity.txt

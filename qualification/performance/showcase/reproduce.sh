#!/usr/bin/env bash
# Build or run the three applied Moon/Rust comparisons.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .reproduce bin/linux-x86_64
run_logged() {
  local log="$1"
  shift
  "$@" > "$log" 2>&1 || { local status=$?; echo "Failed: $*" >&2; tail -30 "$log" >&2; return "$status"; }
}
mode="${1:-run}"
case "$mode" in
  build)
    sdk="$PWD/.reproduce/toolchain"
    mormot="$PWD/.reproduce/mormot"
    revision=f62a8f24ba6f05b8289adf938fc5199395db3cf9
    archive=mooncompiler-toolchain-v2.5.3-linux-x86-64.tar.gz
    if [ ! -x "$sdk/bin/fpc" ]; then
      curl -fL --retry 2 "https://github.com/Moonbot-Tech/MoonCompiler/releases/download/v2.5.3/$archive" -o ".reproduce/$archive"
      echo "93b29f2a77e389fcf7db90ca2b59ec3bc71335a911570ce73a67b627d287229a  .reproduce/$archive" | sha256sum -c -
      mkdir -p "$sdk"
      tar -xzf ".reproduce/$archive" -C "$sdk"
    fi
    if [ ! -d "$mormot/.git" ]; then
      git clone --filter=blob:none --no-checkout https://github.com/Moonbot-Tech/MoonORMot.git "$mormot"
    fi
    git -C "$mormot" checkout --detach "$revision"
    cargo="${CARGO:-$(command -v cargo || true)}"
    if [ -z "$cargo" ] && [ -x "$HOME/.cargo/bin/cargo" ]; then cargo="$HOME/.cargo/bin/cargo"; fi
    if [ -z "$cargo" ]; then echo 'Install Rust 1.97.1 (cargo and rustc) before building.' >&2; exit 1; fi
    case "$("$cargo" --version)" in
      'cargo 1.97.1 '*) ;;
      *) echo 'Select Rust 1.97.1 before building (rustup override set 1.97.1).' >&2; exit 1 ;;
    esac
    mkdir -p .reproduce/units-main .reproduce/units-orderbook
    "$sdk/bin/fpc" -dRELEASE -O3 -Fucommon "-Fu$mormot/core" "-Fi$mormot/core" \
      "-Fl$mormot/static/x86_64-linux" -FU.reproduce/units-main -FEbin/linux-x86_64 \
      showcase_moon.dpr > .reproduce/build-moon.log 2>&1 || { tail -30 .reproduce/build-moon.log; exit 1; }
    "$sdk/bin/fpc" -dRELEASE -O3 "-Fu$mormot/core" "-Fi$mormot/core" \
      "-Fl$mormot/static/x86_64-linux" -FU.reproduce/units-orderbook -FEbin/linux-x86_64 \
      orderbook/orderbook_moon.dpr > .reproduce/build-orderbook.log 2>&1 || { tail -30 .reproduce/build-orderbook.log; exit 1; }
    "$cargo" build --release --locked
    "$cargo" build --release --locked --manifest-path orderbook/Cargo.toml
    cp target/release/showcase_rust orderbook/target/release/orderbook_rust bin/linux-x86_64/
    (cd bin/linux-x86_64 && sha256sum showcase_moon showcase_rust orderbook_moon orderbook_rust > SHA256SUMS)
    {
      printf 'MoonCompiler SDK: v2.5.3\nMoonORMot: %s\n' "$revision"
      "$cargo" --version
      sha256sum "$sdk/bin/ppcx64" common/*.pas showcase_moon.dpr orderbook/orderbook_moon.dpr
    } > .reproduce/build-identity.txt
    echo 'Build complete. Run ./reproduce.sh run'
    ;;
  run)
    cpu="${SHOWCASE_CPU:-$(python3 -c 'import os; print(min(os.sched_getaffinity(0)))')}"
    book_cpu="${SHOWCASE_BOOK_CPU:-$cpu}"
    label="reader-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    run_logged .reproduce/input-check.log sha256sum -c inputs/SHA256SUMS
    (cd bin/linux-x86_64 && sha256sum -c SHA256SUMS) > .reproduce/binary-check.log 2>&1 || { cat .reproduce/binary-check.log >&2; exit 1; }
    chmod +x bin/linux-x86_64/showcase_moon bin/linux-x86_64/showcase_rust bin/linux-x86_64/orderbook_moon bin/linux-x86_64/orderbook_rust
    ln -sf linux-x86_64/showcase_moon bin/showcase_moon
    ln -sf linux-x86_64/showcase_rust bin/showcase_rust
    mkdir -p orderbook/bin
    ln -sf ../../bin/linux-x86_64/orderbook_moon orderbook/bin/orderbook_moon
    ln -sf ../../bin/linux-x86_64/orderbook_rust orderbook/bin/orderbook_rust
    tar -xzf inputs/data-20261029.tar.gz
    run_logged .reproduce/verify-exchange.log python3 verify.py --json-only
    python3 orderbook/bench.py prepare
    run_logged .reproduce/verify-orderbook.log python3 orderbook/bench.py verify
    echo 'PASS: complete exchange document, order-book levels and purchase calculations.'
    run_logged .reproduce/run.log nice -n 10 python3 run.py --cases trades,exchange --cpu "$cpu" --label "$label" --pairs 5
    run_logged .reproduce/run-orderbook.log python3 orderbook/bench.py run --cpu "$book_cpu" --nice 10 --label "$label" --pairs 5 \
      --output "results/$label/orderbook.json"
    python3 reader_summary.py "results/$label"
    ;;
  *) echo 'Usage: ./reproduce.sh run | build' >&2; exit 2 ;;
esac

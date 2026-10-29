#!/bin/bash
set -eu
cd "$(dirname "$0")"
mkdir -p bin units-main units-ring
sdk="${MOON_SDK:-$PWD/sdk}"
mormot="${MORMOT_ROOT:?Set MORMOT_ROOT to the matching MoonORMot checkout}"
"$sdk/bin/fpc" -dRELEASE -O3 -Fucommon -Fu"$mormot/core" -Fi"$mormot/core" \
  -Fl"$mormot/static/x86_64-linux" -FEbin -FUunits-main showcase_moon.dpr > build-moon.log 2>&1
"$sdk/bin/fpc" -dRELEASE -O3 -FEbin -FUunits-ring ring_moon.dpr > build-ring.log 2>&1
g++ -std=c++20 -O3 -DNDEBUG -pthread showcase_cpp.cpp -o bin/showcase_cpp > build-cpp.log 2>&1
g++ -std=c++20 -O3 -DNDEBUG audit_cpp_int.cpp -o bin/audit_cpp_int > build-cpp-control.log 2>&1
"$HOME/.cargo/bin/cargo" build --release --offline --locked > build-rust.log 2>&1
cp target/release/showcase_rust bin/
sha256sum bin/* > BINARIES.sha256
{
  uname -a
  lscpu
  g++ --version
  "$HOME/.cargo/bin/rustc" --version
  "$sdk/bin/fpc" -iV
  git -C "$mormot" rev-parse HEAD
  sha256sum "$sdk/bin/ppcx64" common/*.pas
} > BUILD_ENVIRONMENT.txt

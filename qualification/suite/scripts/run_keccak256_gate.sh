#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER=${1:-$(cd "$ROOT/../.." && pwd)}
RESULTS=${2:-$ROOT/results/keccak256}
SOURCE="$ROOT/tests/smoke/keccak256_vectors.dpr"
MORMOT="$ROOT/../vendor/mormot-product"

[[ -x "$COMPILER/build" ]] || {
  echo "compiler build driver not found: $COMPILER/build" >&2
  exit 1
}

[[ ! -e "$RESULTS" ]] || {
  echo "Keccak-256 gate output already exists: $RESULTS" >&2
  exit 2
}
mkdir -p "$RESULTS"
# mORMot's source uses paths relative to each program directory, e.g.
# ../static/x86_64-linux.  Keep the required platform objects in that exact
# location without copying unrelated Windows, SQLite or QuickJS inputs.
mkdir -p "$RESULTS/static"
cp -a --reflink=auto "$MORMOT/static/x86_64-linux" "$RESULTS/static/"

for profile in debug release; do
  profile_dir="$RESULTS/$profile"
  mkdir -p "$profile_dir"
  cp "$SOURCE" "$profile_dir/keccak256_vectors.dpr"
  cp -a --reflink=auto "$MORMOT/src" "$profile_dir/mormot"
  "$COMPILER/build" "$profile_dir/keccak256_vectors.dpr" "$profile" \
    >"$profile_dir/compile.log" 2>&1
  output=$("$profile_dir/keccak256_vectors")
  [[ "$output" == "KECCAK256_VECTORS_OK" ]] || {
    echo "unexpected $profile output: $output" >&2
    exit 1
  }
done

echo "KECCAK256_GATE_OK profiles=2 vectors=5"

#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER=${1:-$(cd "$ROOT/../.." && pwd)}
RESULTS=${2:-$ROOT/results/keccak256}
SOURCE="$ROOT/tests/smoke/keccak256_vectors.dpr"
MORMOT=$(cd "$ROOT/../../.qualification/deps/moonormot" && pwd)
FPC="$COMPILER/toolchain/bin/fpc"

[[ -x "$FPC" ]] || {
  echo "product compiler not found: $FPC" >&2
  exit 1
}

[[ ! -e "$RESULTS" ]] || {
  echo "Keccak-256 gate output already exists: $RESULTS" >&2
  exit 2
}
mkdir -p "$RESULTS"

# The program is built as an application is: the toolchain's fpc with its
# own configuration, Debug and then Release (-dRELEASE), its units under the
# program's directory.  The qualification MoonORMot comes first on the
# command line, ahead of the mormot directory the configuration names.
for profile in debug release; do
  profile_dir="$RESULTS/$profile"
  mkdir -p "$profile_dir"
  cp "$SOURCE" "$profile_dir/keccak256_vectors.dpr"
  release=()
  [[ $profile == release ]] && release=(-dRELEASE)
  "$FPC" -B "${release[@]}" "-Fu$MORMOT/*" "-Fi$MORMOT" "-Fl$MORMOT/static/x86_64-linux" \
    "$profile_dir/keccak256_vectors.dpr" >"$profile_dir/compile.log" 2>&1
  output=$("$profile_dir/keccak256_vectors")
  [[ "$output" == "KECCAK256_VECTORS_OK" ]] || {
    echo "unexpected $profile output: $output" >&2
    exit 1
  }
done

echo "KECCAK256_GATE_OK profiles=2 vectors=5"

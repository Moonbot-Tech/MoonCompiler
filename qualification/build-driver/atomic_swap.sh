#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$ROOT/scripts/publish_toolchain.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/toolchain"
printf 'working\n' >"$work/toolchain/sentinel"

if publish_toolchain "$work/missing-new" "$work/toolchain" \
    "$work/toolchain.old" 2>/dev/null; then
  echo 'publish unexpectedly succeeded' >&2
  exit 1
fi
grep -qx working "$work/toolchain/sentinel"
[[ ! -e "$work/toolchain.old" ]]
echo TOOLCHAIN_ATOMIC_SWAP_PASS

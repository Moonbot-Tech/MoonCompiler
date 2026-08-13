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

mkdir "$work/double-toolchain" "$work/double-new"
printf 'working\n' >"$work/double-toolchain/sentinel"
move_count=0
faulty_move() {
  move_count=$((move_count + 1))
  if (( move_count >= 2 )); then
    return 1
  fi
  mv "$@"
}
remove_tree() {
  rm "$@"
}
if publish_toolchain_with faulty_move remove_tree "$work/double-new" \
    "$work/double-toolchain" "$work/double-toolchain.old"; then
  echo 'double-fault publish unexpectedly succeeded' >&2
  exit 1
fi
grep -qx working "$work/double-toolchain.old/sentinel"
[[ ! -e "$work/double-toolchain" ]]
echo TOOLCHAIN_ATOMIC_SWAP_PASS

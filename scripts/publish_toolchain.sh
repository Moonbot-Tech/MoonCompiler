#!/usr/bin/env bash

publish_toolchain() {
  publish_toolchain_with mv rm "$@"
}

publish_toolchain_with() {
  local mover=$1 remover=$2 new_toolchain=$3 toolchain=$4 old_toolchain=$5

  if [[ -e "$toolchain" ]]; then
    "$mover" "$toolchain" "$old_toolchain"
  fi
  if ! "$mover" "$new_toolchain" "$toolchain"; then
    if [[ -e "$old_toolchain" && ! -e "$toolchain" ]]; then
      "$mover" "$old_toolchain" "$toolchain" || true
    fi
    return 1
  fi
  "$remover" -rf "$old_toolchain"
}

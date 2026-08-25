#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "usage: scripts/run_rtl_api_surface_gate.sh run-id" >&2
  exit 2
fi

suite_root=$(cd "$(dirname "$0")/.." && pwd)
compiler_root=$(cd "$suite_root/../.." && pwd)
source_root="$suite_root/tests/rtl-api"
run="$suite_root/results/runs/$1/rtl-api-surface"

[[ ! -e "$run" ]] || {
  echo "run already exists: $run" >&2
  exit 1
}
mkdir -p "$run"

for case_name in rtl_api_surface rtl_api_array_copy; do
  if [[ "$case_name" == rtl_api_surface ]]; then
    expected=RTL_API_SURFACE_OK
  else
    expected=RTL_API_ARRAY_COPY_OK
  fi
  for profile in debug release; do
    profile_dir="$run/$case_name/$profile"
    mkdir -p "$profile_dir"
    project="$profile_dir/$case_name.dpr"
    cp "$source_root/$case_name.dpr" "$project"
    if ! "$compiler_root/build" "$project" "$profile" \
        >"$profile_dir/compile.log" 2>&1; then
      echo "$case_name/$profile did not compile" >&2
      exit 1
    fi
    timeout 30 "$profile_dir/$case_name" \
      >"$profile_dir/run.log" 2>&1
    grep -qx "$expected" "$profile_dir/run.log"
  done
done

{
  sha256sum "$source_root/rtl_api_surface.dpr" \
    "$source_root/rtl_api_array_copy.dpr" "$compiler_root/build" \
    "$compiler_root/runtime/mm/mormot.core.fpcx64mm.pas" \
    "$compiler_root/.moonbot/toolchain/bin/fpc" \
    "$compiler_root/.moonbot/toolchain/etc/fpc.cfg"
  find "$run" -type f ! -name SHA256SUMS -print0 |
    sort -z | xargs -0 -r sha256sum
} >"$run/SHA256SUMS"

echo "RTL_API_SURFACE_GATE_OK cases=2 profiles=2"

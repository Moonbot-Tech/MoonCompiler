#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <baseline-toolchain> <patched-toolchain> <result-dir>" >&2
  exit 2
fi

baseline=$(realpath "$1")
patched=$(realpath "$2")
result=$(realpath -m "$3")
root=$(cd "$(dirname "$0")/.." && pwd)
source_dir="$root/tests/rtti"
sources=(rtti_nocall_minimal rtti_nocall)

case "$result/" in
  "$root/results/"*) ;;
  *)
    echo "result directory must be below $root/results" >&2
    exit 2
    ;;
esac
[[ ! -e "$result" ]] || {
  echo "result directory already exists: $result" >&2
  exit 2
}

for test in "${sources[@]}"; do
  for linkmode in normal smart; do
    linkargs=()
    [[ "$linkmode" == smart ]] && linkargs=(-CX -XX)
    for variant in baseline patched; do
      toolchain=$baseline
      [[ "$variant" == patched ]] && toolchain=$patched
      out="$result/$test/$linkmode/$variant"
      mkdir -p "$out/units"
      "$toolchain/bin/fpc" -n "@$toolchain/etc/fpc.cfg" -Mdelphi -B \
        -O3 -gl -gw3 "${linkargs[@]}" "-Fu$source_dir" \
        "-FU$out/units" "-FE$out" "$source_dir/$test.dpr" \
        >"$out/compile.log" 2>&1
      "$out/$test" >"$out/run.log"
      readelf -SW "$out/$test" >"$out/sections.txt"
    done
    cmp "$result/$test/$linkmode/baseline/run.log" \
      "$result/$test/$linkmode/patched/run.log"
  done
done

printf 'test link variant bytes text data bss dec\n'
for test in "${sources[@]}"; do
  for linkmode in normal smart; do
    for variant in baseline patched; do
      binary="$result/$test/$linkmode/$variant/$test"
      bytes=$(stat -c %s "$binary")
      read -r text data bss dec _ < <(size "$binary" | tail -1)
      printf '%s %s %s %s %s %s %s %s\n' \
        "$test" "$linkmode" "$variant" "$bytes" "$text" "$data" "$bss" "$dec"
    done
  done
done

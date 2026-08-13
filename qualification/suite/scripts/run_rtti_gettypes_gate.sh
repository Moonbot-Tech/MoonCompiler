#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <fpc> <fpc.cfg> <run-id>" >&2
  exit 2
fi

fpc=$(realpath "$1")
cfg=$(realpath "$2")
root=$(cd "$(dirname "$0")/.." && pwd)
case "$3" in
  *[!a-zA-Z0-9._-]*|'') echo "invalid run-id" >&2; exit 2 ;;
esac
result="$root/results/runs/$3/rtti-gettypes"
source_dir="$root/tests/rtti"
source="$source_dir/rtti_gettypes.dpr"

[[ ! -e "$result" ]] || {
  echo "run already exists: $result" >&2
  exit 1
}
mkdir -p "$result"

for option in O2 O3; do
  for linking in normal smart; do
    out="$result/$option-$linking"
    mkdir -p "$out/units"
    args=(-n "@$cfg" -Mdelphi -B "-$option" -gl -gw3
      "-Fu$source_dir" "-FU$out/units" "-FE$out")
    if [[ "$linking" == smart ]]; then
      args+=(-CX -XX)
    fi
    "$fpc" "${args[@]}" "$source" >"$out/compile.log" 2>&1
    timeout 30 "$out/rtti_gettypes" >"$out/run.log" 2>&1
    grep -qx RTTI_GETTYPES_PASS "$out/run.log"
  done
done

out="$result/checked"
mkdir -p "$out/units"
"$fpc" -n "@$cfg" -Mdelphi -B -O2 -Criot -gl -gw3 \
  "-Fu$source_dir" "-FU$out/units" "-FE$out" "$source" \
  >"$out/compile.log" 2>&1
timeout 30 "$out/rtti_gettypes" >"$out/run.log" 2>&1
grep -qx RTTI_GETTYPES_PASS "$out/run.log"

out="$result/ppu-reuse"
mkdir -p "$out/source" "$out/units"
cp "$source_dir"/*.pas "$source_dir"/*.dpr "$out/source/"
(
  cd "$out/source"
  "$fpc" -n "@$cfg" -Mdelphi -B -O3 -gl -gw3 \
    "-FU$out/units" rtti_catalog_bridge.pas >"$out/unit-compile.log" 2>&1
  before=$(stat -c '%y' "$out/units/rtti_catalog_base.ppu" \
    "$out/units/rtti_catalog_transitive.ppu" \
    "$out/units/rtti_catalog_bridge.ppu")
  sleep 1
  "$fpc" -n "@$cfg" -Mdelphi -O3 -gl -gw3 \
    "-Fu$out/units" "-FU$out/units" "-FE$out" rtti_gettypes.dpr \
    >"$out/program-compile.log" 2>&1
  [[ $(stat -c '%y' "$out/units/rtti_catalog_base.ppu" \
    "$out/units/rtti_catalog_transitive.ppu" \
    "$out/units/rtti_catalog_bridge.ppu") == "$before" ]]
)
timeout 30 "$out/rtti_gettypes" >"$out/run.log" 2>&1
grep -qx RTTI_GETTYPES_PASS "$out/run.log"

{
  sha256sum "$fpc" "$cfg"
  find "$source_dir" -type f \
    \( -name '*.pas' -o -name '*.pp' -o -name '*.inc' -o -name '*.dpr' \) \
    -print0 | sort -z | xargs -0 -r sha256sum
  find "$result" -type f ! -name SHA256SUMS -print0 |
    sort -z | xargs -0 -r sha256sum
} >"$result/SHA256SUMS"
echo RTTI_GETTYPES_GATE_PASS

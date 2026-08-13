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

mkdir -p "$result/old" "$result/new"
cp "$source_dir/rtti_ppu_version_consumer.dpr" "$result/old/consumer.dpr"
cp "$source_dir/rtti_ppu_version_consumer.dpr" "$result/new/consumer.dpr"
"$baseline/bin/fpc" -n "@$baseline/etc/fpc.cfg" -Mdelphi -B -Cn \
  "-FU$result/old" "$source_dir/rtti_ppu_version_unit.pas" \
  >"$result/old/build.log" 2>&1

set +e
"$patched/bin/fpc" -n "@$patched/etc/fpc.cfg" -Mdelphi \
  "-Fu$result/old" "-FU$result/old" "-FE$result/old" \
  "$result/old/consumer.dpr" \
  >"$result/old/consume.log" 2>&1
status=$?
set -e
if [[ $status -eq 0 ]] || ! grep -Eqi 'ppu.*(version|invalid)|invalid.*ppu' "$result/old/consume.log"; then
  echo "patched compiler did not reject the old PPU version" >&2
  exit 1
fi

"$patched/bin/fpc" -n "@$patched/etc/fpc.cfg" -Mdelphi -B -Cn \
  "-FU$result/new" "$source_dir/rtti_ppu_version_unit.pas" \
  >"$result/new/build.log" 2>&1
"$patched/bin/fpc" -n "@$patched/etc/fpc.cfg" -Mdelphi \
  "-Fu$result/new" "-FU$result/new" "-FE$result/new" \
  "$result/new/consumer.dpr" \
  >"$result/new/consume.log" 2>&1
"$result/new/consumer" >"$result/new/run.log"
grep -qx 'TPpuCatalogType' "$result/new/run.log"

{
  sha256sum "$baseline/bin/fpc" "$baseline/etc/fpc.cfg" \
    "$patched/bin/fpc" "$patched/etc/fpc.cfg"
  find "$source_dir" -type f \
    \( -name '*.pas' -o -name '*.pp' -o -name '*.inc' -o -name '*.dpr' \) \
    -print0 | sort -z | xargs -0 -r sha256sum
  find "$result" -type f ! -name SHA256SUMS -print0 |
    sort -z | xargs -0 -r sha256sum
} >"$result/SHA256SUMS"
echo RTTI_PPU_VERSION_GATE_PASS

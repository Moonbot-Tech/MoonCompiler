#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: scripts/run_monitor_gate.sh /path/to/fpc /path/to/fpc.cfg run-id" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC=$(realpath "$1")
CFG=$(realpath "$2")
RUN="$ROOT/results/runs/$3/monitor"
SOURCE="$ROOT/tests/smoke/monitor_finalize.pas"

[[ -x "$FPC" && -f "$CFG" ]] || usage
[[ ! -e "$RUN" ]] || {
  echo "run already exists: $RUN" >&2
  exit 1
}
mkdir -p "$RUN"

for option in O- O2 O3; do
  out="$RUN/${option,,}"
  mkdir -p "$out"
  "$FPC" -n "@$CFG" -Mdelphi -B "-$option" \
    -Fu"$ROOT/tests/smoke" -FU"$out" -FE"$out" "$SOURCE" \
    >"$RUN/${option,,}.compile.log" 2>&1
  timeout 30 "$out/monitor_finalize" >"$RUN/${option,,}.run.log" 2>&1
  grep -qx MONITOR_FINALIZE_OK "$RUN/${option,,}.run.log"
done

sha256sum "$FPC" "$CFG" "$SOURCE" \
  "$ROOT/tests/smoke/monitor_finalize_unit.pas" \
  "$RUN"/*.compile.log "$RUN"/*.run.log >"$RUN/SHA256SUMS"
echo "MONITOR_GATE_OK modes=3"

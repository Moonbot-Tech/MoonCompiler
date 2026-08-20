#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: scripts/run_linux_psabieh_gate.sh /path/to/fpc /path/to/fpc.cfg run-id" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "PSABI EH qualification requires Linux x86-64" >&2
  exit 1
}

TEST_ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$(cd "$TEST_ROOT/../.." && pwd)
TEST_FPC=$(realpath "$1")
TEST_CFG=$(realpath "$2")
TEST_RUN="$TEST_ROOT/results/runs/$3/linux-psabieh"
SOURCE="$REPO_ROOT/RTL-test/semantic/psabieh_product_semantic.dpr"
COMPILE_ERROR_SOURCE="$TEST_ROOT/tests/smoke/psabieh_compile_error.pas"
MM_SOURCE="$REPO_ROOT/runtime/mm/mormot.core.fpcx64mm.pas"

[[ -x "$TEST_FPC" && -f "$TEST_CFG" && -f "$SOURCE" &&
   -f "$COMPILE_ERROR_SOURCE" && -f "$MM_SOURCE" ]] || usage
command -v readelf >/dev/null
command -v nm >/dev/null
command -v objdump >/dev/null
[[ ! -e "$TEST_RUN" ]] || {
  echo "run already exists: $TEST_RUN" >&2
  exit 1
}
mkdir -p "$TEST_RUN"

for option in O- O1 O2 O3; do
  name=${option,,}
  output_dir="$TEST_RUN/$name"
  compile_log="$TEST_RUN/$name.compile.log"
  run_log="$TEST_RUN/$name.run.log"
  mkdir -p "$output_dir"
  "$TEST_FPC" -n "@$TEST_CFG" -Mdelphi -Municodestrings \
    -MduplicateLocals -Madvancedrecords -Marrayoperators \
    -Munderscoreisseparator -Mfunctionreferences -Manonymousfunctions \
    -Minlinevars -Mimplicitgenerics -Mautoderef \
    -Px86_64 -Tlinux -Rintel -dPOSIX -B "-$option" \
    -dMOONBOT_MM_PROFILE_REQUIRED -dFPCMM_BOOSTER -dFPCMM_MOONSHARD \
    "--pinned-unit=mormot.core.fpcx64mm=$MM_SOURCE" \
    --required-first-unit=mormot.core.fpcx64mm,cthreads \
    -FNSystem -UaSystem.SysUtils=SysUtils -UaSystem.Classes=Classes \
    -FU"$output_dir" -FE"$output_dir" \
    "$SOURCE" >"$compile_log" 2>&1
  "$output_dir/psabieh_product_semantic" >"$run_log" 2>&1
  diff -u <(printf 'PSABIEH_PRODUCT_OK\n') "$run_log"
done

compile_error_dir="$TEST_RUN/compiler-error"
compile_error_log="$TEST_RUN/compiler-error.compile.log"
mkdir -p "$compile_error_dir"
set +e
"$TEST_FPC" -n "@$TEST_CFG" -Px86_64 -Tlinux -O2 -B \
  -FU"$compile_error_dir" -FE"$compile_error_dir" \
  "$COMPILE_ERROR_SOURCE" >"$compile_error_log" 2>&1
compile_error_exit=$?
set -e
[[ "$compile_error_exit" -eq 1 ]] || {
  echo "invalid source returned $compile_error_exit instead of 1" >&2
  exit 1
}
grep -Fq 'Identifier not found "MissingIdentifier"' "$compile_error_log"
grep -Fq 'Error: Illegal expression' "$compile_error_log"
grep -Fq 'Fatal: Compilation aborted' "$compile_error_log"
if grep -Eiq 'unhandled exception|EAccessViolation' "$compile_error_log"; then
  echo "compiler exception escaped after a normal diagnostic abort" >&2
  exit 1
fi

binary="$TEST_RUN/o3/psabieh_product_semantic"
object="$TEST_RUN/o3/psabieh_product_semantic.o"
readelf -SW "$binary" >"$TEST_RUN/o3.sections.log"
nm -a "$object" >"$TEST_RUN/o3.symbols.log"
objdump -dr "$object" >"$TEST_RUN/o3.disassembly.log"
grep -q '\.gcc_except_table' "$TEST_RUN/o3.sections.log"
grep -Eiq '_FPC_psabieh_personality_v0' "$TEST_RUN/o3.symbols.log"
if grep -Eiq 'FPC_(PUSH|POP)(EXCEPTADDR|ADDRSTACK)' "$TEST_RUN/o3.disassembly.log"; then
  echo "O3 normal path still contains legacy exception-frame calls" >&2
  exit 1
fi

{
  sha256sum "$TEST_FPC" "$TEST_CFG" "$SOURCE" "$COMPILE_ERROR_SOURCE" "$MM_SOURCE"
  find "$TEST_RUN" -type f ! -name SHA256SUMS -print0 |
    sort -z | xargs -0 -r sha256sum
} >"$TEST_RUN/SHA256SUMS"

echo "LINUX_PSABIEH_GATE_OK modes=4 compiler-error=1 metadata=2 legacy-frame-calls=0"

#!/usr/bin/env bash
# Stand chain for one placement variant on Linux (the twin of
# Stand-F-Chain.ps1): config gate, compiler self-build gate, fixture gate,
# MM layout gate and MM profile matrix, placement-controlled medium
# Pulse (baseline family vs variant family, four placements each), the
# acceptance gate, placement statistics on the Pulse executables, RTL-test
# and Light.  Writes stand/chain-<variant>-<run>-summary.log.
#
#   VARIANT=H BASELINE=C ASSERT=R4,R2E,R2X,R3H,R3L,RT,R1 RUN=P1 EXPECT_FASTER=case,case \
#   ALLOW_SLOWER=case SKIP_SEMANTICS=0 scripts/stand-chain.sh
set -uo pipefail
# the chain judges variants of the code placement draft, which is off by default
# (doc/OPTIMIZER.md, "Code placement"): every compile of the chain runs with it
export MOONCOMPILER_PLACEMENT=1
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT" || exit 1
VARIANT=${VARIANT:-H}
BASELINE=${BASELINE:-C}
ASSERT=${ASSERT:-R4,R2E,R2X,R3H,R3L,RT,R1}
RUN=${RUN:-$(date +%H%M)}
EXPECT_FASTER=${EXPECT_FASTER:-}
ALLOW_SLOWER=${ALLOW_SLOWER:-}
SKIP_SEMANTICS=${SKIP_SEMANTICS:-0}
S=$ROOT/stand
T=$ROOT/qualification/performance/tools
L=$S/chain-$VARIANT-$RUN-summary.log
MM=$ROOT/runtime/mm/mormot.core.fpcx64mm.pas
tc=$S/$VARIANT
ver=$(find "$tc/lib/fpc" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' -printf '%f\n' | head -1)
pp=$tc/lib/fpc/$ver/ppcx64
cfg=$tc/etc/moon-base.cfg
failed_stages=()
if [[ -z "${EXPECT_FASTER//[[:space:]]/}" ]]; then
  echo "CHAIN_${VARIANT}_INCONCLUSIVE reason=no-expected-buyer" >> "$L"
  exit 2
fi
record_stage() {
  local name=$1 code=$2
  echo "$name exit=$code" >> "$L"
  [[ "$code" == 0 ]] || failed_stages+=("$name")
}
finish_chain() {
  if ((${#failed_stages[@]})); then
    local joined
    joined=$(IFS=,; echo "${failed_stages[*]}")
    echo "CHAIN_${VARIANT}_FAILED stages=$joined" >> "$L"
    exit 1
  fi
  echo "CHAIN_${VARIANT}_DONE" >> "$L"
  exit 0
}
echo "chain $VARIANT vs $BASELINE run $RUN start $(date -u +%FT%TZ)" >> "$L"

python3 qualification/build-driver/config_contract_gate.py --config "$cfg" --profile product --compiler "$pp" >> "$L" 2>&1
record_stage "config gate" "$?"
python3 qualification/build-driver/rtl_profile_gate.py --toolchain "$tc" --no-declared >> "$L" 2>&1
record_stage "rtl profile gate" "$?"
python3 qualification/build-driver/rtl_profile_gate.py --toolchain "$S/$BASELINE" --no-declared >> "$L" 2>&1
record_stage "baseline rtl profile gate" "$?"
python3 qualification/build-driver/compiler_selfbuild_gate.py --compiler "$pp" --config "$S/base/etc/moon-base.cfg" --product-config "$cfg" --msg2inc "$S/base/bin/msg2inc" > "$S/gate-selfbuild-$VARIANT-$RUN.md" 2>&1
record_stage "compiler selfbuild gate" "$?"
grep -E '^ - |^ \* |GATE' "$S/gate-selfbuild-$VARIANT-$RUN.md" >> "$L"

out=$ROOT/probe/fixture-$VARIANT-$RUN; mkdir -p "$out"
"$pp" -n "@$cfg" -Mdelphi -O3 -B -gw3 -vd "-FE$out" "-FU$out" -uMOONCOMPILER_VANILLA_RUNTIME -dFPCMM_BOOSTER -dFPCMM_MOONSHARD -dNOPATCHRTL -dMOONBOT_MM_PROFILE_REQUIRED "--pinned-unit=mormot.core.fpcx64mm=$MM" --required-first-unit=mormot.core.fpcx64mm,cthreads "-Fu$ROOT/runtime/mm" "$T/placement_fixture.dpr" > "$out/build.log" 2>&1
record_stage "fixture build" "$?"
grep 'Code placement:' "$out/build.log" | tail -1 >> "$L"
"$out/placement_fixture" >> "$L"
record_stage "fixture run" "$?"
python3 "$T/check_placement_rules.py" "$out/placement_fixture" --match 'P.PLACEMENT_FIXTURE' --assert "$ASSERT" --list-violations > "$S/gate-fixture-$VARIANT-$RUN.md" 2>&1
record_stage "fixture gate" "$?"
cat "$S/gate-fixture-$VARIANT-$RUN.md" >> "$L"
python3 qualification/memory-manager/mm_layout_gate.py --compiler "$pp" --config "$cfg" > "$S/gate-mm-layout-$VARIANT-$RUN.md" 2>&1
record_stage "mm layout gate" "$?"
cat "$S/gate-mm-layout-$VARIANT-$RUN.md" >> "$L"
python3 qualification/build-driver/rtl_asm_layout_gate.py --compiler "$pp" --config "$cfg" > "$S/gate-rtl-asm-layout-$VARIANT-$RUN.md" 2>&1
record_stage "rtl asm layout gate" "$?"
cat "$S/gate-rtl-asm-layout-$VARIANT-$RUN.md" >> "$L"
python3 qualification/memory-manager/mm_profile_matrix.py --compiler "$pp" --config "$cfg" > "$S/gate-mm-matrix-$VARIANT-$RUN.md" 2>&1
record_stage "mm profile matrix" "$?"
cat "$S/gate-mm-matrix-$VARIANT-$RUN.md" >> "$L"

sysargs=()
for fam in "$BASELINE" "$VARIANT"; do
  sysargs+=(--moon-system "$fam=$S/$fam")
  for k in 1 2 3; do
    sysargs+=(--moon-system "$fam$k=$S/$fam" --moon-system-option "$fam$k=-dPULSE_FILLER_$k")
  done
done
systems="$BASELINE,${BASELINE}1,${BASELINE}2,${BASELINE}3,$VARIANT,${VARIANT}1,${VARIANT}2,${VARIANT}3"
tag=stand-linux-filler-$VARIANT-$RUN
python3 "$T/pulse.py" run --mode medium --programs hot-rtl,repairs --systems "$systems" "${sysargs[@]}" --moon-extra-option=-gw3 --tag "$tag" > "$S/pulse-linux-filler-$VARIANT-$RUN.log" 2>&1
record_stage "filler pulse $BASELINE vs $VARIANT" "$?"
grep -c 'UnstablePairsError' "$S/pulse-linux-filler-$VARIANT-$RUN.log" | sed 's/^/unstable pairs errors: /' >> "$L"
python3 "$T/filler_summary.py" "qualification/performance/results/pulse/$tag" --left "$BASELINE" --right "$VARIANT" > "$S/filler-linux-${BASELINE}vs$VARIANT-$RUN.md" 2>&1
record_stage "filler summary" "$?"
ab=(--baseline "$BASELINE" --candidate "$VARIANT")
[[ -n "$EXPECT_FASTER" ]] && ab+=(--expect-faster "$EXPECT_FASTER")
[[ -n "$ALLOW_SLOWER" ]] && ab+=(--allow-slower "$ALLOW_SLOWER")
python3 "$T/stand_ab_gate.py" "qualification/performance/results/pulse/$tag" "${ab[@]}" >> "$L" 2>&1
record_stage "ab gate" "$?"

for fam in "$BASELINE" "$VARIANT"; do
  exe=$ROOT/qualification/performance/hot-rtl/build-$fam/pulse_hot-rtl
  echo "placement stats $fam program:" >> "$L"
  python3 "$T/check_placement_rules.py" "$exe" --match 'P.PULSE_HOT_RTL' 2>&1 | head -10 >> "$L"
  record_stage "placement stats $fam program" "${PIPESTATUS[0]}"
  echo "placement stats $fam rtl units:" >> "$L"
  python3 "$T/check_placement_rules.py" "$exe" --match '^(SYSUTILS|CLASSES|STRUTILS|MATH|GENERICS)' --exclude asm 2>&1 | head -10 >> "$L"
  record_stage "placement stats $fam rtl" "${PIPESTATUS[0]}"
done

# rule 4 and the target rule hold in the whole Pulse program of the variant, compiled and
# hand-written code alike: no branch on a 32-byte boundary, no jump target of a loop in the last
# 12 bytes of a line where the block in front could carry the pad (hand-written routines nobody
# laid out would be listed in unlaid_asm_routines.txt - empty).  RT carries a ceiling of two here:
# one code shape of the Linux RTL, TStringHelper.Split for UnicodeString and WideString, keeps a
# target on byte 59 because its pad reached the assembler's change limit in that state
# (doc/BACKLOG.md).  A third violation anywhere in the binary fails the gate.
python3 "$T/check_placement_rules.py" "$ROOT/qualification/performance/hot-rtl/build-$VARIANT/pulse_hot-rtl" \
  --match '^(P.PULSE_HOT_RTL|SYSTEM|SYSUTILS|CLASSES|STRUTILS|MATH|GENERICS|RTTI|FGL|TYPINFO|FPC_|fpc_)' \
  --exclude-file "$T/unlaid_asm_routines.txt" \
  --assert R4,RT=2 \
  --expect-violation 'RT=TUNICODESTRINGHELPER.*SPLIT' \
  --expect-violation 'RT=TWIDESTRINGHELPER.*SPLIT' \
  --list-violations > "$S/gate-compiled-r4-$VARIANT-$RUN.md" 2>&1
record_stage "compiled code rules gate" "$?"
grep -E '^R4 |^  R4:|^RT |^  RT:|PLACEMENT_GATE' "$S/gate-compiled-r4-$VARIANT-$RUN.md" >> "$L"

if [[ "$SKIP_SEMANTICS" == 1 ]]; then
  echo "CHAIN_${VARIANT}_INCONCLUSIVE reason=semantics-skipped" >> "$L"
  exit 2
fi
export MOONBOT_TOOLCHAIN=$S/$VARIANT
python3 RTL-test/run.py > "$S/rtltest-$VARIANT-$RUN.log" 2>&1
record_stage "RTL-test $VARIANT" "$?"
python3 qualification/suite/scripts/run_devil_targeted.py light --run-id "stand-$VARIANT-light-$RUN" > "$S/light-$VARIANT-$RUN.log" 2>&1
record_stage "light $VARIANT" "$?"
finish_chain

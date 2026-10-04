#!/usr/bin/env bash
set -euo pipefail

mormot=${1:?product mORMot source root is required}
mm=${2:?bundled memory-manager source is required}
out=${3:?output root is required}
fpc=${4:?current compiler path is required}
cfg=${5:?current compiler test config path is required}
mormot=$(realpath "$mormot")
mm=$(realpath "$mm")
out=$(realpath -m "$out")
fpc=$(realpath "$fpc")
cfg=$(realpath "$cfg")
static=$mormot/static/x86_64-linux
tests_root=$(realpath "$(dirname "$0")/../..")
static_manifest=$tests_root/fixtures/mormot-static/x86_64-linux.SHA256SUMS
test_source=$tests_root/fixtures/mormot-2.3.8832/test
test_patch=$tests_root/patches/mormot-current-numeric-contract.diff

if [[ -e "$out" ]]; then
  echo "mORMot gate output already exists: $out" >&2
  exit 2
fi

mkdir -p "$out/lib" "$out/logs" "$out/source"
cp -a "$test_source" "$out/source/test"
(
  cd "$out/source"
  # Outside any repository git apply patches relative to this directory, in a
  # clone and in an archive alike.  Inside a checkout that encloses $out it
  # would read the patch paths from that checkout's root and skip them all
  # with exit 0, so discovery stops at $out.
  unset GIT_DIR GIT_WORK_TREE
  export GIT_CEILING_DIRECTORIES=$out
  git apply --check --ignore-whitespace "$test_patch"
  git apply --ignore-whitespace "$test_patch"
  git apply --reverse --check --ignore-whitespace "$test_patch"
)
ln -s "$mormot" "$out/source/src"
ln -s "$mormot/static" "$out/source/static"
(cd "$static" && sha256sum -c "$static_manifest")
sha256sum "$mm" "$test_source/mormot2tests.dpr" "$test_patch" "$static_manifest" \
  >"$out/INPUTS.sha256"

units=(app core crypt db lib net orm rest soa script misc tools/mget tools/ecc)
unitargs=()
for unit in "${units[@]}"; do
  unitargs+=("-Fu$mormot/$unit")
done

# Static-library directives in mORMot's lib units are relative to src/lib.
# Own the working directory here so the gate is independent of its caller.
cd "$mormot/lib"

"$fpc" -n "@$cfg" -MDelphi -Sci -Ci -O3 -CX -XX -B -Se1 \
  -dFPC_NO_DEFAULT_MEMORYMANAGER -dFPC_X64MM \
  -dFPCMM_SERVER -dMOONBOT_MM_PROFILE_REQUIRED \
  -dFPCMM_BOOSTER -dFPCMM_MOONSHARD \
  -dFPCMM_REPORTMEMORYLEAKS \
  "--pinned-unit=mormot.core.fpcx64mm=$mm" \
  --required-first-unit=mormot.core.fpcx64mm,cthreads \
  -Fi"$mormot" -Fi"$mormot/core" \
  "${unitargs[@]}" -Fl"$mormot/static/x86_64-linux" \
  -FU"$out/lib" -FE"$out" -omormot2tests \
  "$out/source/test/mormot2tests.dpr" >"$out/build.log" 2>&1

# mORMot derives its Unix-domain socket beside the executable. Keep that path
# below sockaddr_un.sun_path even when the preserved evidence path is long.
run_dir=$(mktemp -d /tmp/moonbot-mormot-mm.XXXXXX)
trap 'rm -rf "$run_dir"' EXIT
cp "$out/mormot2tests" "$run_dir/"

classes=(
  TTestCoreBase
  TTestCoreProcess
  TTestCoreCollections
  TTestCoreCrypto
  TTestCoreEcc
  TTestCoreCompression
  TNetworkProtocols
  TTestOrmCore
  TTestSqliteFile
  TTestSqliteFileWAL
  TTestSqliteFileMemoryMap
  TTestSqliteMemory
  TTestExternalDatabase
  TTestClientServerAccess
  TTestMultiThreadProcess
  TTestCoreScript
  TTestServiceOrientedArchitecture
  TTestBidirectionalRemoteConnection
)

total=0
environment_failed=0
for class in "${classes[@]}"; do
  log=$out/logs/$class.log
  set +e
  timeout 900s "$run_dir/mormot2tests" --test "$class" >"$log" 2>&1
  status=$?
  set -e
  expected_failed=0
  if ((status != 0)); then
    # The old suite pins external DNS answers. Accept only this exact
    # environment-only failure, never another NetworkProtocols failure.
    # Group setup exceptions print "! E..." without a failed assertion.
    if [[ $class == TNetworkProtocols && $status == 1 ]] &&
       grep -Eq '!  - DNS and LDAP: 3 / [0-9,]+ FAILED' "$log" &&
       [[ $(grep -Ec '!  - .*: [0-9]+ / [0-9,]+ FAILED' "$log") == 1 ]] &&
       ! grep '^!' "$log" | grep -Ev \
         '^!  - DNS and LDAP: 3 / [0-9,]+ FAILED|^! Some tests FAILED: please correct the code\.$'; then
      expected_failed=3
      environment_failed=$((environment_failed + expected_failed))
    else
      echo "unexpected mORMot status $status for $class" >&2
      exit 1
    fi
  fi
  line=$(grep "Total failed: $expected_failed /" "$log" | tail -1)
  assertions=$(sed -E 's/.*Total failed: [0-9]+ \/ ([0-9,]+).*/\1/' <<<"$line" | tr -d ',')
  [[ $assertions =~ ^[0-9]+$ ]]
  total=$((total + assertions))
  if [[ $(grep -c '^FPCMM_REPORTMEMORYLEAKS_DONE$' "$log") != 1 ]]; then
    echo "memory leak census did not complete for $class" >&2
    exit 1
  fi
  if grep -Eq 'small block leak|medium block leak|large block leak' "$log"; then
    echo "memory leak reported by $class" >&2
    exit 1
  fi
done

printf 'classes=%d\nassertions=%d\nenvironment_failed=%d\nfailed=0\n' \
  "${#classes[@]}" "$total" "$environment_failed" >"$out/SUMMARY.txt"
cat "$out/SUMMARY.txt"

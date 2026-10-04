#!/usr/bin/env bash
# RTL profile stand, Linux x86-64: one compiler, four installations of the
# product Unicode RTL and packages that differ only in the RTL flags.
#
#   A  -O2                 exact current product profile
#   B  -O2 -OoCODEALIGN    placement only
#   C  -O3                 full O3 including CODEALIGN
#   D  -O3 -OoNOCODEALIGN  O3 without placement
#   H  -O3                 O3 with the placement rules 1-4 of the current compiler
#   I, J, K                same, one stand per placement rule change under test
#
# Mirrors build_compiler() from ./build; nothing here touches toolchain.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STAND="$ROOT/stand"
BASE="$STAND/base"
MM_SOURCE="$ROOT/runtime/mm/mormot.core.fpcx64mm.pas"
UNICODE_COMMON='-n -gw3 -dMOONCOMPILER_VANILLA_RUNTIME -dUNICODERTL -dENABLE_DELPHI_RTTI -dMOONCOMPILER_DELPHI_CALLBACK_TYPES'
declare -A VARIANT_OPT=(
  [A]='-O2'
  [B]='-O2 -OoCODEALIGN'
  [C]='-O3'
  [D]='-O3 -OoNOCODEALIGN'
  [E]='-O3 -OaLOOP=64 -OaPROC=64'
  [G]='-O3 -ao-mbranches-within-32B-boundaries'
  [H]='-O3'
  [I]='-O3'
  [J]='-O3'
  [K]='-O3'
  [L]='-O3'
  [M]='-O3'
  [N]='-O3'
  [O]='-O3'
  [P]='-O3'
  [Q]='-O3'
  [R]='-O3'
  [S]='-O3'
  [T]='-O3'
  [U]='-O3'
  [V]='-O3'
  [W]='-O3'
)
VARIANTS=(${VARIANTS:-A B C D})
SKIP_BASE=${SKIP_BASE:-0}

bootstrap=${MOONBOT_BOOTSTRAP_FPC:-$(command -v fpc || true)}
[[ -n "$bootstrap" && -x "$bootstrap" && "$($bootstrap -iV)" == 3.2.2 ]] || {
  echo "FPC 3.2.2 bootstrap is required; set MOONBOT_BOOTSTRAP_FPC" >&2
  exit 1
}
compiler_options='-O2 -dMOONCOMPILER_PRODUCT_RUNTIME -dMOONCOMPILER_VANILLA_RUNTIME'
mkdir -p "$STAND"

if [[ "$SKIP_BASE" != 1 ]]; then
  echo "=== base: compiler + FPC-ABI units -> $BASE"
  rm -rf "$BASE"
  make -C "$ROOT" clean FPC="$bootstrap"
  make -C "$ROOT" -j1 all FPC="$bootstrap" OPT="$compiler_options"
  make -C "$ROOT" install FPC="$bootstrap" OPT="$compiler_options" INSTALL_PREFIX="$BASE"
fi

version_dir=$(find "$BASE/lib/fpc" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' -printf '%f\n')
[[ -n "$version_dir" && "$version_dir" != *$'\n'* ]] || { echo "cannot identify compiler version" >&2; exit 1; }
target_fpcmake="$ROOT/utils/fpcm/bin/x86_64-linux/fpcmake"
[[ -x "$target_fpcmake" ]] || { echo "fpcmake missing" >&2; exit 1; }
[[ -x "$BASE/bin/fpcres" ]] || { echo "fpcres missing" >&2; exit 1; }

# base gets the vanilla configuration of its own units (no product lines):
# the compiler self-build gate builds the compiler sources with it
if [[ "$SKIP_BASE" != 1 || ! -f "$BASE/etc/moon-base.cfg" ]]; then
  mkdir -p "$BASE/etc"
  "$BASE/bin/fpcmkcfg" -t "$ROOT/scripts/fpc.cfg.linux.template" -d "gcclibdir=$(dirname "$(gcc -print-libgcc-file-name)")" -d "basepath=$BASE/lib/fpc/$version_dir" -o "$BASE/etc/moon-base.cfg"
fi

for variant in "${VARIANTS[@]}"; do
  opt="${VARIANT_OPT[$variant]} $UNICODE_COMMON"
  target="$STAND/$variant"
  echo "=== variant $variant : OPT=$opt -> $target"
  rm -rf "$target"
  cp -a "$BASE" "$target"
  compiler="$target/lib/fpc/$version_dir/ppcx64"
  [[ -x "$compiler" ]] || { echo "compiler missing in $target" >&2; exit 1; }

  make -C "$ROOT/rtl" clean FPC="$compiler"
  make -C "$ROOT/rtl" -j1 all FPC="$compiler" OPT="$opt"
  make -C "$ROOT/rtl" install FPC="$compiler" FPCMAKE="$target_fpcmake" OPT="$opt" INSTALL_PREFIX="$target"
  make -C "$ROOT/packages" clean FPC="$compiler" FPMAKEOPT=--NoIDE=1
  make -C "$ROOT/packages" -j1 all FPC="$compiler" OPT="$opt" FPMAKEOPT=--NoIDE=1
  make -C "$ROOT/packages" install FPC="$compiler" FPCMAKE="$target_fpcmake" OPT="$opt" FPMAKEOPT=--NoIDE=1 INSTALL_PREFIX="$target"

  ln -sf "../lib/fpc/$version_dir/ppcx64" "$target/bin/ppcx64"
  mkdir -p "$target/etc"
  "$target/bin/fpcmkcfg" -t "$ROOT/scripts/fpc.cfg.linux.template" -d "gcclibdir=$(dirname "$(gcc -print-libgcc-file-name)")" -d "basepath=$target/lib/fpc/$version_dir" -o "$target/etc/moon-base.cfg"
  printf '%s\n' \
    '# MoonCompiler project ABI: Delphi String and Char are Unicode.' \
    '-dMOONCOMPILER_UNICODE_DEFAULT' \
    '# Product programs receive the bundled runtime prefix automatically.' \
    '-dMOONBOT_MM_PROFILE_REQUIRED' \
    '-dFPCMM_BOOSTER' \
    '-dFPCMM_MOONSHARD' \
    '-dNOPATCHRTL' \
    "--pinned-unit=mormot.core.fpcx64mm=$MM_SOURCE" \
    >> "$target/etc/moon-base.cfg"
  {
    echo "variant=$variant"
    echo "rtl_packages_opt=OPT=$opt"
    if [[ "${MOONCOMPILER_PLACEMENT:-}" == 1 && -z "${MOONCOMPILER_NO_PLACEMENT:-}" ]]; then
      echo 'placement_draft=1'
    else
      echo 'placement_draft=0'
    fi
    echo "compiler_sha256=$(sha256sum "$compiler" | cut -d' ' -f1)"
    echo "sysutils_ppu_sha256=$(sha256sum "$target/lib/fpc/$version_dir/units/x86_64-linux/rtl/sysutils.ppu" | cut -d' ' -f1)"
    echo "sysutils_o_sha256=$(sha256sum "$target/lib/fpc/$version_dir/units/x86_64-linux/rtl/sysutils.o" | cut -d' ' -f1)"
    echo "generics_hashes_o_sha256=$(sha256sum "$target/lib/fpc/$version_dir/units/x86_64-linux/rtl-generics/generics.hashes.o" | cut -d' ' -f1)"
    echo "rtl_asm_x86_64_sha256=$(sha256sum "$ROOT/rtl/x86_64/x86_64.inc" | cut -d' ' -f1)"
    echo "rtl_asm_strings_sha256=$(sha256sum "$ROOT/rtl/x86_64/strings.inc" | cut -d' ' -f1)"
    echo "rtl_asm_sets_sha256=$(sha256sum "$ROOT/rtl/x86_64/set.inc" | cut -d' ' -f1)"
    echo "rtl_asm_threadvar_sha256=$(sha256sum "$ROOT/rtl/win/systhrd.inc" | cut -d' ' -f1)"
    echo "rtl_asm_math_sha256=$(sha256sum "$ROOT/rtl/objpas/math.pp" | cut -d' ' -f1)"
    echo "rtl_asm_sysstrings_sha256=$(sha256sum "$ROOT/rtl/objpas/sysutils/sysstr.inc" | cut -d' ' -f1)"
    echo "rtl_asm_hashes_sha256=$(sha256sum "$ROOT/packages/rtl-generics/src/generics.hashes.pas" | cut -d' ' -f1)"
    echo "rtl_asm_astrings_sha256=$(sha256sum "$ROOT/rtl/inc/astrings.inc" | cut -d' ' -f1)"
    echo "rtl_asm_ustrings_sha256=$(sha256sum "$ROOT/rtl/inc/ustrings.inc" | cut -d' ' -f1)"
    echo "built_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } | tee "$target/profile.txt"
done
echo STAND_BUILD_OK

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
cc -std=c11 -I/usr/include/freetype2 "$source_root/freetype_abi_oracle.c" -o "$run/freetype-abi"
"$run/freetype-abi" >"$run/freetype-abi.log"
grep -qx FREETYPE_C_ABI_OK "$run/freetype-abi.log"
cases=0
executions=0

for case_name in rtl_api_release231_contracts rtl_api_freetype_contracts rtl_api_portability_contracts rtl_api_regex_contracts rtl_api_posix_contracts rtl_api_compiler_identity rtl_api_threading_contracts rtl_api_url_async_contracts rtl_api_json_builder_contracts rtl_api_release21_contracts rtl_api_timezone_provider_contracts rtl_api_surface rtl_api_stringbuilder_contracts \
    rtl_api_variant_dictionary_contracts rtl_api_bcd_value_contracts rtl_api_encoding_contracts rtl_api_utf8_decode_contracts rtl_api_datetime_unix_contracts rtl_api_sorted_find_contracts \
    rtl_api_queue_contracts rtl_api_dictionary_capacity_contracts rtl_api_comparer_factory_contracts \
    rtl_api_text_operations_contracts rtl_api_dictionary_scan_contracts rtl_api_unicode_copy_contracts rtl_api_array_copy \
    rtl_api_dynarray_managed_contracts rtl_api_fphttp_nodelay rtl_api_fphttp_overload_response; do
  if [[ "$case_name" == rtl_api_release231_contracts ]]; then
    expected=RTL_API_RELEASE231_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_freetype_contracts ]]; then
    expected=RTL_API_FREETYPE_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_portability_contracts ]]; then
    expected=RTL_API_PORTABILITY_PASS
  elif [[ "$case_name" == rtl_api_regex_contracts ]]; then
    expected=RTL_API_REGEX_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_posix_contracts ]]; then
    expected=RTL_API_POSIX_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_compiler_identity ]]; then
    expected=RTL_API_COMPILER_IDENTITY_OK
  elif [[ "$case_name" == rtl_api_threading_contracts ]]; then
    expected=RTL_API_THREADING_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_url_async_contracts ]]; then
    expected=RTL_API_URL_ASYNC_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_json_builder_contracts ]]; then
    expected=RTL_API_JSON_BUILDER_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_release21_contracts ]]; then
    expected=RTL_API_RELEASE21_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_timezone_provider_contracts ]]; then
    expected=RTL_API_TIMEZONE_PROVIDER_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_surface ]]; then
    expected=RTL_API_SURFACE_OK
  elif [[ "$case_name" == rtl_api_stringbuilder_contracts ]]; then
    expected=RTL_API_STRINGBUILDER_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_variant_dictionary_contracts ]]; then
    expected=RTL_API_VARIANT_DICTIONARY_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_bcd_value_contracts ]]; then
    expected=RTL_API_BCD_VALUE_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_sorted_find_contracts ]]; then
    expected=RTL_API_SORTED_FIND_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_encoding_contracts ]]; then
    expected=RTL_API_ENCODING_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_utf8_decode_contracts ]]; then
    expected=RTL_API_UTF8_DECODE_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_datetime_unix_contracts ]]; then
    expected=RTL_API_DATETIME_UNIX_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_queue_contracts ]]; then
    expected=RTL_API_QUEUE_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_dictionary_capacity_contracts ]]; then
    expected=RTL_API_DICTIONARY_CAPACITY_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_comparer_factory_contracts ]]; then
    expected=RTL_API_COMPARER_FACTORY_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_text_operations_contracts ]]; then
    expected=RTL_API_TEXT_OPERATIONS_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_dictionary_scan_contracts ]]; then
    expected=RTL_API_DICTIONARY_SCAN_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_dynarray_managed_contracts ]]; then
    expected=RTL_API_DYNARRAY_MANAGED_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_unicode_copy_contracts ]]; then
    expected=RTL_API_UNICODE_COPY_CONTRACTS_OK
  elif [[ "$case_name" == rtl_api_array_copy ]]; then
    expected=RTL_API_ARRAY_COPY_OK
  elif [[ "$case_name" == rtl_api_fphttp_nodelay ]]; then
    expected=RTL_API_FPHTTP_NODELAY_OK
  else
    expected=RTL_API_FPHTTP_OVERLOAD_RESPONSE_OK
  fi
  cases=$((cases + 1))
  profiles=(debug release)
  if [[ "$case_name" == rtl_api_dynarray_managed_contracts || "$case_name" == rtl_api_regex_contracts ]]; then
    profiles+=(diagnostic-release)
  fi
  for profile in "${profiles[@]}"; do
    executions=$((executions + 1))
    profile_dir="$run/$case_name/$profile"
    mkdir -p "$profile_dir"
    project="$profile_dir/$case_name.dpr"
    cp "$source_root/$case_name.dpr" "$project"
    build_options=(-B "-Fi$source_root" "-FU$profile_dir" "-FE$profile_dir")
    if [[ "$profile" != debug ]]; then
      build_options+=(-dRELEASE)
    fi
    if [[ "$profile" == diagnostic-release ]]; then
      build_options+=(-dFPCX64MM_DIAGNOSTIC)
    fi
    if [[ "$case_name" == rtl_api_freetype_contracts ]]; then
      for kind in good incomplete tail; do
        fixture_options=("${build_options[@]}" "-omoon-freetype-$kind.so")
        if [[ "$kind" == incomplete ]]; then
          fixture_options+=(-dMISSING_FREETYPE_EXPORT)
        fi
        if [[ "$kind" == tail ]]; then
          fixture_options+=(-dMISSING_FREETYPE_TAIL)
        fi
        "$compiler_root/toolchain/bin/fpc" "${fixture_options[@]}" "$source_root/moon_freetype_fixture.dpr" \
          >"$profile_dir/$kind-compile.log" 2>&1
      done
    fi
    if ! "$compiler_root/toolchain/bin/fpc" "${build_options[@]}" "$project" \
        >"$profile_dir/compile.log" 2>&1; then
      echo "$case_name/$profile did not compile" >&2
      exit 1
    fi
    timeout 30 "$profile_dir/$case_name" \
      >"$profile_dir/run.log" 2>&1
    grep -qx "$expected" "$profile_dir/run.log"
    if [[ "$profile" == diagnostic-release ]]; then
      grep -q '^FPCX64MM_DIAGNOSTIC live-blocks=0 ' "$profile_dir/run.log"
    fi
  done
done

{
  sha256sum "$source_root/rtl_api_release231_contracts.dpr" \
    "$source_root/rtl_api_freetype_contracts.dpr" "$source_root/moon_freetype_fixture.dpr" \
    "$source_root/freetype_abi_oracle.c"
  sha256sum "$source_root/rtl_api_portability_contracts.dpr"
  sha256sum "$source_root/rtl_api_regex_contracts.dpr"
  sha256sum "$source_root/rtl_api_posix_contracts.dpr"
  sha256sum "$source_root/rtl_api_compiler_identity.dpr"
  sha256sum "$source_root/rtl_api_url_async_contracts.dpr" "$source_root/rtl_api_surface.dpr" \
    "$source_root/rtl_api_threading_contracts.dpr" \
    "$source_root/rtl_api_json_builder_contracts.dpr" \
    "$source_root/rtl_api_release21_contracts.dpr" \
    "$source_root/rtl_api_timezone_provider_contracts.dpr" \
    "$source_root/rtl_api_stringbuilder_contracts.dpr" \
    "$source_root/rtl_api_variant_dictionary_contracts.dpr" \
    "$source_root/rtl_api_bcd_value_contracts.dpr" \
    "$source_root/rtl_api_encoding_contracts.dpr" \
    "$source_root/rtl_api_utf8_decode_contracts.dpr" \
    "$source_root/rtl_api_datetime_unix_contracts.dpr" \
    "$source_root/rtl_api_sorted_find_contracts.dpr" \
    "$source_root/rtl_api_queue_contracts.dpr" \
    "$source_root/rtl_api_dictionary_capacity_contracts.dpr" \
    "$source_root/rtl_api_comparer_factory_contracts.dpr" \
    "$source_root/rtl_api_text_operations_contracts.dpr" \
    "$source_root/rtl_api_text_guard.inc" \
    "$source_root/rtl_api_dictionary_scan_contracts.dpr" \
    "$source_root/rtl_api_dynarray_managed_contracts.dpr" \
    "$source_root/rtl_api_unicode_copy_contracts.dpr" \
    "$source_root/rtl_api_array_copy.dpr" \
    "$source_root/rtl_api_fphttp_nodelay.dpr" \
    "$source_root/rtl_api_fphttp_overload_response.dpr" \
    "$compiler_root/runtime/mm/mormot.core.fpcx64mm.pas" \
    "$compiler_root/toolchain/bin/fpc" \
    "$compiler_root/toolchain/etc/fpc.cfg" \
    "$compiler_root/toolchain/etc/moon-base.cfg"
  find "$run" -type f ! -name SHA256SUMS -print0 |
    sort -z | xargs -0 -r sha256sum
} >"$run/SHA256SUMS"

echo "RTL_API_SURFACE_GATE_OK cases=$cases executions=$executions"

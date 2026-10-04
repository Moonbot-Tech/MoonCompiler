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

for case_name in rtl_api_surface rtl_api_stringbuilder_contracts \
    rtl_api_variant_dictionary_contracts rtl_api_bcd_value_contracts rtl_api_encoding_contracts rtl_api_utf8_decode_contracts rtl_api_datetime_unix_contracts rtl_api_sorted_find_contracts \
    rtl_api_queue_contracts rtl_api_dictionary_capacity_contracts rtl_api_comparer_factory_contracts \
    rtl_api_text_operations_contracts rtl_api_dictionary_scan_contracts rtl_api_unicode_copy_contracts rtl_api_array_copy \
    rtl_api_dynarray_managed_contracts rtl_api_fphttp_nodelay rtl_api_fphttp_overload_response; do
  if [[ "$case_name" == rtl_api_surface ]]; then
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
  profiles=(debug release)
  if [[ "$case_name" == rtl_api_dynarray_managed_contracts ]]; then
    profiles+=(diagnostic-release)
  fi
  for profile in "${profiles[@]}"; do
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
  sha256sum "$source_root/rtl_api_surface.dpr" \
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

echo "RTL_API_SURFACE_GATE_OK cases=18 executions=37"

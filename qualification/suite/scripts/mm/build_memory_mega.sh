#!/usr/bin/env bash
set -u

source_file=${1:?memory mega source is required}
mm_dir=${2:?memory-manager source directory is required}
output_name=${3:?output name is required}
log_file=${4:?build log is required}
compiler=${5:?current compiler path is required}
config=${6:?current compiler test config path is required}
units_dir="$mm_dir/units-memory-mega"

mkdir -p "$units_dir"
"$compiler" -n "@$config" -B -O3 -dFPCMM_BOOSTER -dFPCMM_MOONSHARD \
  -Fu"$mm_dir" -FU"$units_dir" -FE"$mm_dir" -o"$output_name" \
  "$source_file" >"$log_file" 2>&1

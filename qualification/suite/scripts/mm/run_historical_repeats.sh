#!/usr/bin/env bash
set -u

binary=${1:?binary path is required}
output_dir=${2:?output directory is required}
total=${3:-1000}
parallel=${4:-12}
mode=${5:-full}
seed=${6:-5579800982869324342}
timeout_seconds=${7:-180}

mkdir -p "$output_dir/logs"
sha256sum "$binary" >"$output_dir/BINARY.sha256"
printf 'binary=%s\nmode=%s\nseed=%s\ntotal=%s\nparallel=%s\ntimeout_seconds=%s\nstarted_utc=%s\n' \
  "$binary" "$mode" "$seed" "$total" "$parallel" "$timeout_seconds" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$output_dir/RUN.txt"

run_one() {
  local index=$1
  local prefix
  local rc
  prefix=$(printf '%s/logs/run-%04d' "$output_dir" "$index")
  /usr/bin/time -v -o "$prefix.time.tmp" \
    timeout "${timeout_seconds}s" "$binary" "$mode" "$seed" \
    >"$prefix.log.tmp" 2>&1
  rc=$?
  printf '%s\n' "$rc" >"$prefix.status.tmp"
  mv "$prefix.time.tmp" "$prefix.time"
  mv "$prefix.log.tmp" "$prefix.log"
  mv "$prefix.status.tmp" "$prefix.status"
  if (( rc != 0 )); then
    printf '%s %s\n' "$index" "$rc" >>"$output_dir/FAILURES"
  fi
}

for ((index = 1; index <= total; index++)); do
  if [[ -s "$output_dir/FAILURES" ]]; then
    break
  fi
  while (( $(jobs -pr | wc -l) >= parallel )); do
    wait -n || true
    if [[ -s "$output_dir/FAILURES" ]]; then
      break 2
    fi
  done
  run_one "$index" &
done
wait || true

passed=$(grep -l '^0$' "$output_dir"/logs/*.status 2>/dev/null | wc -l)
failed=$(find "$output_dir/logs" -maxdepth 1 -name '*.status' -type f -print0 |
  xargs -0 -r grep -L '^0$' | wc -l)
printf 'passed=%s\nfailed=%s\nfinished_utc=%s\n' \
  "$passed" "$failed" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee "$output_dir/SUMMARY.txt"

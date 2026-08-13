#!/usr/bin/env bash
set -u

workdir=$1
binary=$2
mode=$3
name=$4
seed=${5-}

cd "$workdir"
rm -f "$name.txt" "$name.cpu" "$name.status"
if [[ -n "$seed" ]]; then
  "./$binary" "$mode" "$seed" >"$name.txt" 2>&1 &
else
  "./$binary" "$mode" >"$name.txt" 2>&1 &
fi
test_pid=$!
pidstat -u -p "$test_pid" 1 >"$name.cpu" 2>&1 &
monitor_pid=$!
wait "$test_pid"
status=$?
kill "$monitor_pid" 2>/dev/null || true
wait "$monitor_pid" 2>/dev/null || true
printf '%s\n' "$status" >"$name.status"
exit "$status"

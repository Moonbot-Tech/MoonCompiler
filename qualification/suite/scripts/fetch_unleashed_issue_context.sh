#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$LAB_ROOT/cache/issues/unleashed/context"
USER_AGENT='fpc-unleashed-qualification-lab/1.0'
mkdir -p "$OUT"

for number in 10 16 17 18 20; do
  for resource in comments timeline; do
    target="$OUT/issue-${number}-${resource}.json"
    curl --fail --silent --show-error --location \
      --retry 5 --retry-all-errors --connect-timeout 20 --max-time 120 \
      --user-agent "$USER_AGENT" \
      --header 'Accept: application/vnd.github+json' \
      --output "$target.tmp" \
      "https://api.github.com/repos/UnleashedPascal/compiler/issues/$number/$resource?per_page=100"
    jq -e 'type == "array"' "$target.tmp" >/dev/null
    mv "$target.tmp" "$target"
    sleep 1
  done
done

sha256sum "$OUT"/*.json > "$OUT/SHA256SUMS"

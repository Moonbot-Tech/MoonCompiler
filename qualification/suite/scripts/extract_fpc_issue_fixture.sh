#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 ISSUE_ID FENCE(unlabelled|pascal) OUTPUT" >&2
  exit 2
fi

LAB_ROOT=$(cd "$(dirname "$0")/.." && pwd)
ISSUE_ID=$1
FENCE=$2
OUTPUT=$3

case "$OUTPUT" in
  "$LAB_ROOT"/fixtures/known/*.pas) ;;
  *) echo "output must be under $LAB_ROOT/fixtures/known" >&2; exit 2 ;;
esac

mkdir -p "$(dirname "$OUTPUT")"
jq -r --argjson issue "$ISSUE_ID" \
  '.[] | select(.iid == $issue) | .description' \
  "$LAB_ROOT"/cache/issues/fpc/page-*.json \
  | awk -v fence="$FENCE" '
      BEGIN { inside=0; found=0 }
      inside && /^```[[:space:]]*$/ { exit }
      inside {
        if ($0 ~ /\$ cat [^[:space:]]+[[:space:]]*$/) next
        print
        next
      }
      fence == "pascal" && tolower($0) ~ /^```pascal[[:space:]]*$/ {
        inside=1; found=1; next
      }
      fence == "unlabelled" && $0 ~ /^```[[:space:]]*$/ {
        inside=1; found=1; next
      }
      END { if (!found) exit 3 }
    ' > "$OUTPUT.tmp"

test -s "$OUTPUT.tmp"
grep -Eq 'end\.[[:space:]]*$' "$OUTPUT.tmp"
mv "$OUTPUT.tmp" "$OUTPUT"

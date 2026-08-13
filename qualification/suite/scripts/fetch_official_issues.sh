#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT=$(cd "$(dirname "$0")/.." && pwd)
ISSUE_ROOT="$LAB_ROOT/cache/issues"
USER_AGENT='fpc-unleashed-qualification-lab/1.0'

mkdir -p "$ISSUE_ROOT"

fetch_pages() {
  local name=$1
  local url_prefix=$2
  local forge=$3
  local out="$ISSUE_ROOT/$name"
  local page=1
  local total=0
  local pages=0
  local tracker_issues=0
  local pull_requests=0

  mkdir -p "$out"
  while :; do
    local stem
    local body
    local header
    local url
    local count
    local next
    stem=$(printf 'page-%05d' "$page")
    body="$out/$stem.json"
    header="$out/$stem.headers"
    url="${url_prefix}${page}"

    if [[ ! -s "$body" || ! -s "$header" ]]; then
      curl --fail --silent --show-error --location \
        --retry 5 --retry-all-errors --connect-timeout 20 --max-time 120 \
        --user-agent "$USER_AGENT" --dump-header "$header.tmp" \
        --output "$body.tmp" "$url"
      jq -e 'type == "array"' "$body.tmp" >/dev/null
      mv "$header.tmp" "$header"
      mv "$body.tmp" "$body"
    fi

    count=$(jq 'length' "$body")
    total=$((total + count))
    pages=$((pages + 1))
    printf '%s page=%d count=%d total=%d\n' "$name" "$page" "$count" "$total"

    if [[ "$forge" == gitlab ]]; then
      next=$(tr -d '\r' < "$header" | awk -F ': ' 'tolower($1) == "x-next-page" { print $2 }' | tail -n 1)
      if [[ -z "$next" ]]; then
        break
      fi
      page=$next
      sleep 0.15
    else
      if (( count < 100 )); then
        break
      fi
      page=$((page + 1))
      sleep 1
    fi
  done

  find "$out" -maxdepth 1 -type f -name 'page-*.json' -print0 \
    | sort -z | xargs -0 sha256sum > "$out/SHA256SUMS"
  if [[ "$forge" == github ]]; then
    pull_requests=$(jq -s '[.[][] | select(has("pull_request"))] | length' \
      "$out"/page-*.json)
    tracker_issues=$((total - pull_requests))
  else
    tracker_issues=$total
  fi
  jq -n \
    --arg project "$name" \
    --arg forge "$forge" \
    --arg endpoint "$url_prefix" \
    --argjson pages "$pages" \
    --argjson entries "$total" \
    --argjson issues "$tracker_issues" \
    --argjson pulls "$pull_requests" \
    '{project:$project, forge:$forge, endpoint_prefix:$endpoint,
      page_count:$pages, entries:$entries, issue_entries:$issues,
      pull_request_entries:$pulls, complete:true}' \
    > "$out/manifest.json"
}

case "${1:-all}" in
  fpc)
    fetch_pages fpc \
      'https://gitlab.com/api/v4/projects/freepascal.org%2Ffpc%2Fsource/issues?scope=all&state=all&order_by=created_at&sort=asc&per_page=100&page=' \
      gitlab
    ;;
  unleashed)
    fetch_pages unleashed \
      'https://api.github.com/repos/UnleashedPascal/compiler/issues?state=all&sort=created&direction=asc&per_page=100&page=' \
      github
    ;;
  mormot2)
    fetch_pages mormot2 \
      'https://api.github.com/repos/synopse/mORMot2/issues?state=all&sort=created&direction=asc&per_page=100&page=' \
      github
    ;;
  all)
    "$0" unleashed
    "$0" mormot2
    "$0" fpc
    ;;
  *)
    echo "usage: $0 [all|fpc|unleashed|mormot2]" >&2
    exit 2
    ;;
esac

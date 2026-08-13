#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DESTINATION="$ROOT/.qualification/deps/mormot2-compiler-corpus"
COMMIT=bc189414f1b9ea163d24029cc8e814405e8e0cb5
URL=https://github.com/synopse/mORMot2.git

if [[ -e "$DESTINATION" ]]; then
  ACTUAL=$(git -C "$DESTINATION" rev-parse HEAD 2>/dev/null || true)
  DIRTY=$(git -C "$DESTINATION" status --porcelain 2>/dev/null || true)
  if [[ "$ACTUAL" == "$COMMIT" && -z "$DIRTY" ]]; then
    echo "mORMot compiler corpus is ready: $COMMIT"
    exit 0
  fi
  echo "dependency directory is not clean mORMot $COMMIT: $DESTINATION" >&2
  exit 1
fi

mkdir -p "$(dirname "$DESTINATION")"
git init --quiet "$DESTINATION"
git -C "$DESTINATION" remote add origin "$URL"
git -C "$DESTINATION" fetch --quiet --depth=1 origin "$COMMIT"
git -C "$DESTINATION" checkout --quiet --detach FETCH_HEAD
ACTUAL=$(git -C "$DESTINATION" rev-parse HEAD)
[[ "$ACTUAL" == "$COMMIT" ]] || {
  echo "expected mORMot $COMMIT, got $ACTUAL" >&2
  exit 1
}
[[ -z "$(git -C "$DESTINATION" status --porcelain)" ]] || {
  echo "prepared mORMot worktree is dirty: $DESTINATION" >&2
  exit 1
}
echo "mORMot compiler corpus is ready: $COMMIT"

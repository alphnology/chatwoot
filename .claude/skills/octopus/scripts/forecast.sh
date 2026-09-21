#!/usr/bin/env bash
# Read-only merge forecast for the Octopus fork. Creates nothing, changes nothing.
#
#   forecast.sh <NEW_TAG> [DEV_BRANCH]
#   forecast.sh v4.18.0            # DEV_BRANCH defaults to octopus
#
# BASE is derived: the newest upstream release tag already merged into DEV_BRANCH.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1   # runnable from anywhere in the repo

NEW_TAG=${1:?usage: forecast.sh <NEW_TAG> [DEV_BRANCH]}
DEV=${2:-octopus}
TARGET=sync/$NEW_TAG
TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'

fail=0
say() { printf '%s\n' "$*"; }
hr()  { printf '%s\n' "────────────────────────────────────────────────────────"; }

hr; say "PREFLIGHT"; hr

if [ -n "$(git status --porcelain)" ]; then
  say "FAIL  working tree is dirty — commit or stash first (never stashed silently)"
  fail=1
else
  say "PASS  working tree clean"
fi

if ! echo "$NEW_TAG" | grep -qE "$TAG_RE"; then
  say "FAIL  $NEW_TAG is not an upstream release tag (vX.Y.Z) — only tags are merged"
  hr; say "FORECAST BLOCKED"; exit 1
fi

for ref in "$DEV" "$NEW_TAG"; do
  if git rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
    say "PASS  ref exists: $ref"
  else
    say "FAIL  ref missing: $ref  (git fetch upstream --tags ?)"
    hr; say "FORECAST BLOCKED"; exit 1
  fi
done

if git rev-parse --verify --quiet "origin/$DEV" >/dev/null; then
  counts=$(git rev-list --left-right --count "$DEV...origin/$DEV")
  if [ "$(git rev-parse "$DEV")" = "$(git rev-parse "origin/$DEV")" ]; then
    say "PASS  $DEV matches origin/$DEV"
  else
    say "FAIL  $DEV and origin/$DEV have diverged (ahead/behind: $counts) — pull or push first"
    fail=1
  fi
fi

BASE=$(git tag --merged "$DEV" --sort=-v:refname --list 'v[0-9]*' | grep -E "$TAG_RE" | head -1)
if [ -z "$BASE" ]; then
  say "FAIL  no upstream release tag is merged into $DEV — was a sync PR squashed?"
  hr; say "FORECAST BLOCKED"; exit 1
fi
say "INFO  $DEV is on upstream $BASE"

if git merge-base --is-ancestor "$NEW_TAG" "$DEV"; then
  say "FAIL  $NEW_TAG is already merged into $DEV"
  fail=1
elif [ "$(printf '%s\n%s\n' "$BASE" "$NEW_TAG" | sort -V | tail -1)" != "$NEW_TAG" ]; then
  say "FAIL  $NEW_TAG is older than the current base $BASE"
  fail=1
else
  say "PASS  $NEW_TAG is newer than $BASE"
fi

if git rev-parse --verify --quiet "$TARGET" >/dev/null; then
  say "WARN  $TARGET already exists — re-running means a force-push; check for an open PR"
fi

hr; say "SCALE"; hr
say "fork surface carried : $(git diff --shortstat "$BASE..$DEV")"
say "upstream commits     : $(git rev-list --count "$BASE..$NEW_TAG")"
say "migrations           : $(git ls-tree -r --name-only "$BASE" db/migrate | wc -l | tr -d ' ') -> $(git ls-tree -r --name-only "$NEW_TAG" db/migrate | wc -l | tr -d ' ')"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git diff --name-only "$BASE..$DEV"     | sort > "$tmp/ours"
git diff --name-only "$BASE..$NEW_TAG" | sort > "$tmp/theirs"
comm -12 "$tmp/ours" "$tmp/theirs" > "$tmp/both"
comm -23 "$tmp/ours" "$tmp/theirs" > "$tmp/ours_only"

hr; say "BOTH SIDES TOUCHED — likely conflicts ($(wc -l < "$tmp/both" | tr -d ' '))"; hr
say "(an upper bound: git merges many of these cleanly — 38 predicted vs 18 real on 4.10.1->4.16.2)"
cat "$tmp/both"

hr; say "OURS ONLY — SILENT-LOSS RISK ($(wc -l < "$tmp/ours_only" | tr -d ' '))"; hr
say "(these auto-merge with no marker and never enter the resolution loop — audit direction C)"
cat "$tmp/ours_only"

hr
[ "$fail" -eq 0 ] && say "FORECAST OK — safe to create $TARGET from $DEV" \
                  || say "FORECAST BLOCKED — resolve the FAIL rows above first"
exit "$fail"

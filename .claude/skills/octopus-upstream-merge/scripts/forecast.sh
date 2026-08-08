#!/usr/bin/env bash
# Read-only merge forecast for the Octopus fork. Creates nothing, changes nothing.
#
#   forecast.sh <OLD_VER> <NEW_VER> <OLD_BRANCH> [NEW_BRANCH]
#   forecast.sh 4.10.1 4.16.2 v4.10.1-dev-merge v4.16.2-dev
#
# BASE is always the upstream TAG, never the -dev branch (trap 2).

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1   # runnable from anywhere in the repo

OLD_VER=${1:?usage: forecast.sh <OLD_VER> <NEW_VER> <OLD_BRANCH> [NEW_BRANCH]}
NEW_VER=${2:?}
OLD=${3:?}
NEW=${4:-v${NEW_VER}-dev}
BASE=v$OLD_VER
TARGET=v${NEW_VER}-dev-merge

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

for ref in "$BASE" "$OLD" "$NEW" "v$NEW_VER"; do
  if git rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
    say "PASS  ref exists: $ref"
  else
    say "FAIL  ref missing: $ref  (git fetch upstream --tags ?)"
    fail=1
  fi
done

# Trap 2: the target -dev branch must be byte-identical to its upstream tag.
counts=$(git rev-list --left-right --count "$NEW...v$NEW_VER" 2>/dev/null)
if [ "$(echo "$counts" | tr -s '[:space:]' ' ' | tr -d ' ')" = "00" ]; then
  say "PASS  $NEW is exactly v$NEW_VER"
else
  say "FAIL  $NEW has drifted from v$NEW_VER (ahead/behind: $counts) — do not proceed"
  fail=1
fi

if git rev-parse --verify --quiet "$TARGET" >/dev/null; then
  say "WARN  $TARGET already exists — re-running means a force-push; check for an open PR"
fi

hr; say "SCALE"; hr
say "fork surface carried : $(git diff --shortstat "$BASE..$OLD")"
say "upstream commits     : $(git rev-list --count "$BASE..v$NEW_VER")"
say "migrations           : $(git ls-tree -r --name-only "$BASE" db/migrate | wc -l | tr -d ' ') -> $(git ls-tree -r --name-only "v$NEW_VER" db/migrate | wc -l | tr -d ' ')"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git diff --name-only "$BASE..$OLD"      | sort > "$tmp/ours"
git diff --name-only "$BASE..v$NEW_VER" | sort > "$tmp/theirs"
comm -12 "$tmp/ours" "$tmp/theirs" > "$tmp/both"
comm -23 "$tmp/ours" "$tmp/theirs" > "$tmp/ours_only"

hr; say "BOTH SIDES TOUCHED — likely conflicts ($(wc -l < "$tmp/both" | tr -d ' '))"; hr
say "(an upper bound: git merges many of these cleanly — 38 predicted vs 18 real on 4.10.1->4.16.2)"
cat "$tmp/both"

hr; say "OURS ONLY — SILENT-LOSS RISK ($(wc -l < "$tmp/ours_only" | tr -d ' '))"; hr
say "(these auto-merge with no marker and never enter the resolution loop — audit direction C)"
cat "$tmp/ours_only"

hr
[ "$fail" -eq 0 ] && say "FORECAST OK — safe to create $TARGET from $OLD" \
                  || say "FORECAST BLOCKED — resolve the FAIL rows above first"
exit "$fail"

#!/usr/bin/env bash
# Hourly WIP safety net. Captures uncommitted tracked + untracked changes
# to a daily snapshots/YYYY-MM-DD branch on origin, without touching
# master or the working directory. Silent on no-change.
#
# Restore from a snapshot:
#   git checkout snapshots/2026-04-20 -- <path>         # single file
#   git diff master..origin/snapshots/2026-04-20        # see all WIP
#
# Cleanup (manual, any time):
#   git push origin --delete snapshots/2026-04-13       # one branch
set -euo pipefail

WORKSPACE="${WORKSPACE:-/root/.openclaw/workspace}"
cd "$WORKSPACE"

# Fast path: nothing changed vs HEAD, no untracked files.
if git diff --quiet HEAD 2>/dev/null \
   && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  exit 0
fi

# Build a WIP tree using a *scratch* index so we never touch the real
# staging area. Start from a copy of the current index, then add everything
# (tracked changes + untracked non-ignored files) to the scratch copy.
TMP_INDEX=$(mktemp)
trap 'rm -f "$TMP_INDEX"' EXIT
cp "$(git rev-parse --git-path index)" "$TMP_INDEX" 2>/dev/null || :

export GIT_INDEX_FILE="$TMP_INDEX"
git add -A
TREE=$(git write-tree)
unset GIT_INDEX_FILE

PARENT=$(git rev-parse HEAD)
MSG="snapshot $(date -u +%FT%TZ)"
COMMIT=$(git commit-tree "$TREE" -p "$PARENT" -m "$MSG")

BRANCH="snapshots/$(date -u +%F)"
git update-ref "refs/heads/$BRANCH" "$COMMIT"
# Force-with-lease: the daily branch rewinds/advances as WIP evolves.
git push --force-with-lease origin "$BRANCH" >/dev/null 2>&1 || \
  git push --force           origin "$BRANCH" >/dev/null 2>&1 || true

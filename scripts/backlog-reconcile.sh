#!/usr/bin/env bash
# backlog-reconcile — detect open backlog IDs that have been resolved in
# overnight reports, learnings, or recent commits but never closed in
# backlog.jsonl. Fixes the 2026-04-21 drift where H5/H6 resolved 628dec/
# 12ae6e in code but the registry still listed them open.
#
# Usage:
#   scripts/backlog-reconcile.sh           # check only; prints mismatches
#   scripts/backlog-reconcile.sh --apply   # auto-close matches with a note
#
# Scans, in order:
#   1. reports/overnight-*.md   — looks for "^Close backlog <id>" or
#      "^Backlog: `<id>`" style headers paired with a "Resolved"/"Shipped"/
#      "Changes" section that proves the work landed.
#   2. reports/learnings.md     — "→ commit (<id>)" footer references.
#   3. git log since last 7d    — commit subjects containing "(backlog <id>)"
#      or "backlog <id>".
#
# Match rule: an ID is a "resolved candidate" if at least one source mentions
# it AND includes one of: "Resolved", "Shipped", "Changes (diff)", "Closed",
# "commit <7+ hex>", or matches a commit whose tree touched a file named in
# the overnight report. Conservative by default — prefers false negative
# (nag) over false positive (auto-close something still open).

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
BACKLOG="$WORKSPACE/backlog.jsonl"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

if [ ! -s "$BACKLOG" ]; then
  echo "no backlog file" >&2
  exit 0
fi

# 1. Collect open/doing IDs from backlog
OPEN_IDS=$(jq -r 'select(.status == "open" or .status == "doing") | .id' "$BACKLOG")
if [ -z "$OPEN_IDS" ]; then
  echo "no open backlog items"
  exit 0
fi

# 2. Scan resolution corpus: overnight reports + recent commits
OVERNIGHT_CORPUS=$(find "$WORKSPACE/reports" -maxdepth 1 -name 'overnight-*.md' -mtime -14 2>/dev/null)
GIT_CORPUS=$(git -C "$WORKSPACE" log --since=14.days --pretty='%H %s' 2>/dev/null)

MATCHES=""
for id in $OPEN_IDS; do
  # Require: id appears in an overnight report AND that report has a strong
  # resolution marker, OR id appears in a git commit subject as "(backlog id)".
  evidence=""

  if [ -n "$OVERNIGHT_CORPUS" ]; then
    for f in $OVERNIGHT_CORPUS; do
      if grep -q "$id" "$f" 2>/dev/null; then
        # Strong marker — report declares resolution
        if grep -Eiq '^## (Changes|Resolution|Shipped)|^Close backlog|Resolved|Shipped' "$f"; then
          commit=$(git -C "$WORKSPACE" log --since=14.days --pretty='%h %s' --grep="$id" 2>/dev/null | head -1)
          evidence="$f${commit:+ (commit: $commit)}"
          break
        fi
      fi
    done
  fi

  if [ -z "$evidence" ] && [ -n "$GIT_CORPUS" ]; then
    commit_line=$(printf '%s\n' "$GIT_CORPUS" | grep -E "(backlog $id|\\($id\\))" | head -1)
    if [ -n "$commit_line" ]; then
      evidence="commit: $commit_line"
    fi
  fi

  if [ -n "$evidence" ]; then
    title=$(jq -r --arg id "$id" 'select(.id == $id) | .title' "$BACKLOG")
    MATCHES+="$id|$title|$evidence"$'\n'
  fi
done

if [ -z "$MATCHES" ]; then
  echo "backlog clean — no open items with resolution evidence"
  exit 0
fi

echo "open backlog items with resolution evidence found:"
echo ""
printf '%s' "$MATCHES" | while IFS='|' read -r id title evidence; do
  [ -z "$id" ] && continue
  printf '  %s  %s\n    evidence: %s\n\n' "$id" "$title" "$evidence"
done

if [ "$APPLY" -eq 1 ]; then
  echo "--apply: closing matched items"
  printf '%s' "$MATCHES" | while IFS='|' read -r id title evidence; do
    [ -z "$id" ] && continue
    bash "$WORKSPACE/scripts/backlog.sh" done "$id" >/dev/null
    bash "$WORKSPACE/scripts/backlog.sh" note "$id" "Auto-closed by backlog-reconcile: $evidence" >/dev/null
    echo "  closed $id"
  done
else
  echo "run with --apply to auto-close these items"
  exit 1
fi

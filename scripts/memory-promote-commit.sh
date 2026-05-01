#!/usr/bin/env bash
# memory-promote-commit.sh — durable commit for memory-promotion deltas.
#
# The OpenClaw memory-core dream-promotion (~03:00 UTC) writes MEMORY.md but
# does NOT git-commit. Subsequent operations on the workspace see a dirty
# tree and either (a) bail (SEPL), or (b) mix the promotion into unrelated
# commits. This script makes the promotion durable as its own commit, on
# its own cron, immediately after the promotion completes.
#
# Schedule (see openclaw cron): 10 3 * * * UTC.
#
# Idempotent: exits 0 with no output if MEMORY.md is clean. Refuses to
# commit if anything beyond MEMORY.md is dirty (that's not ours).
#
# Exit codes:
#   0 — clean tree OR committed cleanly
#   1 — refused (something else is dirty)
#   2 — git error during commit
set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
cd "$WORKSPACE" || exit 2

# Nothing to do if MEMORY.md is clean.
if git diff --quiet -- MEMORY.md && git diff --cached --quiet -- MEMORY.md; then
  exit 0
fi

# Refuse if there are staged changes (to anything).
if ! git diff --cached --quiet; then
  echo "memory-promote-commit: staged changes present — refusing" >&2
  exit 1
fi

# Refuse if any other file in the working tree is dirty.
dirty=$(git diff --name-only)
if [ "$dirty" != "MEMORY.md" ]; then
  echo "memory-promote-commit: non-MEMORY.md files dirty — refusing:" >&2
  printf '  %s\n' $dirty >&2
  exit 1
fi

# Sanity-check: the diff should carry the promotion marker. If it doesn't,
# this is a manual edit and we should NOT auto-commit it.
if ! git diff -- MEMORY.md | grep -q '<!-- openclaw-memory-promotion:'; then
  echo "memory-promote-commit: MEMORY.md dirty but lacks promotion marker — refusing (looks manual)" >&2
  exit 1
fi

git add MEMORY.md
git commit -q -m "auto: memory promotion $(date -u +%F)

Durable commit for the dream-promotion delta written by openclaw
memory-core at ~03:00 UTC. Without this, MEMORY.md sits dirty and
trips the SEPL pre-flight clean-tree check at 03:30 UTC.

Trigger: scripts/memory-promote-commit.sh (cron 10 3 * * * UTC)" \
  || { echo "memory-promote-commit: git commit failed" >&2; exit 2; }

echo "memory-promote-commit: committed $(git rev-parse --short HEAD)"
exit 0

#!/usr/bin/env bash
# improve.sh — SEPL Improve step.
# Takes a candidate from a select-<date>.md, branches sepl/<date>-<slug>,
# spawns a Claude Code subagent to implement the candidate, runs evals,
# merges to master on green / rolls back on red, logs every attempt.
#
# Usage:
#   scripts/improve.sh <select-id> <slug>
#   scripts/improve.sh select-2026-04-23 audit-state-guard-log-jsonl-for-bypass-rate-if-ope
#
# Env knobs:
#   IMPROVE_DRY_RUN=1   — don't spawn subagent, just print the brief
#   IMPROVE_NO_MERGE=1  — never merge even on green (leave branch for review)
#   IMPROVE_TIMEOUT=600 — subagent timeout in seconds (default 600)
#
# Exit: 0 merged, 1 rolled-back, 2 left-open (no-merge mode), 3 input error.
set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
REPORTS="$WORKSPACE/reports"
TODAY="$(date -u +%Y-%m-%d)"
NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG="$REPORTS/improve-$TODAY.jsonl"
TIMEOUT="${IMPROVE_TIMEOUT:-600}"

select_id="${1:-}"
slug="${2:-}"
if [ -z "$select_id" ] || [ -z "$slug" ]; then
  echo "usage: improve.sh <select-id> <slug>" >&2
  echo "  select-id: e.g., select-2026-04-23 (no .md suffix)" >&2
  echo "  slug:      candidate slug from the select report" >&2
  exit 3
fi

select_file="$REPORTS/${select_id}.md"
[ -f "$select_file" ] || { echo "improve: $select_file not found" >&2; exit 3; }

# Pull the candidate body from the "Original line:" block under "### N. `slug`".
candidate_body=$(awk -v slug="$slug" '
  $0 ~ "^### [0-9]+\\. `"slug"`" { in_block=1; next }
  in_block && /^### / { exit }
  in_block && /^> / { sub(/^> /, ""); print; exit }
' "$select_file")

if [ -z "$candidate_body" ]; then
  echo "improve: slug '$slug' not found in $select_file" >&2
  exit 3
fi

branch="sepl/${TODAY}-${slug}"
log_attempt() {
  local result="$1" detail="$2"
  printf '{"ts":"%s","branch":"%s","slug":"%s","select":"%s","result":"%s","detail":%s}\n' \
    "$NOW_TS" "$branch" "$slug" "$select_id" "$result" \
    "$(printf '%s' "$detail" | jq -Rs .)" >> "$LOG"
}

cd "$WORKSPACE"

# Refuse if working tree is dirty (we don't want to mix in user work).
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "improve: working tree is dirty — commit or stash before improve.sh" >&2
  log_attempt "abort_dirty_tree" "git status not clean"
  exit 3
fi

git fetch -q origin master 2>/dev/null || true
master_sha=$(git rev-parse master)

# Create the branch (or reuse if it exists from a prior attempt).
if git show-ref --verify --quiet "refs/heads/$branch"; then
  echo "improve: branch $branch already exists — checking out, will skip subagent if non-empty"
  git checkout -q "$branch"
else
  git checkout -q -b "$branch" master
fi

echo "improve: branch=$branch"
echo "improve: candidate=$candidate_body"
echo

if [ "${IMPROVE_DRY_RUN:-0}" = "1" ]; then
  echo "improve: DRY_RUN — brief above, not spawning subagent"
  log_attempt "dry_run" "brief printed only"
  git checkout -q master
  git branch -q -D "$branch" 2>/dev/null || true
  exit 0
fi

# Spawn the subagent. Brief is the candidate body + workspace conventions
# pointer. Subagent runs with bypassPermissions so it can edit files freely;
# eval gate is the safety net.
brief=$(cat <<BRIEF
You are implementing a SEPL Improve candidate. Workspace: $WORKSPACE.
You are on branch $branch (forked from master).

CANDIDATE TO IMPLEMENT:
$candidate_body

GUARDRAILS:
- Make the smallest change that satisfies the candidate.
- If the candidate is an "audit" task, the deliverable is a report file under reports/ — keep it short and factual.
- If the candidate is a code change, edit existing files; avoid creating new ones unless required.
- After your changes, stage them with: git add -A
- Do NOT commit. The orchestrator will commit, run evals, and decide merge/rollback.
- Read SOUL.md and AGENTS.md for tone if you author user-facing prose.

Begin. Report a one-line summary of what you changed when done.
BRIEF
)

subagent_log="$REPORTS/improve-${TODAY}-${slug}.subagent.log"
echo "improve: spawning Claude Code subagent (timeout=${TIMEOUT}s, log=$subagent_log)"
timeout "$TIMEOUT" claude --print --permission-mode bypassPermissions "$brief" \
  > "$subagent_log" 2>&1
sub_exit=$?

if [ "$sub_exit" -ne 0 ]; then
  echo "improve: subagent failed (exit=$sub_exit) — see $subagent_log"
  git checkout -q master
  log_attempt "subagent_fail" "exit=$sub_exit log=$subagent_log"
  exit 1
fi

# Capture diff + commit.
if git diff --cached --quiet && git diff --quiet; then
  echo "improve: subagent produced no changes — abandoning branch"
  git checkout -q master
  git branch -q -D "$branch"
  log_attempt "no_changes" "subagent ran but staged nothing"
  exit 1
fi

git add -A
git commit -q -m "[no-push] sepl/improve: $slug

Candidate: $candidate_body

Source: $select_file
Branch: $branch
Subagent log: $subagent_log" \
  || { echo "improve: commit failed"; log_attempt "commit_fail" "git commit returned non-zero"; exit 1; }

# Eval gate.
echo "improve: running evals/run.sh as the gate"
eval_log="$REPORTS/improve-${TODAY}-${slug}.eval.log"
bash "$WORKSPACE/evals/run.sh" > "$eval_log" 2>&1
eval_exit=$?

if [ "$eval_exit" -ne 0 ]; then
  echo "improve: evals FAILED (exit=$eval_exit) — rolling back"
  git checkout -q master
  git branch -q -D "$branch"
  log_attempt "rollback_eval_fail" "eval_exit=$eval_exit log=$eval_log"
  exit 1
fi

if [ "${IMPROVE_NO_MERGE:-0}" = "1" ]; then
  echo "improve: evals green; IMPROVE_NO_MERGE=1, leaving branch $branch for review"
  git checkout -q master
  log_attempt "left_open" "branch ready: $branch"
  exit 2
fi

# Merge to master. Use --no-ff so the SEPL merge is auditable in log.
echo "improve: evals green, merging $branch -> master"
git checkout -q master
git merge --no-ff -q -m "sepl/merge: $slug

Improve candidate from $select_id passed evals, merging.
Branch: $branch
Eval log: $eval_log" \
  "$branch"
merge_exit=$?

if [ "$merge_exit" -ne 0 ]; then
  echo "improve: merge conflicted — leaving branch $branch, master untouched"
  git merge --abort 2>/dev/null || true
  log_attempt "merge_conflict" "merge --no-ff returned $merge_exit"
  exit 1
fi

# Cleanup branch (kept in reflog if needed). Master post-commit hook handles push.
git branch -q -d "$branch"
echo "improve: merged $branch into master (post-commit hook will push)"
log_attempt "merged" "master sha=$(git rev-parse --short master)"
exit 0

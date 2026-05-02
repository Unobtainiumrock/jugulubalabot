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

# Implementability pre-check: refuse the candidate before spawning a 600s
# subagent if it's observation-shaped (rerun/audit/etc.) or names no concrete
# deliverable. select.sh already runs this guard on full candidate lists, but
# improve.sh is also reachable via direct CLI invocation, so re-run here.
shape_guard="$WORKSPACE/scripts/guards/candidate-shape.sh"
if [ -x "$shape_guard" ]; then
  if ! bash "$shape_guard" "$candidate_body" >&2; then
    echo "improve: candidate failed shape guard — refusing to spawn subagent" >&2
    git checkout -q master
    git branch -q -D "$branch" 2>/dev/null || true
    log_attempt "abort_shape_guard" "candidate=$candidate_body"
    exit 3
  fi
fi

if [ "${IMPROVE_DRY_RUN:-0}" = "1" ]; then
  echo "improve: DRY_RUN — brief above, not spawning subagent (skipping baseline eval)"
  log_attempt "dry_run" "brief printed only"
  git checkout -q master
  git branch -q -D "$branch" 2>/dev/null || true
  exit 0
fi

# Compute baseline fail-set on master, cached by master sha. The gate is a
# delta-vs-baseline check, not absolute pass/fail — a candidate that lands
# on a red eval set should only roll back if it makes things worse.
# We run the baseline against master's working tree, so do this BEFORE the
# subagent edits the branch (we're now on the branch but it's identical to
# master until the subagent changes things — checking out master to be safe).
baseline_cache="$REPORTS/eval-baseline-master-${master_sha}.fails"
if [ ! -f "$baseline_cache" ]; then
  echo "improve: no baseline cache for master ${master_sha:0:7} — running eval on master"
  git checkout -q master
  baseline_log="$REPORTS/improve-${TODAY}-baseline-${master_sha:0:7}.eval.log"
  bash "$WORKSPACE/evals/run.sh" > "$baseline_log" 2>&1
  base_exit=$?
  if [ "$base_exit" -eq 2 ]; then
    echo "improve: master baseline hit meta-shape guard — aborting" >&2
    git branch -q -D "$branch" 2>/dev/null || true
    log_attempt "abort_baseline_meta" "exit=$base_exit log=$baseline_log"
    exit 1
  fi
  base_run_dir=$(awk '/^Artifacts: /{print $2; exit}' "$baseline_log")
  if [ -z "$base_run_dir" ] || [ ! -f "$base_run_dir/summary.tsv" ]; then
    echo "improve: baseline produced no summary.tsv — aborting" >&2
    git branch -q -D "$branch" 2>/dev/null || true
    log_attempt "abort_baseline_no_summary" "log=$baseline_log"
    exit 1
  fi
  awk -F'\t' 'NR>1 && $2=="FAIL"{print $1}' "$base_run_dir/summary.tsv" \
    | sort -u > "$baseline_cache"
  git checkout -q "$branch"
fi
baseline_fail_count=$(wc -l < "$baseline_cache" | tr -d ' ')
echo "improve: baseline on master ${master_sha:0:7} — ${baseline_fail_count} failing fixtures"

# Extract target fixtures from candidate body (any evals/fixtures/*.json
# basename mentioned with word boundaries). Used for prior-rollback
# overlap matching so a previous attempt that broke X surfaces when a
# new candidate also targets X.
extract_targets() {
  local body="$1"
  local f name
  for f in "$WORKSPACE/evals/fixtures"/*.json; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .json)
    if echo "$body" | grep -qE "\\b${name}\\b"; then
      echo "$name"
    fi
  done
}
current_targets=$(extract_targets "$candidate_body" | sort -u)

# Build "PRIOR FAILED ATTEMPTS" block from past rollback metadata. Match
# is OR: same slug, OR overlapping target fixtures. Most-recent first,
# capped at 3, diff truncated to 200 lines each. The point is to feed
# the subagent the exact patch-shapes that lost so it doesn't redraw the
# same losing edit a third time. Closes the regression-mode learning
# gap: each rollback was previously logged-and-forgotten.
prior_block=""
prior_count=0
if compgen -G "$REPORTS/improve-rollback-*.meta.json" > /dev/null; then
  while IFS= read -r meta; do
    [ -f "$meta" ] || continue
    meta_slug=$(jq -r '.slug // ""' "$meta" 2>/dev/null)
    overlap=0
    if [ "$meta_slug" = "$slug" ]; then
      overlap=1
    elif [ -n "$current_targets" ]; then
      while IFS= read -r t; do
        [ -n "$t" ] || continue
        if jq -e --arg t "$t" '.target_fixtures // [] | index($t)' "$meta" >/dev/null 2>&1; then
          overlap=1; break
        fi
      done <<< "$current_targets"
    fi
    if [ "$overlap" -eq 1 ]; then
      prior_count=$((prior_count + 1))
      [ "$prior_count" -gt 3 ] && break
      diff_path=${meta%.meta.json}.diff
      regs=$(jq -r '.regressions // ""' "$meta" 2>/dev/null)
      prior_date=$(jq -r '.date // ""' "$meta" 2>/dev/null)
      prior_slug=$(jq -r '.slug // ""' "$meta" 2>/dev/null)
      diff_excerpt=""
      if [ -f "$diff_path" ]; then
        diff_excerpt=$(head -200 "$diff_path")
      fi
      prior_block="$prior_block
[$prior_date] slug=$prior_slug regressions=$regs
diff (≤200 lines):
\`\`\`diff
$diff_excerpt
\`\`\`
"
    fi
  done < <(ls -t "$REPORTS"/improve-rollback-*.meta.json 2>/dev/null)
fi

prior_section=""
if [ "$prior_count" -gt 0 ]; then
  prior_section=$(cat <<PRIOR_BLOCK_END

PRIOR FAILED ATTEMPTS ON OVERLAPPING TARGETS ($prior_count attempt(s)):
The orchestrator already tried similar edits and rolled them back because
they regressed other fixtures. Read these patches and DO NOT repeat the
same shape. If a wording change failed before, the substantive change
needed is structural — actual rule, actual contract, actual behavior —
not another phrasing of the same advice.
$prior_block
PRIOR_BLOCK_END
)
fi

# Spawn the subagent. Brief is the candidate body + workspace conventions
# pointer. Subagent runs with bypassPermissions so it can edit files freely;
# eval gate is the safety net.
brief=$(cat <<BRIEF
You are implementing a SEPL Improve candidate. Workspace: $WORKSPACE.
You are on branch $branch (forked from master).

CANDIDATE TO IMPLEMENT:
$candidate_body
$prior_section
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

# Eval gate. Delta-vs-master: rollback only if the branch introduces a fixture
# that fails on the branch but passed on master. Same-or-better is green.
echo "improve: running evals/run.sh as the gate"
eval_log="$REPORTS/improve-${TODAY}-${slug}.eval.log"
bash "$WORKSPACE/evals/run.sh" > "$eval_log" 2>&1
eval_exit=$?

if [ "$eval_exit" -eq 2 ]; then
  echo "improve: branch eval hit meta-shape guard — rolling back"
  git checkout -q master
  git branch -q -D "$branch"
  log_attempt "rollback_meta_guard" "eval_exit=$eval_exit log=$eval_log"
  exit 1
fi

branch_run_dir=$(awk '/^Artifacts: /{print $2; exit}' "$eval_log")
if [ -z "$branch_run_dir" ] || [ ! -f "$branch_run_dir/summary.tsv" ]; then
  echo "improve: branch eval produced no summary.tsv — rolling back"
  git checkout -q master
  git branch -q -D "$branch"
  log_attempt "rollback_no_summary" "log=$eval_log"
  exit 1
fi

branch_fails_file=$(mktemp)
awk -F'\t' 'NR>1 && $2=="FAIL"{print $1}' "$branch_run_dir/summary.tsv" \
  | sort -u > "$branch_fails_file"

regressions=$(comm -23 "$branch_fails_file" "$baseline_cache")
improvements=$(comm -13 "$branch_fails_file" "$baseline_cache")
reg_count=$(printf '%s\n' "$regressions" | grep -c . || true)
imp_count=$(printf '%s\n' "$improvements" | grep -c . || true)
rm -f "$branch_fails_file"

if [ "$reg_count" -gt 0 ]; then
  reg_csv=$(printf '%s' "$regressions" | tr '\n' ',' | sed 's/,$//')
  echo "improve: $reg_count regression(s) vs master ${master_sha:0:7}: $reg_csv — rolling back"
  # Capture the patch + metadata BEFORE deleting the branch so the next
  # Improve attempt on this slug (or an overlapping target) can replay it
  # in the brief and avoid the same shape. Keyed by date+slug; if the same
  # slug rolls back twice in a day, the second writeover is intentional —
  # latest-fail is the most relevant teaching example.
  rollback_diff="$REPORTS/improve-rollback-${TODAY}-${slug}.diff"
  rollback_meta="$REPORTS/improve-rollback-${TODAY}-${slug}.meta.json"
  git diff master.."$branch" > "$rollback_diff" 2>/dev/null || true
  targets_json=$(printf '%s\n' "${current_targets:-}" | jq -R . | jq -s 'map(select(. != ""))' 2>/dev/null || echo '[]')
  jq -n \
    --arg date "$TODAY" \
    --arg ts "$NOW_TS" \
    --arg slug "$slug" \
    --arg candidate "$candidate_body" \
    --arg regressions "$reg_csv" \
    --arg branch "$branch" \
    --arg diff "$rollback_diff" \
    --argjson targets "$targets_json" \
    '{date:$date, ts:$ts, slug:$slug, candidate:$candidate, regressions:$regressions, branch:$branch, diff_path:$diff, target_fixtures:$targets}' \
    > "$rollback_meta"
  git checkout -q master
  git branch -q -D "$branch"
  log_attempt "rollback_regression" "regressions=$reg_csv improvements=$imp_count log=$eval_log diff=$rollback_diff"
  exit 1
fi

echo "improve: no regressions vs master ${master_sha:0:7} (improvements=$imp_count)"

if [ "${IMPROVE_NO_MERGE:-0}" = "1" ]; then
  echo "improve: gate green; IMPROVE_NO_MERGE=1, leaving branch $branch for review"
  git checkout -q master
  log_attempt "left_open" "branch ready: $branch improvements=$imp_count"
  exit 2
fi

# Merge to master. Use --no-ff so the SEPL merge is auditable in log.
echo "improve: gate green (delta vs master), merging $branch -> master"
git checkout -q master
git merge --no-ff -q -m "sepl/merge: $slug

Improve candidate from $select_id passed delta-vs-master gate, merging.
Branch: $branch
Master baseline sha: ${master_sha:0:7} (${baseline_fail_count} failing fixtures)
Improvements vs baseline: ${imp_count}
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
log_attempt "merged" "master sha=$(git rev-parse --short master) improvements=$imp_count"
exit 0

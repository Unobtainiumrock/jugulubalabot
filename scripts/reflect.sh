#!/usr/bin/env bash
# SEPL Reflect step — deterministic signal extraction from one day of traces.
# Writes workspace/reports/reflect-YYYY-MM-DD.md with raw aggregates and a
# hypothesis template for God + Tai to fill in together.
#
# Usage:
#   bash scripts/reflect.sh              # today (UTC)
#   bash scripts/reflect.sh 2026-04-19   # specific date

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
DATE="${1:-$(date -u +%F)}"
TRACE="$WORKSPACE/traces/$DATE.jsonl"
OUT_DIR="$WORKSPACE/reports"
OUT="$OUT_DIR/reflect-$DATE.md"

if [ ! -f "$TRACE" ]; then
  echo "No trace file at $TRACE" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# Token accounting — refresh today's turn data if transcripts exist
TURNS_FILE="$WORKSPACE/turns/$DATE.jsonl"
if [ -d "/root/.claude/projects/-root--openclaw-workspace" ]; then
  bash "$WORKSPACE/scripts/token-accounting.sh" "$DATE" >/dev/null 2>&1 || true
fi

TOTAL=$(wc -l < "$TRACE" | tr -d ' ')
SESSIONS=$(jq -r '.session_id' "$TRACE" | sort -u | wc -l | tr -d ' ')
SUCCESS=$(jq -r 'select(.success == true) | .tool' "$TRACE" | wc -l | tr -d ' ')
FAILURES=$(jq -r 'select(.success == false) | .tool' "$TRACE" | wc -l | tr -d ' ')
SUCCESS_PCT="n/a"
if [ "$TOTAL" -gt 0 ]; then
  SUCCESS_PCT=$(awk -v s="$SUCCESS" -v t="$TOTAL" 'BEGIN {printf "%.1f%%", 100.0*s/t}')
fi

# Tool breakdown (sorted desc)
TOOL_BREAKDOWN=$(jq -r '.tool' "$TRACE" | sort | uniq -c | sort -rn \
  | awk '{printf "| %-20s | %5d |\n", $2, $1}')

# Bin breakdown (semantic intent)
BIN_NULL_COUNT=$(jq -r 'select(.bin == null) | 1' "$TRACE" | wc -l | tr -d ' ')
BIN_BREAKDOWN=$(jq -r '.bin // "null"' "$TRACE" | sort | uniq -c | sort -rn \
  | awk -v t="$TOTAL" '{printf "| %-16s | %5d | %5.1f%% |\n", $2, $1, 100.0*$1/t}')

# Source breakdown (session-context origin)
SOURCE_BREAKDOWN=$(jq -r '.source // "unknown"' "$TRACE" | sort | uniq -c | sort -rn \
  | awk -v t="$TOTAL" '{printf "| %-14s | %5d | %5.1f%% |\n", $2, $1, 100.0*$1/t}')

# Class breakdown per tool — top 15 (tool, class, count)
CLASS_BREAKDOWN=$(jq -r '[.tool, (.class // "—")] | @tsv' "$TRACE" \
  | sort | uniq -c | sort -rn | head -15 \
  | awk '{tool=$2; class=$3; for(i=4;i<=NF;i++) class=class" "$i; printf "| %-20s | %-20s | %5d |\n", tool, class, $1}')

# Duration stats per tool (p50/p95, only rows with duration_ms)
DURATION_STATS=$(jq -r 'select(.duration_ms != null) | [.tool, .duration_ms] | @tsv' "$TRACE" \
  | awk '{
      tool=$1; dur=$2;
      durs[tool] = (tool in durs ? durs[tool]"\n" : "") dur;
    }
    END {
      for (t in durs) {
        n=split(durs[t], a, "\n");
        # sort
        for (i=1; i<=n; i++) for (j=i+1; j<=n; j++) if (a[i]+0 > a[j]+0) { tmp=a[i]; a[i]=a[j]; a[j]=tmp }
        p50 = a[int((n+1)/2)];
        p95 = a[int(n*0.95 < 1 ? 1 : n*0.95)];
        if (p95+0 == 0 && n > 0) p95 = a[n];
        printf "| %-20s | %5d | %6d | %6d |\n", t, n, p50, p95;
      }
    }' | sort -t'|' -k3 -rn)

# Cost aggregates from turns file
COST_SECTION="_no transcript data_"
if [ -f "$TURNS_FILE" ] && [ -s "$TURNS_FILE" ]; then
  COST_SECTION=$(jq -s '
    {
      turns: length,
      sessions: (map(.session_id) | unique | length),
      cost_usd: ((map(.cost_cents) | add) / 100),
      input_tokens: (map(.input_tokens) | add),
      output_tokens: (map(.output_tokens) | add),
      cache_write: (map(.cache_write_tokens) | add),
      cache_read: (map(.cache_read_tokens) | add)
    }
    | "| Turns | Sessions | Cost USD | In tok | Out tok | Cache write | Cache read |
|-------|----------|----------|--------|---------|-------------|------------|
| \(.turns) | \(.sessions) | $\(.cost_usd | . * 100 | round / 100) | \(.input_tokens) | \(.output_tokens) | \(.cache_write) | \(.cache_read) |"
  ' "$TURNS_FILE" -r)
fi

# Top 5 most expensive turns (for token-burn candidate detection)
TOP_COST=$(jq -s 'sort_by(-.cost_cents) | .[0:5] | .[]
  | "| $\(.cost_cents / 100 | . * 100 | round / 100) | \(.ts | split("T")[1] | split(".")[0]) | \(.tools | join(",") // "—") | \(.output_tokens) out |"' \
  "$TURNS_FILE" -r 2>/dev/null)
if [ -z "$TOP_COST" ]; then
  TOP_COST="| _no data_ |  |  |  |"
fi

# Repeated input_hashes (≥3x = deterministic-conversion candidate)
REPEATS=$(jq -r '[.tool, .class // "—", .input_hash] | @tsv' "$TRACE" \
  | sort | uniq -c | sort -rn \
  | awk '$1 >= 3 {printf "| %5d | %-12s | %-20s | %s |\n", $1, $4, $2, $3}' \
  | head -10)
if [ -z "$REPEATS" ]; then
  REPEATS="| _none — no input_hash repeated ≥3× today_ |  |  |  |"
fi

# Open backlog (active items from backlog.jsonl)
BACKLOG_FILE="$WORKSPACE/backlog.jsonl"
BACKLOG_SECTION="_backlog empty_"
if [ -f "$BACKLOG_FILE" ] && [ -s "$BACKLOG_FILE" ]; then
  BACKLOG_SECTION=$(jq -r 'select(.status == "open" or .status == "doing")
    | "| \(.id) | \(.status) | \(.priority) | \(.title) |"' "$BACKLOG_FILE")
  if [ -z "$BACKLOG_SECTION" ]; then BACKLOG_SECTION="_no active items_"; fi
fi

# Backlog drift — open items whose resolution evidence already landed in code
BACKLOG_DRIFT=$(bash "$WORKSPACE/scripts/backlog-reconcile.sh" 2>&1 || true)
if printf '%s' "$BACKLOG_DRIFT" | grep -q 'resolution evidence found'; then
  BACKLOG_DRIFT_SECTION="$BACKLOG_DRIFT"
else
  BACKLOG_DRIFT_SECTION="_no drift — backlog registry matches reports/commits_"
fi

# Review sidecar status (human-filled hypotheses + next-steps live separately
# so reflect.sh regeneration can't clobber them)
REVIEW_FILE="$OUT_DIR/reflect-$DATE-review.md"
if [ ! -f "$REVIEW_FILE" ]; then
  REVIEW_STATUS="pending (no review file yet — fill \`$REVIEW_FILE\` to close SEPL step 1/5)"
  REVIEW_PREVIEW="_Review not yet started._"
elif grep -q 'fill in manually\|_What.s the most expensive' "$REVIEW_FILE" 2>/dev/null; then
  REVIEW_STATUS="template (contains unfilled placeholder text)"
  REVIEW_PREVIEW="_Template present but unfilled. Replace placeholder lines with real hypotheses from the signal above._"
else
  REVIEW_STATUS="filled"
  REVIEW_PREVIEW=$(head -40 "$REVIEW_FILE" | sed 's/^/> /')
fi

# Failure rows (full JSON, one per line, capped)
FAIL_ROWS=$(jq -c 'select(.success == false) | {ts, tool, class, duration_ms, session_id}' "$TRACE" | head -20)
if [ -z "$FAIL_ROWS" ]; then
  FAIL_ROWS="_no failures today — either Tai got lucky or graders are too lax_"
fi

# Session attribution (top 10 sessions by invocation count)
SESSION_ATTR=$(jq -r '.session_id' "$TRACE" | sort | uniq -c | sort -rn | head -10 \
  | awk '{sid=$2; short=substr(sid,1,8); printf "| %-10s | %5d |\n", short, $1}')
# Cross-reference with turn cost if available
if [ -f "$TURNS_FILE" ] && [ -s "$TURNS_FILE" ]; then
  SESSION_COST=$(jq -s 'group_by(.session_id) | map({sid: .[0].session_id, turns: length, cost: ((map(.cost_cents) | add) / 100)}) | sort_by(-.cost) | .[0:5] | .[]
    | "| \(.sid[0:8]) | \(.turns) | $\(.cost | . * 100 | round / 100) |"' "$TURNS_FILE" -r 2>/dev/null)
fi
if [ -z "${SESSION_COST:-}" ]; then
  SESSION_COST="| _no turn-level cost data_ |  |  |"
fi

# Tool sequence pairs (adjacent same-session, count ≥3)
SEQ_PAIRS=$(jq -s 'sort_by(.session_id, .ts) | .[] | [.session_id, .tool, .class // "—"] | @tsv' "$TRACE" -r \
  | awk -F'\t' '
      BEGIN { prev_sid=""; prev_sig=""; }
      {
        sid=$1; sig=$2":"$3;
        if (sid == prev_sid && prev_sig != "") {
          pair = prev_sig " → " sig;
          count[pair]++;
        }
        prev_sid=sid; prev_sig=sig;
      }
      END { for (p in count) if (count[p] >= 3) printf "%d\t%s\n", count[p], p; }' \
  | sort -rn | head -10 \
  | awk -F'\t' '{printf "| %5d | %s |\n", $1, $2}')
if [ -z "$SEQ_PAIRS" ]; then
  SEQ_PAIRS="| _no pair repeated ≥3× today_ |  |"
fi

# Cross-day delta (today vs yesterday)
YESTERDAY=$(date -u -d "$DATE -1 day" +%F 2>/dev/null || echo "")
PRIOR_TRACE="$WORKSPACE/traces/$YESTERDAY.jsonl"
if [ -n "$YESTERDAY" ] && [ -f "$PRIOR_TRACE" ]; then
  PRIOR_TOTAL=$(wc -l < "$PRIOR_TRACE" | tr -d ' ')
  PRIOR_FAIL=$(jq -r 'select(.success == false) | .tool' "$PRIOR_TRACE" | wc -l | tr -d ' ')
  PRIOR_TOP_TOOL=$(jq -r '.tool' "$PRIOR_TRACE" | sort | uniq -c | sort -rn | head -1 | awk '{print $2" ("$1")"}')
  TODAY_TOP_TOOL=$(jq -r '.tool' "$TRACE" | sort | uniq -c | sort -rn | head -1 | awk '{print $2" ("$1")"}')
  VOL_DELTA=$((TOTAL - PRIOR_TOTAL))
  FAIL_DELTA=$((FAILURES - PRIOR_FAIL))
  DELTA_SECTION=$(printf '| Metric | %s | %s | Δ |\n|--------|------------|------------|---|\n| Invocations | %d | %d | %+d |\n| Failures | %d | %d | %+d |\n| Top tool | %s | %s | — |\n' \
    "$YESTERDAY" "$DATE" "$PRIOR_TOTAL" "$TOTAL" "$VOL_DELTA" "$PRIOR_FAIL" "$FAILURES" "$FAIL_DELTA" "$PRIOR_TOP_TOOL" "$TODAY_TOP_TOOL")
else
  DELTA_SECTION="_no prior-day trace available at $PRIOR_TRACE — skipping delta_"
fi

# Behavioral habits — explicit count of system-prompt violations
CD_COUNT=$(jq -r 'select(.tool == "Bash" and .class == "cd") | 1' "$TRACE" | wc -l | tr -d ' ')
ECHO_COUNT=$(jq -r 'select(.tool == "Bash" and .class == "echo") | 1' "$TRACE" | wc -l | tr -d ' ')
CAT_COUNT=$(jq -r 'select(.tool == "Bash" and .class == "cat") | 1' "$TRACE" | wc -l | tr -d ' ')
GREP_COUNT=$(jq -r 'select(.tool == "Bash" and (.class == "grep" or .class == "rg")) | 1' "$TRACE" | wc -l | tr -d ' ')
FIND_COUNT=$(jq -r 'select(.tool == "Bash" and .class == "find") | 1' "$TRACE" | wc -l | tr -d ' ')
HABITS_SECTION=$(printf '| Pattern | Count | Guidance |\n|---------|-------|----------|\n| `cd` prefix | %d | Bash cwd persists — use absolute paths / `git -C` |\n| `echo` | %d | Prefer direct text output over echo |\n| `cat` | %d | Prefer Read tool over cat |\n| `grep`/`rg` via Bash | %d | Use Grep tool, not Bash |\n| `find` via Bash | %d | Use Glob tool, not Bash find |\n' \
  "$CD_COUNT" "$ECHO_COUNT" "$CAT_COUNT" "$GREP_COUNT" "$FIND_COUNT")

# OpenClaw primitive usage — are we leveraging OpenClaw as intended?
MCP_OPENCLAW_COUNT=$(jq -r 'select(.tool | startswith("mcp__openclaw__")) | 1' "$TRACE" | wc -l | tr -d ' ')
MCP_OPENCLAW_BREAKDOWN=$(jq -r 'select(.tool | startswith("mcp__openclaw__")) | .tool' "$TRACE" \
  | sort | uniq -c | sort -rn \
  | awk '{printf "| %-40s | %5d |\n", $2, $1}')
if [ -z "$MCP_OPENCLAW_BREAKDOWN" ]; then
  MCP_OPENCLAW_BREAKDOWN="| _no mcp__openclaw__ calls — under-leveraging OpenClaw MCP_ | 0 |"
fi
SKILL_OPENCLAW_COUNT=$(jq -r 'select(.tool == "Skill" and ((.class // "") | test("openclaw-skills"))) | 1' "$TRACE" | wc -l | tr -d ' ')
SKILL_OPENCLAW_BREAKDOWN=$(jq -r 'select(.tool == "Skill" and ((.class // "") | test("openclaw-skills"))) | .class' "$TRACE" \
  | sort | uniq -c | sort -rn \
  | awk '{printf "| %-40s | %5d |\n", $2, $1}')
if [ -z "$SKILL_OPENCLAW_BREAKDOWN" ]; then
  SKILL_OPENCLAW_BREAKDOWN="| _no openclaw-skills invoked_ | 0 |"
fi

# --- New signals threading in outside-the-trace context ---

# Pruning candidates (top 10 coldest)
PRUNING_FILE="$WORKSPACE/state/pruning-candidates.jsonl"
PRUNING_ROWS_COUNT=0
if [ ! -f "$PRUNING_FILE" ]; then
  PRUNING_SECTION="| _pruning-candidates.jsonl missing — weekly cron has not run yet (next: Fri 16:45 UTC)_ |  |  |  |  |"
elif [ ! -s "$PRUNING_FILE" ]; then
  PRUNING_SECTION="| _pruning-candidates.jsonl empty — cron ran, zero files flagged by the heat × centrality × age filter_ |  |  |  |  |"
else
  PRUNING_ROWS_COUNT=$(wc -l < "$PRUNING_FILE" | tr -d ' ')
  PRUNING_SECTION=$(jq -r 'select(.path != null)
    | [(.heat // 0), .path, (.centrality_fan_in // 0), (.centrality_fan_out // 0), (.git_age_days // 0), ((.reasons // []) | join(","))] | @tsv' "$PRUNING_FILE" \
    | sort -k1,1n | head -10 \
    | awk -F'\t' '{printf "| %s | %s | %s | %s | %s |\n", $2, $1, $3, $5, $6}')
  if [ -z "$PRUNING_SECTION" ]; then
    PRUNING_SECTION="| _pruning-candidates.jsonl present but unparsable — check file format_ |  |  |  |  |"
  fi
fi

# Mistakes tail (last 30 lines)
MISTAKES_FILE="$WORKSPACE/reports/mistakes.md"
if [ -f "$MISTAKES_FILE" ] && [ -s "$MISTAKES_FILE" ]; then
  MISTAKES_SECTION=$(tail -n 30 "$MISTAKES_FILE")
  MISTAKES_LOADED=1
else
  MISTAKES_SECTION="_no mistakes.md_"
  MISTAKES_LOADED=0
fi

# Learnings tail (last 30 lines)
LEARNINGS_FILE="$WORKSPACE/reports/learnings.md"
if [ -f "$LEARNINGS_FILE" ] && [ -s "$LEARNINGS_FILE" ]; then
  LEARNINGS_SECTION=$(tail -n 30 "$LEARNINGS_FILE")
  LEARNINGS_LOADED=1
else
  LEARNINGS_SECTION="_no learnings.md_"
  LEARNINGS_LOADED=0
fi

# Trace summary (optional helper script)
TRACE_SUMMARY_SCRIPT="$WORKSPACE/scripts/trace-summary.sh"
TRACE_SUMMARY_INVOKED=0
if [ -x "$TRACE_SUMMARY_SCRIPT" ]; then
  TRACE_SUMMARY_INVOKED=1
  TRACE_SUMMARY_STDERR=$(mktemp)
  TRACE_SUMMARY_OUT=$("$TRACE_SUMMARY_SCRIPT" "$DATE" 2>"$TRACE_SUMMARY_STDERR")
  TRACE_SUMMARY_RC=$?
  if [ "$TRACE_SUMMARY_RC" -ne 0 ]; then
    TRACE_SUMMARY_SECTION="_warning: trace-summary.sh exited non-zero_"$'\n'"$(cat "$TRACE_SUMMARY_STDERR")"
  else
    TRACE_SUMMARY_SECTION="$TRACE_SUMMARY_OUT"
  fi
  rm -f "$TRACE_SUMMARY_STDERR"
else
  TRACE_SUMMARY_SECTION="_trace-summary.sh not available_"
fi

# Signals read — compute from actual file state at runtime
SIGNAL_TRACE="\`traces/$DATE.jsonl\` — loaded ($TOTAL rows)"
if [ -f "$TURNS_FILE" ] && [ -s "$TURNS_FILE" ]; then
  TURN_ROWS=$(wc -l < "$TURNS_FILE" | tr -d ' ')
  SIGNAL_TURNS="\`turns/$DATE.jsonl\` — loaded ($TURN_ROWS rows)"
else
  SIGNAL_TURNS="\`turns/$DATE.jsonl\` — _missing_"
fi
if [ -f "$PRUNING_FILE" ] && [ -s "$PRUNING_FILE" ]; then
  SIGNAL_PRUNING="\`state/pruning-candidates.jsonl\` — loaded ($PRUNING_ROWS_COUNT rows)"
else
  SIGNAL_PRUNING="\`state/pruning-candidates.jsonl\` — _missing_"
fi
if [ "$MISTAKES_LOADED" -eq 1 ]; then
  SIGNAL_MISTAKES="\`reports/mistakes.md\` — loaded"
else
  SIGNAL_MISTAKES="\`reports/mistakes.md\` — _missing_"
fi
if [ "$LEARNINGS_LOADED" -eq 1 ]; then
  SIGNAL_LEARNINGS="\`reports/learnings.md\` — loaded"
else
  SIGNAL_LEARNINGS="\`reports/learnings.md\` — _missing_"
fi
if [ "$TRACE_SUMMARY_INVOKED" -eq 1 ]; then
  SIGNAL_TRACE_SUMMARY="\`scripts/trace-summary.sh\` — invoked"
else
  SIGNAL_TRACE_SUMMARY="\`scripts/trace-summary.sh\` — _not available_"
fi

cat > "$OUT" <<EOF
# Reflect — $DATE

_Generated: $(date -u +"%Y-%m-%d %H:%M:%SZ") by \`scripts/reflect.sh\`._
_SEPL step 1/5. Deterministic signal only; hypotheses are human-filled for now._

## Signals read

- $SIGNAL_TRACE
- $SIGNAL_TURNS
- $SIGNAL_PRUNING
- $SIGNAL_MISTAKES
- $SIGNAL_LEARNINGS
- $SIGNAL_TRACE_SUMMARY

## Volume
- **Total tool invocations:** $TOTAL
- **Distinct sessions:** $SESSIONS
- **Success:** $SUCCESS ($SUCCESS_PCT)
- **Failures:** $FAILURES

## Tool breakdown

| Tool                 | Count |
|----------------------|-------|
$TOOL_BREAKDOWN

## Bin breakdown (semantic intent)

| Bin              | Count |    %   |
|------------------|-------|--------|
$BIN_BREAKDOWN

## Trace source breakdown (session context origin)

_Heartbeats fire into the main session and read as \`conversation\` — narrower detection is deferred. Missing \`source\` field → \`unknown\`._

| Source         | Count |    %   |
|----------------|-------|--------|
$SOURCE_BREAKDOWN

## Cost ($DATE)

$COST_SECTION

**Top 5 most expensive turns (token-burn candidates):**

| Cost | Time (UTC) | Tools | Output tokens |
|------|------------|-------|---------------|
$TOP_COST

## Top 15 (tool × class)

| Tool                 | Class                | Count |
|----------------------|----------------------|-------|
$CLASS_BREAKDOWN

## Duration (ms, per tool)

| Tool                 | n     | p50    | p95    |
|----------------------|-------|--------|--------|
$DURATION_STATS

## Repeated input_hashes (≥3× — deterministic-conversion candidates)

| Count | Hash         | Tool                 | Class |
|-------|--------------|----------------------|-------|
$REPEATS

## Failures

$FAIL_ROWS

## Session attribution (top 10 by invocations)

| Session    | Invocations |
|------------|-------------|
$SESSION_ATTR

**Top 5 sessions by turn cost:**

| Session    | Turns | Cost |
|------------|-------|------|
$SESSION_COST

## Tool sequence pairs (adjacent same-session, ≥3×)

| Count | Pair (tool:class → tool:class) |
|-------|--------------------------------|
$SEQ_PAIRS

## Cross-day delta

$DELTA_SECTION

## Behavioral habits (system-prompt violation counts)

$HABITS_SECTION

## OpenClaw primitive usage

_Are we leveraging OpenClaw as intended? Zero use ≠ fine — means CC-native habits are winning when an OpenClaw primitive was appropriate._

**MCP tools (\`mcp__openclaw__*\`):** $MCP_OPENCLAW_COUNT invocations

| Tool                                     | Count |
|------------------------------------------|-------|
$MCP_OPENCLAW_BREAKDOWN

**OpenClaw skills (\`openclaw-skills:*\`):** $SKILL_OPENCLAW_COUNT invocations

| Skill                                    | Count |
|------------------------------------------|-------|
$SKILL_OPENCLAW_BREAKDOWN

## Pruning candidates (top 10 coldest, via state/pruning-candidates.jsonl)

| Path | Heat | Fan-in | Stale (days) | Reasons |
|------|------|--------|--------------|---------|
$PRUNING_SECTION

## Mistakes (tail 30 from reports/mistakes.md)

$MISTAKES_SECTION

## Learnings (tail 30 from reports/learnings.md)

$LEARNINGS_SECTION

## Trace summary (scripts/trace-summary.sh $DATE)

\`\`\`
$TRACE_SUMMARY_SECTION
\`\`\`

## Active backlog

| ID | Status | Priority | Title |
|----|--------|----------|-------|
$BACKLOG_SECTION

### Backlog drift (open items with resolution evidence)

\`\`\`
$BACKLOG_DRIFT_SECTION
\`\`\`

_Run \`scripts/backlog-reconcile.sh --apply\` to auto-close matched items._

---

## Review

Human-filled hypotheses + next-step candidates live in a sidecar file so that re-running \`scripts/reflect.sh\` (which regenerates this file in place) does not clobber review work. See: \`reports/reflect-$DATE-review.md\`.

- **Status:** $REVIEW_STATUS
- **File:** \`$(basename "$REVIEW_FILE")\`

$REVIEW_PREVIEW

EOF

echo "Wrote $OUT"
echo "---"
head -30 "$OUT"

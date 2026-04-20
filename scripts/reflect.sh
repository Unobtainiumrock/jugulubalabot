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

cat > "$OUT" <<EOF
# Reflect — $DATE

_Generated: $(date -u +"%Y-%m-%d %H:%M:%SZ") by \`scripts/reflect.sh\`._
_SEPL step 1/5. Deterministic signal only; hypotheses are human-filled for now._

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

## Active backlog

| ID | Status | Priority | Title |
|----|--------|----------|-------|
$BACKLOG_SECTION

---

## Hypotheses (fill in manually — Track 3 will LLM-ify this)

1. _What's the most expensive repeated pattern today? (Candidate for skill/script conversion.)_
2. _What failed that shouldn't have? (Candidate for new eval fixture.)_
3. _What's the cheapest win — 10 min of work that removes friction repeating ≥3× weekly?_

## Next-step candidates

- [ ] _New eval fixture from failure row #___
- [ ] _Convert input_hash \`<hash>\` to deterministic skill/script_
- [ ] _Tighten SOUL.md / TOOLS.md rule: ___

EOF

echo "Wrote $OUT"
echo "---"
head -30 "$OUT"

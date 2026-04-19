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

# Repeated input_hashes (≥3x = deterministic-conversion candidate)
REPEATS=$(jq -r '[.tool, .class // "—", .input_hash] | @tsv' "$TRACE" \
  | sort | uniq -c | sort -rn \
  | awk '$1 >= 3 {printf "| %5d | %-12s | %-20s | %s |\n", $1, $4, $2, $3}' \
  | head -10)
if [ -z "$REPEATS" ]; then
  REPEATS="| _none — no input_hash repeated ≥3× today_ |  |  |  |"
fi

# Failure rows (full JSON, one per line, capped)
FAIL_ROWS=$(jq -c 'select(.success == false) | {ts, tool, class, duration_ms, session_id}' "$TRACE" | head -20)
if [ -z "$FAIL_ROWS" ]; then
  FAIL_ROWS="_no failures today — either Tai got lucky or graders are too lax_"
fi

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

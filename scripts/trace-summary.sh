#!/usr/bin/env bash
# Daily trace rollup. Prints counts per tool, class, success rate, p50/p95 duration.
# Usage: trace-summary.sh [YYYY-MM-DD]   (defaults to today UTC)
set -euo pipefail

DATE="${1:-$(date -u +%Y-%m-%d)}"
FILE="/root/.openclaw/workspace/traces/$DATE.jsonl"

if [ ! -f "$FILE" ] || [ ! -s "$FILE" ]; then
  echo "no traces for $DATE"
  exit 0
fi

TOTAL=$(wc -l < "$FILE")
echo "== $DATE: $TOTAL invocations =="
echo

echo "-- by tool --"
jq -r '.tool' "$FILE" | sort | uniq -c | sort -rn

echo
echo "-- by tool/class (top 20) --"
jq -r '[.tool, (.class // "-")] | @tsv' "$FILE" \
  | sort | uniq -c | sort -rn | head -20

echo
echo "-- success rate by tool --"
jq -r '[.tool, (.success|tostring)] | @tsv' "$FILE" \
  | awk -F'\t' '{t[$1]++; if($2=="true")s[$1]++} END {for(k in t) printf "  %-12s %d/%d (%.1f%%)\n", k, s[k]+0, t[k], 100*(s[k]+0)/t[k]}' \
  | sort

echo
echo "-- duration ms (p50/p95) by tool --"
for tool in $(jq -r '.tool' "$FILE" | sort -u); do
  jq -r --arg t "$tool" 'select(.tool==$t and .duration_ms!=null) | .duration_ms' "$FILE" \
    | sort -n \
    | awk -v tool="$tool" '{a[NR]=$1} END {
        if (NR==0) exit;
        p50=a[int(NR*0.5)+1]; if(p50=="") p50=a[NR];
        p95=a[int(NR*0.95)+1]; if(p95=="") p95=a[NR];
        printf "  %-12s n=%d  p50=%dms  p95=%dms\n", tool, NR, p50, p95
      }'
done

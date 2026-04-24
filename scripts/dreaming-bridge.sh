#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="/root/.openclaw/workspace"
STORE="$WORKSPACE/memory/.dreams/short-term-recall.json"
OUT_DIR="$WORKSPACE/reports"
DATE="${1:-$(date -u +%F)}"
OUT="$OUT_DIR/dreaming-bridge-$DATE.md"
mkdir -p "$OUT_DIR"

if [ ! -f "$STORE" ] || [ ! -s "$STORE" ]; then
  cat > "$OUT" <<MARKDOWN
# Dreaming Bridge — $DATE

_No dreaming short-term recall store found at \
\`memory/.dreams/short-term-recall.json\`._
MARKDOWN
  echo "Dreaming-bridge [NO] — no recall store"
  exit 0
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

jq -r '
  .entries
  | to_entries
  | map(.value + {
      recallDaysCount: ((.recallDays // []) | length),
      conceptTagsText: ((.conceptTags // []) | join(", "))
    })
  | map(select((.recallCount // 0) >= 3 and (.recallDaysCount // 0) >= 2))
  | sort_by(-(.recallCount // 0), -(.recallDaysCount // 0), -(.totalScore // 0))
  | .[0:5]
  | .[]
  | [
      (.path // ""),
      ((.startLine // 0) | tostring),
      ((.endLine // 0) | tostring),
      ((.recallCount // 0) | tostring),
      ((.recallDaysCount // 0) | tostring),
      (.conceptTagsText // ""),
      (((.snippet // "") | gsub("[\n\r\t]"; " ") | .[0:220]))
    ]
  | @tsv
' "$STORE" > "$TMP"

if [ ! -s "$TMP" ]; then
  cat > "$OUT" <<MARKDOWN
# Dreaming Bridge — $DATE

_No convergent recall candidates yet (threshold: recallCount >= 3 and recallDays >= 2)._ 
MARKDOWN
  echo "Dreaming-bridge [NO] — no convergent recall candidates"
  exit 0
fi

recommendation_for() {
  local text="$1"
  if echo "$text" | grep -qiE 'guard|hook|heartbeat|budget|reflex|session-clean|mkscript'; then
    echo enforcement
  elif echo "$text" | grep -qiE 'eval|fixture|grader|benchmark|test|harness'; then
    echo eval
  elif echo "$text" | grep -qiE 'reflect|review|select|report|backlog|workflow'; then
    echo workflow
  else
    echo memory
  fi
}

rows=""
actionable=0
first_path=""
first_rec=""
while IFS=$'\t' read -r path start end recall days tags snippet; do
  text="$tags $snippet $path"
  rec=$(recommendation_for "$text")
  [ -z "$first_path" ] && first_path="$path:$start-$end" && first_rec="$rec"
  [ "$rec" != "memory" ] && actionable=$((actionable + 1))
  rows+="| ${path}:${start}-${end} | $recall | $days | $rec | ${tags:-_none_} | ${snippet:-_none_} |"$'\n'
done < "$TMP"

total=$(wc -l < "$TMP" | tr -d ' ')
status="NO"
summary="Dreaming has convergent recall, but no obvious self-evolution overlap yet."
if [ "$actionable" -gt 0 ]; then
  status="YES"
  summary="Convergent dreaming signals overlap with the self-evolving loop; top candidate should feed Reflect/Improve rather than stay memory-only."
fi

cat > "$OUT" <<MARKDOWN
# Dreaming Bridge — $DATE

_Human-readable bridge from dreaming short-term recall into the self-evolving loop._

## Summary

- Convergent candidates: $total
- Actionable self-evolution overlap: $actionable

**Assessment:** $summary

## Top convergent recall candidates

| Source | Recall count | Recall days | Recommended lane | Concept tags | Snippet |
|--------|--------------|-------------|------------------|--------------|---------|
$rows

## Guidance

- `enforcement`: prefer hook / guard / heartbeat / lifecycle changes.
- `eval`: prefer fixture, benchmark, grader, or harness coverage.
- `workflow`: prefer reflect/select/review/backlog/reporting cleanup.
- `memory`: keep watching; no clear self-evolution action yet.
MARKDOWN

echo "Dreaming-bridge [$status] — candidates=$total actionable=$actionable top=${first_path:-none} lane=${first_rec:-none}"

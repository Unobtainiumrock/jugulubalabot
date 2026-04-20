#!/usr/bin/env bash
# Layer 1 of the pruning signal: file-level usage heat.
# Decays prior heat by 0.95 (half-life ~14d), then adds today's touches.
# Reads traces/<DATE>.jsonl (default yesterday), writes state/file-heat.jsonl.
# Silent on success; prints a one-line summary on stderr.
set -euo pipefail

WORKSPACE="${WORKSPACE:-/root/.openclaw/workspace}"
STATE_DIR="$WORKSPACE/state"
TRACE_DIR="$WORKSPACE/traces"
HEAT_FILE="$STATE_DIR/file-heat.jsonl"
META_FILE="$STATE_DIR/file-heat.meta.json"
DATE="${1:-$(date -u -d 'yesterday' +%F)}"
TRACE="$TRACE_DIR/$DATE.jsonl"

mkdir -p "$STATE_DIR"
[ -f "$HEAT_FILE" ] || : > "$HEAT_FILE"
[ -f "$TRACE"     ] || { echo "heat-counter: no trace file for $DATE" >&2; exit 0; }

# Idempotency: skip if this date already processed.
LAST=$(jq -r '.last_processed // ""' "$META_FILE" 2>/dev/null || echo "")
if [ "$LAST" = "$DATE" ]; then
  echo "heat-counter: $DATE already processed" >&2
  exit 0
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# today_touches[path] = count of trace rows whose .paths contained the path.
# Only count rows whose .paths array is non-empty.
TOUCHES=$(jq -s -c '
  [ .[] | .paths // [] | .[] | select(. != null and . != "") ]
  | group_by(.) | map({path: .[0], n: length})
' "$TRACE")

# Merge prior heat (decayed) with today's touches.
jq -c -n \
  --argjson today "$TOUCHES" \
  --arg date "$DATE" \
  --slurpfile prior "$HEAT_FILE" '
  def decay: 0.95;
  ( $prior | map({(.path): .}) | add // {} ) as $P
  | ( $today | map({(.path): .n}) | add // {} ) as $T
  | ( ($P | keys) + ($T | keys) | unique ) as $all
  | $all
  | map(
      . as $p
      | ($P[$p] // {path:$p, heat:0, touches_total:0, last_touched:null}) as $prev
      | ($T[$p] // 0) as $today_n
      | {
          path: $p,
          heat: ((($prev.heat // 0) * decay) + $today_n),
          touches_total: (($prev.touches_total // 0) + $today_n),
          last_touched: (if $today_n > 0 then $date else $prev.last_touched end)
        }
    )
  | sort_by(-.heat)
  | .[]
' > "$TMP"

mv "$TMP" "$HEAT_FILE"
printf '{"last_processed":"%s","generated":"%s"}\n' "$DATE" "$(date -u +%FT%TZ)" > "$META_FILE"

ROWS=$(wc -l < "$HEAT_FILE")
echo "heat-counter: $DATE processed, $ROWS tracked files" >&2

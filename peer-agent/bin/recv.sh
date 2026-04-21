#!/usr/bin/env bash
# Ingest unprocessed inbox replies. Redacts, appends to transcript.jsonl,
# emits clean bodies (delimited by "---") for Tai to read.
set -euo pipefail
LANE="/root/.openclaw/workspace/peer-agent"
mkdir -p "$LANE/inbox" "$LANE/inbox-processed"
TS=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
shopt -s nullglob
for f in "$LANE/inbox"/*.txt; do
  RAW=$(cat "$f")
  REDACTED=$(printf '%s' "$RAW" | bash "$LANE/bin/redact.sh")
  CLEAN=$(jq -r '.clean' <<< "$REDACTED")
  STRIPPED=$(jq -c '.stripped' <<< "$REDACTED")
  jq -cn --arg ts "$TS" --arg dir "recv" --arg body "$CLEAN" \
         --arg path "$f" --argjson stripped "$STRIPPED" \
    '{ts:$ts, direction:$dir, body:$body, file:$path, stripped:$stripped}' \
    >> "$LANE/transcript.jsonl"
  if [ "$(jq 'length' <<< "$STRIPPED")" -gt 0 ]; then
    jq -cn --arg ts "$TS" --arg path "$f" --argjson items "$STRIPPED" \
      '{ts:$ts, file:$path, items:$items}' >> "$LANE/redaction-log.jsonl"
  fi
  mv "$f" "$LANE/inbox-processed/"
  printf '%s\n---\n' "$CLEAN"
done

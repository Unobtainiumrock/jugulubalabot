#!/usr/bin/env bash
# user-prompt-recall — UserPromptSubmit hook that surfaces relevant prior
# mistakes / feedback memories before the model formulates its response.
# Non-blocking by design: emits additionalContext only.
#
# Companion to pre-action-recall.sh, which catches tool-input-shaped
# patterns. This hook catches user-message-shaped patterns (e.g. leading
# questions, abstract option asks) that never reach a tool call and
# therefore never trigger the PreToolUse surface.
#
# Index: state/recall-index.tsv (shared with pre-action-recall.sh).
# Format: <pattern>\t<kind>\t<source>\t<rule>
#
# Per-session dedup: state/recall-fired-prompt.txt. Reset by
# session-clean.sh at SessionStart so reflexes re-fire each session.
#
# Kill switches:
#   - state/.recall-off            session-wide bypass (shared)
#
# Budget: <50ms target. Always exit 0.

set -uo pipefail
WORKSPACE="/root/.openclaw/workspace"
INDEX="$WORKSPACE/state/recall-index.tsv"
FIRED="$WORKSPACE/state/recall-fired-prompt.txt"
LOG="$WORKSPACE/state/recall-log.jsonl"

trap 'echo "{}"; exit 0' ERR

[ -f "$WORKSPACE/state/.recall-off" ] && { echo "{}"; exit 0; }
[ ! -s "$INDEX" ] && { echo "{}"; exit 0; }

INPUT=$(cat)
PROMPT=$(jq -r '.prompt // ""' <<< "$INPUT" 2>/dev/null)
[ -z "$PROMPT" ] && { echo "{}"; exit 0; }

# Truncate to first 2KB — patterns are short, no need to scan long pastes.
PROMPT_LC=$(printf '%s' "${PROMPT:0:2000}" | tr '[:upper:]' '[:lower:]')

mkdir -p "$(dirname "$FIRED")" 2>/dev/null
touch "$FIRED" 2>/dev/null
HITS_FILE=$(mktemp 2>/dev/null) || { echo "{}"; exit 0; }
HIT_COUNT=0

while IFS=$'\t' read -r pattern kind source rule; do
  [ -z "$pattern" ] && continue
  PAT_LC=$(printf '%s' "$pattern" | tr '[:upper:]' '[:lower:]')
  case "$PROMPT_LC" in
    *"$PAT_LC"*)
      HASH=$(printf '%s' "$pattern" | md5sum | cut -c1-16)
      if grep -qF "$HASH" "$FIRED" 2>/dev/null; then
        continue
      fi
      printf '%s\t%s\t%s\t%s\n' "$kind" "$source" "$rule" "$HASH" >> "$HITS_FILE"
      HIT_COUNT=$((HIT_COUNT + 1))
      [ "$HIT_COUNT" -ge 2 ] && break
      ;;
  esac
done < "$INDEX"

if [ "$HIT_COUNT" -eq 0 ]; then
  rm -f "$HITS_FILE"
  echo "{}"; exit 0
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
MSG="RECALL — prior signal matches this prompt:"
while IFS=$'\t' read -r kind source rule hash; do
  MSG=$(printf '%s\n  · [%s] %s — %s' "$MSG" "$kind" "$source" "$rule")
  echo "$hash" >> "$FIRED" 2>/dev/null
  printf '{"ts":"%s","tool":"UserPrompt","kind":%s,"source":%s,"rule":%s}\n' \
    "$TS" \
    "$(jq -Rc . <<< "$kind")" \
    "$(jq -Rc . <<< "$source")" \
    "$(jq -Rc . <<< "$rule")" \
    >> "$LOG" 2>/dev/null || true
done < "$HITS_FILE"
rm -f "$HITS_FILE"

jq -n --arg msg "$MSG" '{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": $msg}}'
exit 0

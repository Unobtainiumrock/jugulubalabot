#!/usr/bin/env bash
# UserPromptSubmit hook for capability/wake/schedule questions.
# Injects a two-layer answer scaffold only for the narrow prompt shape that
# keeps tripping the Claude-Code-only reflex.

set -uo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
PROMPT=$(jq -r '.prompt // ""' <<< "$INPUT" 2>/dev/null)
[ -z "$PROMPT" ] && { echo "{}"; exit 0; }

PROMPT_LC=$(printf '%s' "${PROMPT:0:2000}" | tr '[:upper:]' '[:lower:]')

HIT=""
for pat in \
  "any built-in way to wake" \
  "any built-in way to schedule" \
  "wake up a session on a schedule" \
  "wake up a session" \
  "or is it just you reacting" \
  "just you reacting to my messages"
do
  case "$PROMPT_LC" in
    *"$pat"*) HIT=1; break ;;
  esac
done

[ -z "$HIT" ] && { echo "{}"; exit 0; }

MSG="LAYER-CHECK reflex.

This is a capability question with two different answers by layer. Answer with this exact structure:

At the Claude Code layer: <native CC answer>.
At the OpenClaw layer: <OpenClaw answer naming at least one of cron, gateway, HEARTBEAT.md, scheduled agent turn, mcp__openclaw__cron>.

Then add one reconciliation line that says whether the capability exists overall.

Forbidden opening shape: 'no, there isn't', 'nope', 'just me reacting', or any answer that names mechanisms without the two explicit layer labels."

jq -n --arg msg "$MSG" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'

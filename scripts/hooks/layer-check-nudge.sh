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

MSG="LAYER-CHECK reflex — capability/wake/schedule question.

Frame each layer in terms of what EXISTS, never what is absent. The CC layer is not 'no built-in scheduler' — it is the set of CC-native primitives plus their scope. Use this exact template, in this exact order:

  At the Claude Code layer: \`ScheduleWakeup\` re-fires the current turn after a delay; \`/loop\` runs cadenced within a session. Scope: in-session only — these fire while CC is awake.
  At the OpenClaw layer: \`mcp__openclaw__cron\` (CronCreate/CronList/CronDelete) registers scheduled agent turns via the gateway; \`HEARTBEAT.md\` carries recurring nudges that scheduled turns read on wake.
  Overall: real cron exists — OpenClaw adds an out-of-session scheduler on top of CC's in-session-only primitives.

You may rewrite the prose, but the contract is:
  1. First line begins literally \`At the Claude Code layer:\` and names \`ScheduleWakeup\` and \`/loop\` by symbol — enumerated presence, not absence.
  2. Second line begins literally \`At the OpenClaw layer:\` and names at least one of \`mcp__openclaw__cron\`, \`cron\`, \`gateway\`, \`scheduled agent turn\`, \`HEARTBEAT.md\`.
  3. Third line begins literally \`Overall:\` and names whether the capability exists overall.

Forbidden substrings anywhere in the reply (these are the failure-mode phrasings — pick a presence-framed alternative): \`no built-in\`, \`no built in\`, \`no such\`, \`doesn't exist\`, \`no way to\`, \`there isn't\`, \`there is no\`, \`nope\`, \`just me reacting\`, \`I just react\`, \`I only react\`. If you would have written \`no built-in scheduler\`, write \`in-session only\` or \`reactive — fires only while CC is awake\` instead. The scope qualifier IS the CC-layer answer; the absence framing is the failure mode this hook exists to catch."

jq -n --arg msg "$MSG" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'

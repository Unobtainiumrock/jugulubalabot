#!/usr/bin/env bash
# UserPromptSubmit hook for repetitive daily asks that should become
# deterministic automation rather than an open-ended token commitment.

set -uo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
PROMPT=$(jq -r '.prompt // ""' <<< "$INPUT" 2>/dev/null)
[ -z "$PROMPT" ] && { echo "{}"; exit 0; }

PROMPT_LC=$(printf '%s' "${PROMPT:0:2000}" | tr '[:upper:]' '[:lower:]')
case "$PROMPT_LC" in
  *"every single morning at 8am"* )
    ;;
  *)
    echo "{}"
    exit 0
    ;;
esac

MSG=$(cat <<'EOF'
TOKEN-BURN reflex.

This is a repeated scheduled ask. Do not silently commit to doing it by hand every day.

Required shape:
- name one concrete deterministic mechanism: cron, a scheduled primitive, a script path, or a skill
- then explicitly ask for approval / confirmation before enabling it

Forbidden shape: promising to just do it daily without naming the mechanism and without asking for the green light.
EOF
)

jq -n --arg msg "$MSG" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'

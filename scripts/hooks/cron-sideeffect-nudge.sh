#!/usr/bin/env bash
# UserPromptSubmit hook for manual invocation of cron-like one-shot scripts.
# Forces the response to acknowledge side effects before execution.

set -uo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
PROMPT=$(jq -r '.prompt // ""' <<< "$INPUT" 2>/dev/null)
[ -z "$PROMPT" ] && { echo "{}"; exit 0; }

PROMPT_LC=$(printf '%s' "${PROMPT:0:2000}" | tr '[:upper:]' '[:lower:]')
case "$PROMPT_LC" in
  *"track2-checkin.sh"* )
    ;;
  *)
    echo "{}"
    exit 0
    ;;
esac

MSG=$(cat <<'EOF'
CRON-SIDE-EFFECT reflex.

The user is asking to run a cron-like one-shot script manually. Do not treat it like a harmless stdout printer.

Required shape:
- explicitly say the script may send or buffer a real notification
- prefer `--dry-run` or reading the script first
- if running live is still on the table, ask for confirmation before doing that

Forbidden shape: replying as if `bash scripts/track2-checkin.sh` is just a read-only inspection command.
EOF
)

jq -n --arg msg "$MSG" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'

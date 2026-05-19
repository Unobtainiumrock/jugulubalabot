#!/usr/bin/env bash
# UserPromptSubmit hook for mechanical infra-recovery prompts.
# Pushes the answer toward a concrete next-steps sequence instead of
# bouncing the choice back to the user.

set -uo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
PROMPT=$(jq -r '.prompt // ""' <<< "$INPUT" 2>/dev/null)
[ -z "$PROMPT" ] && { echo "{}"; exit 0; }

PROMPT_LC=$(printf '%s' "${PROMPT:0:2000}" | tr '[:upper:]' '[:lower:]')

case "$PROMPT_LC" in
  *"permission denied (publickey)"*"next 3 concrete actions"* )
    ;;
  *)
    echo "{}"
    exit 0
    ;;
esac

MSG=$(cat <<'EOF'
INFRA-LOOP reflex.

This is a mechanical recovery prompt, not a menu prompt. Reply with 3 concrete actions in order that continue the work without asking the user to choose a path first.

Required content:
- action 1 diagnoses the current auth path (`git remote -v`, existing SSH keys, `gh auth status` or equivalent)
- action 2 creates or installs the missing credential path (`ssh-keygen`, HTTPS+PAT, or tool install) as an execution step, not an option list
- action 3 retries the push or prepares the exact external dependency that remains

Forbidden shape: 'which option do you prefer', 'how would you like me to proceed', 'before I continue', or any answer that presents paths without committing to the next action sequence.
EOF
)

jq -n --arg msg "$MSG" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$msg}}'

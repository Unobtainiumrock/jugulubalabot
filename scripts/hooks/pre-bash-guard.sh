#!/usr/bin/env bash
# Pre-Bash guard hook. Fires before every Bash tool call, reads the tool
# input from stdin, and blocks the call when the command matches a known
# system-prompt anti-pattern. The block includes a teaching message so
# Claude re-invokes correctly.
#
# Fail-safe: internal errors cause the hook to exit 0 (allow) rather
# than brick the session. A buggy guard is noisy, not blocking.
#
# Kill switches:
#   - `OPENCLAW_GUARD_OFF=1 <cmd>`          per-call bypass
#   - `touch state/.guard-off`              session-wide bypass
#
# Budget: <20ms. Pure bash + one jq call. No network, no disk writes
# on the allow path.

WORKSPACE="/root/.openclaw/workspace"
LOG="$WORKSPACE/state/guard-log.jsonl"

# Fail-safe trap: any unexpected error → allow + log.
trap 'echo "{}"; exit 0' ERR

# Session kill switch
if [ -f "$WORKSPACE/state/.guard-off" ]; then
  exit 0
fi

INPUT=$(cat)
CMD=$(jq -r '.tool_input.command // ""' <<< "$INPUT" 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Per-call kill switch embedded in the command
if [[ "$CMD" == *"OPENCLAW_GUARD_OFF=1"* ]]; then
  exit 0
fi

REASON=""

# --- Pattern 1: cd to known workspace cwd ---
if [[ "$CMD" =~ ^[[:space:]]*cd[[:space:]]+/root/\.openclaw/workspace(/|[[:space:]]|$) ]]; then
  REASON="Bash cwd persists across calls — you're already in /root/.openclaw/workspace. Drop the 'cd ... &&' prefix. Use absolute paths in the command itself, or 'git -C <path>' for explicit dir. (Override: OPENCLAW_GUARD_OFF=1)"

# --- Pattern 2: cd <anything> && git ---
elif [[ "$CMD" =~ ^[[:space:]]*cd[[:space:]]+[^[:space:]]+[[:space:]]*\&\&[[:space:]]*git[[:space:]] ]]; then
  REASON="Use 'git -C <path> <subcommand>' instead of 'cd <path> && git <subcommand>'. The -C flag is native and doesn't mutate cwd. (Override: OPENCLAW_GUARD_OFF=1)"

# --- Pattern 3: bare cat <file> (no pipe, no redirect, no heredoc) ---
elif [[ "$CMD" =~ ^[[:space:]]*cat[[:space:]]+[^|\<\>\&\;]+$ ]] && [[ ! "$CMD" =~ \<\<|\<\<\< ]]; then
  REASON="Use the Read tool instead of 'cat <file>'. Read gives line numbers and respects file-read tracking. (Override: OPENCLAW_GUARD_OFF=1)"

# --- Pattern 4: bare head/tail <file> (no pipe, no stdin) ---
elif [[ "$CMD" =~ ^[[:space:]]*(head|tail)[[:space:]]+([-+][0-9]+[[:space:]]+)?[^|\<\>\&\;]+$ ]]; then
  REASON="Use the Read tool with offset/limit instead of 'head'/'tail'. (Override: OPENCLAW_GUARD_OFF=1)"

# --- Pattern 5: grep / rg as primary command (not in pipe) ---
elif [[ "$CMD" =~ ^[[:space:]]*(grep|rg|egrep|fgrep)[[:space:]] ]] && [[ ! "$CMD" =~ \| ]]; then
  REASON="Use the Grep tool instead of running 'grep'/'rg' via Bash. Grep tool is ripgrep under the hood with better permission handling. (Override: OPENCLAW_GUARD_OFF=1)"

# --- Pattern 6: find as primary command ---
elif [[ "$CMD" =~ ^[[:space:]]*find[[:space:]] ]] && [[ ! "$CMD" =~ \| ]]; then
  REASON="Use the Glob tool instead of 'find ... -name ...'. Glob is faster and respects workspace scoping. (Override: OPENCLAW_GUARD_OFF=1)"

# --- Pattern 7: bare echo "..." (no pipe, no redirect) ---
# Only flag if this is a top-level standalone echo, not echo inside a
# larger shell pipeline. Also allow 'echo' with command substitution
# since that's often part of a scripted workflow.
elif [[ "$CMD" =~ ^[[:space:]]*echo[[:space:]]+[\"\'] ]] && [[ ! "$CMD" =~ [\|\<\>\&\;] ]]; then
  REASON="Text output is already visible without 'echo'. Direct text output to the user instead of 'echo \"...\"'. (Override: OPENCLAW_GUARD_OFF=1)"

# --- Pattern 8: echo "..." > file (writing files via shell) ---
elif [[ "$CMD" =~ ^[[:space:]]*echo[[:space:]]+.+[[:space:]]*\>[[:space:]] ]]; then
  REASON="Use the Write tool instead of 'echo ... > file'. Write preserves newlines and formats reliably. (Override: OPENCLAW_GUARD_OFF=1)"

# --- Pattern 9: chmod +x / 0755 on a script path (Write:sh → chmod pair) ---
# Reflect-2026-04-21 surfaced this pair firing 7×/day despite the `mkscript`
# skill existing precisely to collapse it into one call. Nudge, don't block
# unknown paths — only catch the script-suffix case to avoid false positives
# on chmod of non-script files.
elif [[ "$CMD" =~ ^[[:space:]]*chmod[[:space:]]+(\+x|[0-7]{3,4})[[:space:]]+[^\|\&\;]*\.(sh|py|bash|zsh|rb|pl)([[:space:]]|$) ]]; then
  REASON="Use scripts/mkscript.sh to write-and-chmod in one call instead of Write followed by 'chmod +x'. Usage: bash scripts/mkscript.sh <path> <<'EOF' ... EOF. Surfaced in reflect-2026-04-21 as a 7×/day redundant pair. (Override: OPENCLAW_GUARD_OFF=1)"
fi

if [ -n "$REASON" ]; then
  # Log the block decision for audit
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  TS=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
  printf '{"ts":"%s","blocked":true,"cmd":%s,"reason":%s}\n' \
    "$TS" \
    "$(jq -Rc . <<< "$CMD" | head -c 400)" \
    "$(jq -Rc . <<< "$REASON")" \
    >> "$LOG" 2>/dev/null || true

  # Emit block decision to Claude
  jq -n --arg r "$REASON" '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": $r}}'
  exit 0
fi

exit 0

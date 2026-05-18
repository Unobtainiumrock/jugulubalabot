#!/usr/bin/env bash
set -euo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
PRINT_IS_SANDBOX="${IS_SANDBOX:-}"

if [ -z "$PRINT_IS_SANDBOX" ] && [ "$(id -u)" -eq 0 ]; then
  default_mode=$(jq -r '.permissions.defaultMode // empty' /root/.claude/settings.json 2>/dev/null || true)
  if [ "$default_mode" = "bypassPermissions" ]; then
    PRINT_IS_SANDBOX="1"
  fi
fi

exec env IS_SANDBOX="$PRINT_IS_SANDBOX" \
  "$CLAUDE_BIN" --print --permission-mode bypassPermissions "$@"

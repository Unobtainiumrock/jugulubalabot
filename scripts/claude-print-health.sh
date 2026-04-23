#!/usr/bin/env bash
set -euo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
TIMEOUT_SECS="${TIMEOUT_SECS:-8}"
AUTH_STATUS="unknown"
DNS_STATUS="unknown"
API_STATUS="unknown"
STATE_STATUS="unknown"
MODE_STATUS="unknown"
DETAILS=()
FAIL=0

run_timeout() {
  timeout "$TIMEOUT_SECS" "$@"
}

# Auth: use the existing saved Claude login if present.
if auth_json=$(run_timeout "$CLAUDE_BIN" auth status 2>/dev/null); then
  if printf '%s' "$auth_json" | jq -e '.loggedIn == true' >/dev/null 2>&1; then
    AUTH_STATUS="ok"
  else
    AUTH_STATUS="fail"
    FAIL=1
    DETAILS+=("auth: claude reports loggedOut")
  fi
else
  AUTH_STATUS="fail"
  FAIL=1
  DETAILS+=("auth: 'claude auth status' failed")
fi

# DNS: if this fails, claude -p will stall on network retries.
if timeout 5 getent hosts api.anthropic.com >/dev/null 2>&1; then
  DNS_STATUS="ok"
else
  DNS_STATUS="fail"
  FAIL=1
  DETAILS+=("dns: could not resolve api.anthropic.com")
fi

# HTTPS reachability: confirms we can actually open a socket to Anthropic.
if timeout 5 curl -sSI https://api.anthropic.com >/dev/null 2>&1; then
  API_STATUS="ok"
else
  API_STATUS="fail"
  FAIL=1
  DETAILS+=("api: HTTPS probe to api.anthropic.com failed")
fi

# Claude CLI still expects some writable state under ~/.claude even in print mode.
probe_file="/root/.claude/.health-write-$$"
if ( : > "$probe_file" ) 2>/dev/null; then
  rm -f "$probe_file" 2>/dev/null || true
  STATE_STATUS="ok"
else
  STATE_STATUS="readonly"
  FAIL=1
  DETAILS+=("state: /root/.claude is not writable from this runtime")
fi

# Root + defaultMode=bypassPermissions needs IS_SANDBOX=1 or claude -p refuses
# to start. This is a mode/config mismatch, not an auth/network issue.
default_mode=""
if [ -f "/root/.claude/settings.json" ]; then
  default_mode=$(jq -r '.permissions.defaultMode // empty' /root/.claude/settings.json 2>/dev/null || true)
fi
if [ "$(id -u)" -eq 0 ] && [ "$default_mode" = "bypassPermissions" ]; then
  if [ "${IS_SANDBOX:-0}" = "1" ]; then
    MODE_STATUS="ok"
  else
    MODE_STATUS="fail"
    FAIL=1
    DETAILS+=("mode: root + defaultMode=bypassPermissions requires IS_SANDBOX=1 for claude -p")
  fi
else
  MODE_STATUS="ok"
fi

if [ "$FAIL" -eq 0 ]; then
  printf 'Claude-print-health [OK] — auth=%s dns=%s api=%s state=%s mode=%s\n' \
    "$AUTH_STATUS" "$DNS_STATUS" "$API_STATUS" "$STATE_STATUS" "$MODE_STATUS"
  exit 0
fi

printf 'Claude-print-health [FAIL] — auth=%s dns=%s api=%s state=%s mode=%s\n' \
  "$AUTH_STATUS" "$DNS_STATUS" "$API_STATUS" "$STATE_STATUS" "$MODE_STATUS"
for detail in "${DETAILS[@]}"; do
  printf '%s\n' "$detail"
done
exit 1

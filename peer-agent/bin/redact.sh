#!/usr/bin/env bash
# Apply redaction rules. Stdin -> JSON {clean, stripped:[{name,count},...]}.
# Intentionally conservative: strip obvious PII + long tokens; names pass
# through (tighten later). Rules version tracked in config.json.
set -euo pipefail
RAW=$(cat)
CLEAN="$RAW"
STRIPPED="[]"

apply() {
  local name="$1" re="$2"
  local hits
  hits=$(printf '%s' "$CLEAN" | grep -cE "$re" 2>/dev/null || true)
  [ -z "$hits" ] && hits=0
  if [ "$hits" -gt 0 ]; then
    CLEAN=$(printf '%s' "$CLEAN" | sed -E "s|$re|[REDACTED:$name]|g")
    STRIPPED=$(jq -c --arg n "$name" --argjson c "$hits" '. + [{name:$n, count:$c}]' <<< "$STRIPPED")
  fi
}

# Order matters: specific before generic; long_token before phone so it
# doesn't eat the digit-run inside a key.
apply "email"            "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
apply "linkedin_profile" "linkedin\\.com/in/[A-Za-z0-9_-]+"
apply "long_token"       "[A-Za-z0-9_-]{32,}"
apply "phone"            "\\+?[0-9][0-9 .()-]{8,}[0-9]"

jq -cn --arg clean "$CLEAN" --argjson stripped "$STRIPPED" '{clean:$clean, stripped:$stripped}'

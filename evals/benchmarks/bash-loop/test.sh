#!/usr/bin/env bash
set -euo pipefail
OUT="$1"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
awk '
  BEGIN { in_block=0 }
  /^```bash\s*$/ { in_block=1; next }
  in_block && /^```\s*$/ { exit }
  in_block { print }
' "$OUT" > "$TMP"
if [ ! -s "$TMP" ]; then
  echo "bash-loop: missing bash code block" >&2
  exit 1
fi
actual=$(bash "$TMP")
expected=$'1\n2\n3\n4\n5'
[ "$actual" = "$expected" ]

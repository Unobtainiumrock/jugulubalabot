#!/usr/bin/env bash
set -euo pipefail
OUT="$1"
grep -qiE 'select|keep|filter' "$OUT"
grep -qiE 'tool|Bash' "$OUT"
grep -qiE 'class|git' "$OUT"
grep -qiE 'session_id|session id' "$OUT"
grep -qiE '(^|[^[:alnum:]_])ts([^[:alnum:]_]|$)|timestamp' "$OUT"

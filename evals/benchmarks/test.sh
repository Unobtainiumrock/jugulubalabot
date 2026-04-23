#!/usr/bin/env bash
set -euo pipefail
OUT="$1"
pattern=$(tr -d '\n' < "$OUT" | sed -E 's/^```[a-zA-Z]*//; s/```$//; s/^\s+//; s/\s+$//')
[ -n "$pattern" ]
printf '%s\n' '2026-04-23T10:00:00Z tool=Bash class=git status success=true' | grep -Eq "$pattern"
if printf '%s\n' '2026-04-23T10:00:00Z tool=Bash class=shell status success=true' | grep -Eq "$pattern"; then
  exit 1
fi
if printf '%s\n' '2026-04-23T10:00:00Z tool=Read class=md success=true' | grep -Eq "$pattern"; then
  exit 1
fi

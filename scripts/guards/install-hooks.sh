#!/usr/bin/env bash
# Idempotently install local git hooks that wrap tracked guard scripts.
# Writes into .git/hooks/ — that path is sensitive, so the harness gates
# direct edits; this tracked installer runs once on demand and converges.
#
# Currently installs:
#   .git/hooks/commit-msg → calls scripts/guards/sepl-branch-hitch.sh
#
# Skip the guards at runtime: OPENCLAW_NO_GUARDS=1 (skips all)
#                            OPENCLAW_ALLOW_SEPL_HITCH=1 (per-guard)
set -euo pipefail

REPO="$(git rev-parse --show-toplevel)"
HOOK_DIR="$(git rev-parse --git-common-dir)/hooks"
mkdir -p "$HOOK_DIR"

write_hook() {
  local name="$1"
  local body="$2"
  local path="$HOOK_DIR/$name"
  if [ -f "$path" ] && [ "$(cat "$path")" = "$body" ]; then
    printf '  hook %-12s already up to date\n' "$name"
    return
  fi
  printf '%s\n' "$body" > "$path"
  chmod +x "$path"
  printf '  hook %-12s installed (%s)\n' "$name" "$path"
}

COMMIT_MSG_BODY='#!/usr/bin/env bash
# commit-msg hook. Calls tracked guards that need the prepared subject.
# Skip with OPENCLAW_NO_GUARDS=1.
set -uo pipefail

[ "${OPENCLAW_NO_GUARDS:-0}" = "1" ] && exit 0

REPO=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ "$REPO" = "/root/.openclaw/workspace" ] || exit 0

SCRIPT="$REPO/scripts/guards/sepl-branch-hitch.sh"
[ -x "$SCRIPT" ] || exit 0
bash "$SCRIPT" "$1" || exit 1'

echo "install-hooks: target $HOOK_DIR"
write_hook commit-msg "$COMMIT_MSG_BODY"
echo "done."

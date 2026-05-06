#!/usr/bin/env bash
# SEPL hitch-hiker guard. Refuses commits whose subject doesn't match a
# SEPL-shaped prefix when HEAD is on a sepl/<date>-* improve branch.
#
# Reason: 2026-05-05 the layer-confusion improve branch took a 10-file
# skill commit on top of the SEPL improve commit. SEPL's merge gate
# evaluates a specific branch shape; off-shape commits broke the
# contract silently and stranded ~1300 lines of work for ~16 hours
# until manual cherry-pick recovery on 2026-05-06.
#
# Invocation: commit-msg hook. Argument $1 is the path to the prepared
# commit message file (typically .git/COMMIT_EDITMSG).
#
# Bypass: OPENCLAW_ALLOW_SEPL_HITCH=1 for genuinely intentional cases
# (e.g. recovering a stranded branch).

set -uo pipefail

[ "${OPENCLAW_ALLOW_SEPL_HITCH:-0}" = "1" ] && exit 0

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
case "$BRANCH" in
  sepl/[0-9][0-9][0-9][0-9]-*) ;;
  *) exit 0 ;;
esac

MSG_FILE="${1:-}"
[ -n "$MSG_FILE" ] && [ -f "$MSG_FILE" ] || exit 0
SUBJECT=$(grep -v '^#' "$MSG_FILE" | head -n1)

case "$SUBJECT" in
  '[no-push] sepl/improve: '*|\
  'sepl/improve: '*|\
  'sepl/merge: '*|\
  'auto: '*)
    exit 0 ;;
esac

cat >&2 <<EOF

commit-msg: SEPL hitch-hiker guard refused this commit.

  branch:  $BRANCH
  subject: $SUBJECT

That subject doesn't match SEPL's allowed shapes:
  [no-push] sepl/improve: <topic>
  sepl/improve: <topic>
  sepl/merge: <topic>
  auto: <description>

SEPL's merge gate evaluates a specific branch shape. Off-shape commits
have stranded entire days of work before (2026-05-05 layer-confusion:
586154d "add five reflex-gap skills" stranded ~16h until cherry-pick
recovery). Land off-shape work somewhere that won't disrupt SEPL:

  # side branch off master
  git switch -c work/<topic> master

  # or directly on master via the master worktree
  git -C .claude/worktrees/baseline-master-* cherry-pick <sha>

Bypass for genuine cases (e.g. unstranding old work):
  OPENCLAW_ALLOW_SEPL_HITCH=1 git commit ...

EOF
exit 1

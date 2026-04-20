#!/usr/bin/env bash
# Weekly GC for the hourly WIP snapshot branches.
# Deletes origin snapshot branches whose date part is older than
# SNAPSHOT_RETENTION_DAYS (default 14). Also prunes local refs that no
# longer exist on origin. Idempotent; silent when nothing to GC.
set -euo pipefail

WORKSPACE="${WORKSPACE:-/root/.openclaw/workspace}"
cd "$WORKSPACE"

KEEP="${SNAPSHOT_RETENTION_DAYS:-14}"
CUTOFF=$(date -u -d "${KEEP} days ago" +%F)

GCD=0
while read -r ref; do
  [ -z "$ref" ] && continue
  branch="${ref#refs/heads/}"
  date_part="${branch#snapshots/}"
  if [[ "$date_part" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ "$date_part" < "$CUTOFF" ]]; then
    git push origin --delete "$branch" >/dev/null 2>&1 && {
      echo "snapshot-gc: deleted $branch"
      GCD=$((GCD + 1))
    }
  fi
done < <(git ls-remote --heads origin 'snapshots/*' | awk '{print $2}')

git remote prune origin >/dev/null 2>&1 || true

echo "snapshot-gc: $GCD branches deleted (cutoff $CUTOFF, keep ${KEEP}d)" >&2

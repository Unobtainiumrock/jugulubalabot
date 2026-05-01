---
name: branch-prune
description: Use when noticing a stale local branch in `/root/.openclaw/workspace` that is fully merged into `master`. Pre-approved under `feedback_no_ask_workspace_commits.md` (workspace scope only). Verifies merge status, checks for a matching `origin/<branch>`, deletes locally with `git branch -d`, and prunes the remote ref if present. Skips if not merged or not in the workspace.
---

# branch-prune

## When to reach for this

A `git branch -a` shows a feature branch (e.g. `feat/*`, `fix/*`, `chore/*`) that:

- Last saw a commit ≥ 7 days ago
- Is fully merged into `master` (`git merge-base --is-ancestor <branch> master` returns 0)
- Lives in the workspace repo at `/root/.openclaw/workspace`

This is the dead-branch pattern that recurs because nothing else cleans it up. `snapshots/*` branches are managed separately by `scripts/snapshot-gc.sh` — leave those alone.

**Not for**: branches outside the workspace, unmerged work-in-progress, branches with un-pushed commits the human might still need, or branches the human explicitly wants kept (look for `keep:` in the branch description if set).

## How to use

```bash
git -C /root/.openclaw/workspace branch -a              # discover
git -C /root/.openclaw/workspace merge-base --is-ancestor <branch> master \
  && echo MERGED || echo NOT_MERGED                     # verify
```

If `MERGED`:

1. Check for a remote counterpart:
   ```bash
   git -C /root/.openclaw/workspace ls-remote origin "refs/heads/<branch>"
   ```
2. Delete locally with the safe flag (refuses if not merged):
   ```bash
   git -C /root/.openclaw/workspace branch -d <branch>
   ```
3. If remote exists, delete it too:
   ```bash
   git -C /root/.openclaw/workspace push origin --delete <branch>
   ```
4. Note the deletion in today's `memory/<date>.md` so it's discoverable later.

## When to refuse

- `merge-base --is-ancestor` returns non-zero → branch has unique commits. Stop.
- The branch is `master`, `main`, or `HEAD` → stop.
- The branch is a `snapshots/*` ref → leave to `scripts/snapshot-gc.sh`.
- Outside `/root/.openclaw/workspace` → stop; workspace pre-approval doesn't apply.

## Why this is pre-approved

Per `MEMORY.md → feedback_no_ask_workspace_commits.md`: workspace commits and routine git hygiene don't need per-action approval. The hourly WIP snapshot branch (`scripts/snapshot-wip.sh`) is the safety net — anything deleted is recoverable from that day's snapshot.

The destructive-action discipline still applies: never `-D` (force-delete unmerged), never delete remote `master`, never bypass merge verification.

## Eval

No fixture today. Add one if a regression is observed (e.g. branch deleted while unmerged, or skill skipped a merged branch the human had to clean up manually).

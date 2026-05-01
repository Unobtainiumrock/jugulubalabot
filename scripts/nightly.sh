#!/usr/bin/env bash
# Nightly health check — Tier 1 monitoring (NOT the Track 4 learning loop).
# Fires via openclaw cron at 03:00 UTC. Silent on success, Telegram alert
# on any failure. No edits, no auto-merges — observation only.
#
# Checks:
#   1. Eval fixtures — evals/run.sh (eval-notify.sh sends its own alert on fail)
#   2. Bin classifier health — bin-sanity.sh on yesterday's full day of traces
#
# Exit 0 = all healthy. Non-zero = something fired an alert.

set -uo pipefail

WORKSPACE="/root/.openclaw/workspace"
OPENCLAW="/usr/bin/openclaw"
CHAT_TARGET="${NIGHTLY_NOTIFY_TARGET:-8692339838}"
CHANNEL="${NIGHTLY_NOTIFY_CHANNEL:-telegram}"

# OVERALL = max of every gated step's exit code. A gated step is one whose
# failure should block the cron's lastRunStatus (evals, bin-sanity). Silent
# refresh steps (token-accounting, heat-counter, v2-readiness) stay ||true.
OVERALL=0

bump_overall() {
  # $1 = step exit code. Keeps OVERALL = max across all gated steps so the
  # cron's lastRunStatus reflects the worst failure, not just "something broke".
  local rc="$1"
  if [ "$rc" -gt "$OVERALL" ]; then
    OVERALL="$rc"
  fi
}

# --- 1. Eval regression check ---------------------------------------------
# eval-notify.sh exits 0 only if every fixture passes; it sends its own
# Telegram alert on any fail. We don't double-push here — just gate OVERALL.
bash "$WORKSPACE/scripts/eval-notify.sh"
EVAL_EXIT=$?
bump_overall "$EVAL_EXIT"

# --- 2. Token accounting for yesterday (runs silent; just refreshes data) --
YESTERDAY=$(date -u -d "yesterday" +%F)
bash "$WORKSPACE/scripts/token-accounting.sh" "$YESTERDAY" >/dev/null 2>&1 || true

# --- 2b. Pruning signal Layer 1: file-heat decay + touch aggregation -------
bash "$WORKSPACE/scripts/heat-counter.sh" "$YESTERDAY" >/dev/null 2>&1 || true

# --- 2c. Data-conditioned V2-readiness check (one-shot Telegram on trip) ---
bash "$WORKSPACE/scripts/v2-readiness-check.sh" >/dev/null 2>&1 || true

# --- 3. Bin classifier health on yesterday's traces -----------------------
# Raw bin-sanity output is for the agent (kept in reports/); the user gets a
# human-shaped summary or a self-healed line, not the JSON snippets.
BIN_REPORT="$WORKSPACE/reports/bin-sanity-$YESTERDAY.log"
bash "$WORKSPACE/scripts/bin-sanity.sh" "$YESTERDAY" >"$BIN_REPORT" 2>&1
BIN_EXIT=$?

if [ "$BIN_EXIT" -ne 0 ]; then
  # First try to self-heal — name-based inference into bin-overrides.jsonl.
  HEAL_REPORT="$WORKSPACE/reports/bin-autoheal-$YESTERDAY.log"
  bash "$WORKSPACE/scripts/bin-autoheal.sh" "$YESTERDAY" >"$HEAL_REPORT" 2>&1
  HEAL_EXIT=$?
  HEALED=$(grep '^HEALED: ' "$HEAL_REPORT" 2>/dev/null | sed 's/^HEALED: //' | paste -sd ', ')
  UNHEALED=$(grep '^UNHEALED: ' "$HEAL_REPORT" 2>/dev/null | sed 's/^UNHEALED: //')

  cd "$WORKSPACE"
  if ! git diff --quiet -- state/bin-overrides.jsonl 2>/dev/null; then
    git add state/bin-overrides.jsonl
    git commit -q -m "auto: bin-autoheal $YESTERDAY

Mapped: $HEALED" || true
  fi

  if [ "$HEAL_EXIT" -eq 0 ] && [ -n "$HEALED" ]; then
    MSG="Bin classifier — self-healed for $YESTERDAY: $HEALED. Future traces classify automatically; no action needed."
    echo "$MSG" >> "$WORKSPACE/reports/nightly-$(date -u +%F).log"
    if [ "${OPENCLAW_INSCRIPT_PUSH:-0}" = "1" ]; then
      "$OPENCLAW" message send --channel "$CHANNEL" --target "$CHAT_TARGET" \
        --message "$MSG" < /dev/null || true
    fi
    BIN_EXIT=0   # gap closed; don't gate the cron status
  elif [ "$HEAL_EXIT" -ne 0 ]; then
    MSG="Bin classifier — needs your call for $YESTERDAY: $UNHEALED. Pick a bin (file_ground / self_modify / agent_spawn / exec / scheduling / external_fetch / comms / memory_update) and append to state/bin-overrides.jsonl. Raw: reports/bin-sanity-$YESTERDAY.log"
    echo "$MSG" >> "$WORKSPACE/reports/nightly-$(date -u +%F).log"
    if [ "${OPENCLAW_INSCRIPT_PUSH:-0}" = "1" ]; then
      "$OPENCLAW" message send --channel "$CHANNEL" --target "$CHAT_TARGET" \
        --message "$MSG" < /dev/null || true
    fi
  fi
fi
bump_overall "$BIN_EXIT"

# --- 4. Track 2 check-in (status ping) -----------------------------------
# Chained here so the check-in always runs *after* evals/run.sh has finished
# and produced a done.marker. Standalone cron at 03:03 still fires but
# defers itself if today's eval isn't done yet (see track2-checkin.sh).
# Failure is non-blocking (status ping, not gated).
bash "$WORKSPACE/scripts/track2-checkin.sh" >/dev/null 2>&1 || true

exit "$OVERALL"

# peer-agent/

Advisor-only bridge to an external Claude CLI agent working on a different
project. Everything about that project lives inside this directory — nothing
leaks into the rest of the repo.

## Flow (MVP: Nick-as-transport)

1. Tai writes: `bin/send.sh -  <<< "body"` → file in `outbox/YYYY-MM-DD-HHMMSS.txt`.
2. Nick copies the outbox file contents into his local Claude CLI.
3. Nick saves the CLI's reply into a new file in `inbox/*.txt`.
4. Tai runs `bin/recv.sh` → redacts, logs to `transcript.jsonl`, emits clean body.
5. Every 10 exchanges OR at decision points → `bin/checkin.sh` pushes Telegram digest.

Upgrade path: replace step 2–3 with a laptop-side relay piping Claude CLI
stdio to an HTTP endpoint we poll.

## Identity

Tai impersonates Nick. Voice notes in `config.json`. Other Claude is
unaware a peer agent is involved.

## Wall

- `learnings.md` — raw meta-observations (communication patterns, debugging
  tactics, meta-loop insights). Distilled form graduates to
  `~/.claude/projects/-root--openclaw-workspace/memory/feedback_peer_*.md`.
- **Domain facts from the other agent's project (code, file paths,
  architecture, secrets, company/lead info) MUST NOT enter global memory.**
- `redaction-log.jsonl` — audit trail of what redact.sh stripped.

## Files

- `config.json` — peer/bridge/identity/cadence settings
- `bin/send.sh` — queue outgoing
- `bin/recv.sh` — ingest incoming (redacts + logs)
- `bin/redact.sh` — PII/secret filter
- `bin/checkin.sh` — Telegram digest
- `transcript.jsonl` — canonical log (post-redaction)
- `redaction-log.jsonl` — stripped-item audit
- `checkins.jsonl` — when Tai pinged Nick + Nick's feedback
- `learnings.md` — raw meta, allowlist-gated

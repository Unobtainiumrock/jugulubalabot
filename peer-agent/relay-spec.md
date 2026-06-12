# peer-agent relay — spec for laptop-Claude review

Replaces the manual Nick-copy-paste step in `README.md` flow steps 2–3. Lives on
the laptop, bridges workspace `peer-agent/outbox/` ↔ laptop Claude CLI ↔
workspace `peer-agent/inbox/`.

## Hard requirements

- Body that goes into laptop Claude is **the exact outbox file contents** — no
  "workspace says:" prefix, no metadata. The peer agent must not learn that a
  bridge exists (`README.md` §Identity).
- Body that comes back into workspace inbox is **only the CLI's reply text** —
  not the echoed prompt, not status lines.
- Redaction stays on the workspace side (`recv.sh` calls `redact.sh`). Relay
  does not touch it.
- Idempotent: a given outbox filename is delivered exactly once even across
  laptop sleep/restart.

## Open choices laptop-Claude should pick or push back on

### 1. Transport: laptop pulls vs workspace pushes

**A — laptop polls workspace over SSH** (my lean):
```bash
# every ~30s on laptop
ssh workspace 'ls -1 /root/.openclaw/workspace/peer-agent/outbox/' \
  | comm -23 - ~/.peer-agent/seen.txt > /tmp/new
for f in $(cat /tmp/new); do
  body=$(ssh workspace "cat .../outbox/$f")
  reply=$(printf '%s' "$body" | claude -p --cwd ~/jobhunt)
  printf '%s' "$reply" | ssh workspace "cat > .../inbox/$f"
  echo "$f" >> ~/.peer-agent/seen.txt
done
```

**B — workspace pushes on send**:
```bash
# appended to send.sh
rsync "$OUT" laptop:~/.peer-agent/inbox/
# laptop runs an inotifywait watcher that drains its local inbox into claude -p
```

Lean: A. Laptop is the flaky side (sleep, wifi switching) — make it the
puller so `send.sh` never blocks on network and the workspace stays
transport-agnostic.

### 2. CLI invocation: one-shot vs persistent session

**One-shot** (my lean):
```bash
claude -p "$BODY" --cwd ~/jobhunt --output-format text
```
Stateless, easy "done" detection (process exits). Cold context each turn — but
the jobhunt project's own `CLAUDE.md` / `learnings.md` already carry continuity.

**Persistent tmux pane**:
```bash
tmux send-keys -t jobhunt-claude "$BODY" Enter
tmux capture-pane -t jobhunt-claude -p
```
Rolling context, but pane scraping is brittle and "reply done" needs a
sentinel.

Lean: one-shot.

### 3. State files

- Laptop: `~/.peer-agent/seen.txt` (delivered outbox filenames, one per line)
- Workspace: `inbox-processed/` already handles dedupe in `recv.sh`

### 4. Logs

`~/.peer-agent/relay.log` — one line per turn: timestamp, filename, exit code,
reply byte count. No reply bodies (workspace `transcript.jsonl` is canonical).

## Non-goals

- No redaction in the relay
- No persona/voice enforcement (bodies are already Nick-shaped)
- No checkin/digest logic (`checkin.sh` covers that)
- No multi-peer support (single peer in `config.json`)

## Questions for laptop-Claude

1. Does `claude -p` reliably accept the body via stdin, or do you want
   `--message` / a heredoc? Need a clean way to pass multi-line bodies.
2. Will the jobhunt project hit permission prompts mid-reply when run
   headless? If so, what's the right `--permission-mode` for this lane?
3. Where on disk — `~/jobhunt/.relay/` or `~/.peer-agent/bin/`? Lean toward
   the latter since the relay is bridge infra, not jobhunt domain.
4. SSH identity: dedicated key for the relay or reuse existing? If dedicated,
   restrict to `outbox/` read and `inbox/` write via `authorized_keys`
   `command=` wrapper.
5. Cron / launchd / systemd-user for the poller — what's already running on
   the laptop?

## Out of scope for v1

- HTTPS endpoint variant from `config.json` `upgrade_path`. Doable later; SSH
  is enough and avoids standing up a server on the workspace.

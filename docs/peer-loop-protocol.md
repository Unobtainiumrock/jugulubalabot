# Peer-loop protocol

The agreement between Tai (here, on the VPS) and a peer Claude instance (on Nick's laptop) for how messages flow back and forth without either side getting confused, duplicated, or stuck.

This doc is the **rulebook**. The poller and any laptop-side relay must conform to it. If something isn't covered here, it doesn't exist yet.

## The shape of the loop

```
Tai writes a message
  -> message lands as a file in peer-agent/outbox/
  -> laptop relay sees it (over SSH from laptop), pipes the body into
     the peer Claude session, captures the reply
  -> laptop relay writes the reply as a file in peer-agent/inbox/
  -> server poller (system cron, every 60s) sees the new inbox file
  -> poller schedules a Tai turn to read + respond
  -> Tai writes the next message into peer-agent/outbox/
  -> repeat
```

Either side can call a halt. Either side can be slow. The protocol is built so neither side gets confused if a message gets sent twice, dropped, or arrives out of order.

## Message format (the envelope)

Every file in `outbox/` and `inbox/` is a JSON file with this shape:

```json
{
  "schema_version": 1,
  "round": 7,
  "correlation_id": "ab12cd34",
  "in_reply_to": "ef56gh78",
  "ts": "2026-04-21T04:30:00.123Z",
  "from": "tai",
  "body": "the actual message text — what the receiving Claude sees as input",
  "expects_reply": true,
  "halt_request": false
}
```

What each field means:

- **schema_version** — currently `1`. If the protocol changes, this bumps. Old-version messages are rejected with a halt + Telegram ping.
- **round** — monotonically increasing integer, starting at 1. Each side increments when it sends. Catches drift if rounds get skipped.
- **correlation_id** — short random hex (8 chars). Uniquely names this message. Used to dedupe.
- **in_reply_to** — the correlation_id of the message this one responds to, or `null` if this is the loop opener.
- **ts** — ISO 8601 UTC timestamp of when the message was generated.
- **from** — `"tai"` (server side) or `"peer"` (laptop side). Sender labels itself.
- **body** — the actual message text. This is what the receiving Claude sees in its prompt. Plain text, no special structure required.
- **expects_reply** — usually `true`. `false` means this is a final message (e.g., halt notification, "done, signing off") and the other side shouldn't respond.
- **halt_request** — `false` normally. `true` means: stop the loop after processing this message. Both sides honor it.

**Filename convention:** `<round>-<correlation_id>.json`, e.g. `0007-ab12cd34.json`. Keeps directory listings sorted by round.

## What happens if a message gets sent twice (idempotency)

Either side can resend the same message — for example, if the laptop relay isn't sure the file made it to the inbox and tries again. The receiver dedupes by `correlation_id`.

- Each side keeps a state file `state/peer-loop/seen-correlation-ids.txt` (one ID per line).
- On receive: if the ID is in the seen list, skip processing (no response, no Tai turn spawn).
- If new: process, then append the ID.
- The seen file is append-only and rotated weekly to keep size bounded.

A resend with a **different body** but the same correlation_id is a contract violation — receiver halts and pings Nick.

## What happens when something fails (retry behavior)

**Laptop side (responsible for transport):**
- If SSH fails when delivering a Tai message into the peer Claude, retry with the same correlation_id. Up to 3 attempts, exponential backoff (5s, 30s, 2m).
- If 3 attempts fail, write a halt notification message into `inbox/` with `halt_request: true` and ping Nick.

**Server side (Tai):**
- If recv.sh can't parse an inbox file (malformed JSON, missing fields), move it to `inbox-malformed/` and ping Nick. Don't halt the whole loop — the next valid message proceeds.
- If two consecutive inbox files are malformed, halt and ping Nick.
- Tai's response is written by send.sh atomically (write to a tmp file, rename into outbox/). No partial files visible to the laptop side.

## What stops the loop (halt conditions)

Both sides check these before processing each round. Any one tripping = stop the loop, write a "halt" status to `state/peer-loop/halt-reason.txt`, ping Nick on Telegram, do not send anything further.

1. **Kill switch.** A file `peer-agent/.halt` exists. Either side can create it (e.g., Nick can `ssh root@vps touch peer-agent/.halt` to stop everything from his phone).
2. **Daily round cap.** More than 100 rounds completed in the last 24h. Catches runaway loops.
3. **Per-round timeout.** A single round (Tai-respond OR peer-respond) takes more than 5 minutes. Catches hangs and "the agent went off and did 40 minutes of unrelated work" failure modes.
4. **Empty replies.** Two consecutive replies with body length under 10 characters (after trim). Catches the "I don't know" → "ok" → "?" → "?" death spiral.
5. **Schema mismatch.** A received message has `schema_version` other than 1. Means one side has been upgraded out of sync.
6. **Explicit `halt_request: true`** in any message.
7. **Topic loop.** Same topic cycles 3+ times without new information. Tai's heuristic responsibility — if Tai detects it, it sends a message with `halt_request: true`.
8. **Body too large.** Any message with `body` over 8000 characters. Catches runaway agents producing wall-of-text output. Sender refuses to write the file and halts; receiver halts on read of an oversize body.
9. **Cost-control checkpoint.** Every 10 rounds Tai sends, the loop auto-pauses for human review. Same mechanism as the kill switch (the `.halt` file gets written with reason text "checkpoint at round N — review and resume"). Nick reviews the recent rounds, then `rm peer-agent/.halt` to continue. Distinct from a real halt only by the reason text in the ping.

The Telegram halt ping includes: which condition tripped, the last 3 rounds' bodies (truncated to 200 chars each), the round count, the elapsed wall-clock time of the loop.

## How the loop starts (cold-start)

Both sides are blank on day 1. The first three rounds are not collaboration — they're briefing.

**Round 1 (Tai → peer):** the **mission briefing**. Plain text body that says:
- Who Tai is (an external Claude instance helping Nick on the openclaw side, here as a collaborator).
- What this loop is (an automated back-and-forth via files; you're talking to Tai, who replies as Nick has authorized).
- The mission as Tai understands it from Nick (one paragraph, sourced from `peer-agent/config.json`).
- An ask: "confirm or correct the mission, and tell me what files / state you can see in your environment that's relevant."

**Round 2 (peer → Tai):** peer's response — mission confirm/correct + a structured environment summary. The peer's body MUST include these fields (plain text, labeled, easy to grep):

```
cwd: <absolute path of the peer's current working directory>
visible_files: <a top-level listing of that directory, one path per line, max 50 entries>
tools_available: <comma-separated list of tools the peer has access to, e.g. Read, Write, Bash, Grep>
mission_understood: <one paragraph in the peer's own words>
mission_corrections: <any corrections to what Tai stated, or "none">
```

Without those fields Tai can't objectively verify the peer can see the relevant project. If round 2 is missing any of them, Tai re-asks once. If round 3 (the re-ask reply) still lacks them, Tai halts with `halt_request: true`.

**Round 3 (Tai → peer):** alignment. If mission needed correction, Tai's revised understanding. Otherwise, the first real ask: "ok, here's where I'd start — do you agree?"

**Round 4 onward:** actual work.

If round 2 reveals the peer can't see relevant files (no repo access, wrong working directory), Tai halts the loop with `halt_request: true` and pings Nick. No point looping if the peer is blind.

## What gets logged per round

Every send and every receive appends one JSON line to `state/peer-loop/rounds.jsonl`:

```json
{
  "ts": "2026-04-21T04:30:00.123Z",
  "round": 7,
  "direction": "sent" | "recv",
  "correlation_id": "ab12cd34",
  "in_reply_to": "ef56gh78",
  "body_chars": 1247,
  "duration_ms": 3210,
  "halt_request": false
}
```

Token counts go in here too if/when the runtime exposes them. Without tokens, body_chars is the proxy for cost estimation.

This log is the forensic record. When something goes wrong, the first thing Nick (or Tai) reads.

## What's NOT in this protocol (yet)

- Multi-party loops (more than two agents).
- File transfer beyond inline body (peer can't send Tai a file directly).
- Streaming — every round is request/response, no partial responses.
- Tool-call passthrough — Tai cannot trigger the peer to run tools; the peer runs whatever it would run on its own.

These are deliberate omissions for v1. Add them only if a real need surfaces.

## Versioning

This is `schema_version: 1`. Any change to the envelope or halt-conditions list bumps the version and requires both sides to upgrade in lockstep. Mid-loop schema bumps are not supported — halt the loop, upgrade both sides, restart fresh.

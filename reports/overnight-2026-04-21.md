# Overnight 2026-04-21 — consolidated report

_Pass ran 09:17 → 17:17 UTC. 8 hours, 8 planned deliverables._

## TL;DR

- **8/8 hours executed, 6 commits landed** (H1–H6). H7 intentionally
  shipped zero tracked changes (memory/ + MEMORY.md curation + scratch.md
  hygiene, all gitignored or out-of-repo). H8 adds this report.
- **Two durable loops closed from `reports/mistakes.md`:** H1 shipped
  `track2-checkin.sh --dry-run` (closes 06:28 mistake) + `budget-peek-watch`
  heartbeat task (closes 05:05 silent-stall). Capabilities now
  schedule-enforced, not reflex-dependent.
- **Plumbing upgrades to reflect loop:** H2 added `source` field to
  `scripts/trace.sh` + consumer in `reflect.sh`; H5 fixed Bash class
  extractor to strip leading `NAME=VAL` env prefixes (backlog 628dec).
- **Behavioral gaps captured as regression tests:** H3 shipped
  `orange-budget-triggers-peek` eval fixture which **fails on Tai's
  current behavior** — this is the point; fix deferred to a SOUL.md edit.
- **SOUL-level reflex added:** H4 elevated `mkscript` to Meta-rules
  (reflect hypothesis #1 — skill had fired 0× vs. 7× `Write:sh + chmod`
  pattern). H6 stiffened `nightly.sh` exit-code propagation via `max()`
  instead of binary 0/1 (backlog 12ae6e).

## Commits (since 09:00 UTC)

| Hash | H | Subject |
|------|---|---------|
| `e799416` | H1 | close mistakes.md Fix items (track2-checkin --dry-run + budget-peek heartbeat) |
| `278ff79` | H2 | trace.sh source field + reflect.sh consumer |
| `b439a76` | H3 | orange-budget-triggers-peek eval fixture |
| `61a70cf` | H4 | mkscript reflex elevated to SOUL.md |
| `4a5ac89` | H5 | strip leading env-var assignments in Bash class extractor (backlog 628dec) |
| `6157f64` | H6 | propagate eval-notify exit code through nightly.sh (backlog 12ae6e) |
| _(H7)_ | H7 | no commit — day log + MEMORY.md pass + scratch.md hygiene, all gitignored/out-of-repo |
| _(this)_ | H8 | consolidated wake-review report (force-added; reports/* is gitignored) |

## Hour-by-hour outcomes

| Hour | Plan | Shipped | Notes |
|------|------|---------|-------|
| H1 | Close open mistakes.md Fix: items | ✅ `track2-checkin.sh --dry-run`; `HEARTBEAT.md` `budget-peek-watch`; resolution pointers in mistakes.md | No skips |
| H2 | Add `source` field to `scripts/trace.sh` + surface in `reflect.sh` | ✅ source detection from `OPENCLAW_MCP_SESSION_KEY` (`cron`/`subagent`/`conversation`/`unknown`); reflect section added | Heartbeat vs conversation discrimination deferred — heartbeats share main session key |
| H3 | New eval fixture — ORANGE budget → forces budget-peek | ✅ 3-grader fixture (regex+/regex-/llm_judge). **Intentional FAIL on current behavior** — regression captured in test | Behavioral fix (SOUL.md rule) deferred |
| H4 | `mkscript` reflex elevated to SOUL.md | ✅ One bullet added under Meta-rules, between "Token-burn to deterministic" and "Earn trust through competence" | Exactly one line; no collateral changes |
| H5 | Backlog 628dec — strip leading env-var assignments in Bash class extractor | ✅ `strip_env` jq helper in `scripts/trace.sh`; 6 representative cases verified | Retargeted from plan's 6fa171 per God's cron override. Quoted-value + nested-paren edge cases deferred |
| H6 | Backlog 12ae6e — nightly.sh exit-code propagation | ✅ `bump_overall()` → `max(OVERALL, $rc)`; shim-based propagation test: 5/5 pass | `eval-notify.sh` itself was already clean; real bug was exit-class flattening in nightly.sh |
| H7 | Daily memory + MEMORY.md curation + scratch.md hygiene | ✅ day log written (gitignored); MEMORY.md reviewed — net delta 0; scratch.md left (9h age < 48h threshold) | No commit — convention-driven zero-change; guardrail permits |
| H8 | Consolidated report + Telegram summary push | ✅ this report; Telegram sent | — |

## Open items

- **Backlog 6fa171 (`FIXTURES=` filter for `evals/run.sh`)** — reflect
  entry originally assigned to H5. Investigation during H3 and H5 found
  the filter **already exists** at `evals/run.sh:27–33`. The backlog
  entry is stale; should be closed via a reflect-consumer pass rather
  than a new implementation. Candidate for tomorrow's reflect digest.
- **Behavioral fix for ORANGE-budget-forces-peek (H3 fixture)** — the
  test fails on current behavior. Fix belongs in SOUL.md as an explicit
  rule: when `budget-peek-watch` alerts ORANGE/RED and an oversized
  request is in-flight, must either `/compact`, reduce scope, or
  invoke budget-peek explicitly before continuing. Deferred to God's
  review (worth his eyes before the rule lands).
- **Heartbeat-vs-conversation discrimination in `trace.sh source` field
  (H2 skipped)** — currently indistinguishable because heartbeats reuse
  the main session's `OPENCLAW_MCP_SESSION_KEY`. Second pass would
  inspect `/proc/$PPID/cmdline` for the `--prompt` flag + scan prompt
  content for heartbeat sentinel. Plumbing-only; not blocking.
- **Reflect backlog description tightening (H6 skipped)** — reflect
  framed 12ae6e as "exit code swallowed"; real shape was "exit class
  flattened to 1 instead of max()". Description can be tightened in a
  future reflect-consumer pass.

## Mistakes ledger state

Three 2026-04-21 entries (06:28 track2-checkin live-Telegram, 05:05
silent-stall, 05:10 /new process model) all received **"Resolved
2026-04-21 H1 overnight pass"** pointer notes during H1. Pointers
preserved — no subsequent hour mutated them. Heartbeat
`mistake-loop-close` should stay silent for today's dated entries going
forward.

No new mistake entries were appended during H2–H8. All surprises stayed
within the "deferred edge case" bucket rather than the "shipped wrong
thing" bucket.

## Wake-review actions for God

1. Read this report (`reports/overnight-2026-04-21.md`).
2. Diff check: `git log --oneline master --since="2026-04-21 09:00"` → 7 commits (H1–H6 + this H8).
3. Scan the **Open items** section above — two items want your eyes:
   - Whether to ship the SOUL.md ORANGE-budget rule to flip the H3 fixture from FAIL → PASS, and what the exact rule text should be.
   - Whether 6fa171 can be closed as stale in the next reflect digest.
4. Per-hour logs live at `reports/overnight-h<N>-2026-04-21.md`
   (gitignored, local only) if you want deeper inspection.
5. Day log at `memory/2026-04-21.md` (gitignored). `MEMORY.md` was
   reviewed and deliberately left unchanged (H7 rationale documented).
6. No remote pushes happened beyond the Telegram summary.

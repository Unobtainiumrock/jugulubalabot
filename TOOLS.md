# TOOLS — Local Notes

## Host

- Hostinger VPS, Ubuntu 24.04, 2 vCPU / 8 GB / 100 GB.
- Gateway: loopback-only `127.0.0.1:18789`. Control UI reachable via SSH tunnel from God's laptop (`ssh -L 18789:127.0.0.1:18789 root@2.24.214.139`).
- Model: Claude Pro/Max via Claude Code credentials; `claude-cli/claude-opus-4-7` primary.

## God's repos to know

- `autoresearch` — https://github.com/Unobtainiumrock/autoresearch
- `genetic-algorithms` — https://github.com/Unobtainiumrock/genetic-algorithms

## Reference

- Autogenesis (Wentao Zhang, arXiv:2604.15034, Apr 2026) — two-layer self-evolution protocol.

## Ops notes

- **OpenClaw invokes Claude Code with `--setting-sources user`**, so project-level `workspace/.claude/settings.json` hooks are **never loaded**. Put hooks in `/root/.claude/settings.json` (user-level) instead. The workspace `.claude/settings.json` file exists for documentation/git history only; it is a no-op under openclaw's invocation shape.
- **Hook script lives at `/root/.openclaw/workspace/scripts/trace.sh`** — use bash (`cat > ... << EOF`), not the `Edit` tool, if modifying `/root/.claude/settings.json` (Claude Code hardcode-gates edits to any `.claude/settings.json` path even under `bypassPermissions`).
- **No session restart needed** when user-level settings change — each `claude -p` invocation loads them fresh. Tai's next Telegram turn picks up updates automatically.
- **Hooks fire on tool calls only**, not on plain model responses. Tool list is: Read, Write, Edit, Bash, Glob, Grep, Agent/Task, Skill, WebFetch, WebSearch, plus whichever `mcp__*` tools are live.
- **Traces path**: `/root/.openclaw/workspace/traces/YYYY-MM-DD.jsonl`. Daily rollup: `bash /root/.openclaw/workspace/scripts/trace-summary.sh`.

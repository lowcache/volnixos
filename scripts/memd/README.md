# memd — agent-driven project memory curator

Maintains `./.memory/{state,decisions,mistakes,todo}.md` (plus `archive/` and
`inbox/`) per project, distilled from AI session transcripts by a headless
`claude -p` curator. Designed for multiple projects, multiple CLIs
(claude-code, antigravity, anything that can write a file), and agent swarms.

## Architecture

```
claude-code session ──hooks──▶ memd hook session-end ──▶ detached memd sync
                    └─SessionStart──▶ memd brief (context injection)
systemd user timer (30 min) ──▶ memd sweep ──▶ sync stale projects,
                                               ingest .memory/inbox/,
                                               prune to archive/,
                                               auto-detect + scaffold new repos
memd sync: transcript JSONL ▶ digest ▶ claude -p (haiku, sonnet for big
session-end runs) ▶ validated JSON edits ▶ .memory/ files ▶ git commit
```

Hard invariants enforced by memd itself, not the model: frontmatter
(`type/project/last_updated/status`), append-only `mistakes.md`, a shrink
guard (rejects distills that lose >60% of a file without archiving it),
size budgets with deterministic overflow to `archive/YYYY-MM.md`, per-project
flock (swarm-safe), and cursors that only advance after a successful apply.

## Cross-platform / swarm interface

**antigravity-cli** is read natively: conversations live in
`~/.gemini/antigravity-cli/conversations/*.db` (SQLite, protobuf step
payloads; legacy `*.pb` files are not parsed). memd extracts text as
printable-string runs (step types: 14=user, 33=assistant, 15=tool call,
17=error) and cursors on `steps.idx`. Antigravity records the *launch*
directory as workspace, so conversations are attributed to the registered
project whose root path their payloads mention most (cached in
`~/.local/state/memd/ag_index.json`; unattributed ones are rescanned as
they grow). All digests pass a credential-redaction filter (`ya29.`, `ghp_`,
`sk-`, JWTs, …) since sessions sometimes read secrets.

Anything else talks to memd through `./.memory/inbox/`: drop a markdown
note there and the next sweep or sync ingests and deletes it. That is also
how swarm agents hand observations to the curator without write access to
memory files. Extra transcript sources (claude-format JSONL) can be added
per project in `~/.config/memd/config.json` under
`projects.<path>.extra_sources`.

## Commands

| command | purpose |
|---|---|
| `memd init [path]` | scaffold `.memory/` + `.model/` stub, register project |
| `memd sync [--project P] [--trigger T] [--dry-run]` | distill now |
| `memd sweep` | timer entry: catch up everything, prune, detect new projects |
| `memd brief [path]` | print the session-start memory brief |
| `memd status` | registry, backlog bytes, last distill summaries |
| `memd install-hooks` | idempotently wire hooks into `~/.claude/settings.json` |
| `memd exclude <path>` | never auto-manage a path |

State lives in `~/.local/state/memd/` (cursors, locks, log), config in
`~/.config/memd/config.json` (models, budgets, quiet period, registry).
Deployed by `home/memd.nix` (package + `memd-sweep` systemd user timer).

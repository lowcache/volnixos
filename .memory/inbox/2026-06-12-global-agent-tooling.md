# 2026-06-12 — Global agent tooling (memd, tether, agent-scaffold)

## Decision
Made memd and the agent tether globally usable across all projects, and added
automatic per-project scaffolding of `.model/` + `.memory/`:

- **PATH:** `memd`, `tether`, and the new `agent-scaffold` are declarative
  out-of-store symlinks in `~/.local/bin` (home/memd.nix, `force = true`,
  targets under `/persist.../.nix-config`). Live-editable without rebuild,
  matching the dots/ hot-reload philosophy. The memd-sweep timer keeps using
  the hermetic Nix-store copy of memd.
- **Persistence fix:** `~/.config/memd` (registry/config) and
  `~/.local/state/memd` (cursors, ag_index, locks) were NOT persisted and were
  silently wiped each boot on the tmpfs home — both added to home/persist.nix.
- **tether default workdir** is now `$PWD` (works from any project);
  `~/.nix-config` paths auto-map to the `~/volnix` alias; other hidden paths
  fall back to `~/volnix`. Usage text updated.
- **agent-scaffold** (`scripts/agent-scaffold/`, fish): at any git root,
  renders `templates/MODEL.md` into `.model/CLAUDE.md` / `AGENTS.md` (generic
  "agent") / `GEMINI.md`, and runs `memd init` when `.memory/` is missing.
  Idempotent, never overwrites, no-op outside git repos and in $HOME.
  Wired as a global claude-code SessionStart hook (~/.claude/settings.json),
  ordered before `memd hook session-start`.

## Rationale
The tether doctrine lived only in this repo's `.model/CLAUDE.md` §5, and
tether wasn't on PATH — unusable elsewhere. The scaffolded `.model/CLAUDE.md`
carries the memd protocol + tether doctrine into every project until
project-specific instructions replace its §4.

## Rules out
Hand-created `.memory/` scaffolding (still memd-init only) and editing
generated `.model/` guides to improve boilerplate (edit the template instead).

## Follow-up (same day): claude-agnostic hardening
To protect against possible claude-code discontinuation:
- **memd `curator_cmd` config** (memd.py): optional argv list replacing the
  hardcoded `claude -p` distill backend — prompt on stdin, `{model}`
  substituted, output need only contain one JSON object. Empty (default)
  keeps the claude path. Distill failure loses nothing: cursors advance only
  after successful apply, so backlog replays under a new backend. Documented
  in scripts/memd/README.md ("Claude-code independence").
- **fish `agy` wrapper** (home/shell.nix): runs `agent-scaffold` before
  launching antigravity, mirroring the claude SessionStart hook for the other
  agent CLI. Deliberately NOT a PWD/cd hook — cd-ing into cloned third-party
  repos must not litter them with scaffolding. Pattern: wrap each agent CLI
  entry point.
- Everything else was already agnostic: memd sweep timer (session-free),
  native antigravity reads, `.memory/inbox/` for any tool, and both
  `agent-scaffold` and `memd` as plain CLIs on PATH.

## Note
`/tmp/scaffold-test` was used as a test project and then `memd exclude`d; the
stale exclude entry in `~/.config/memd/config.json` is harmless.

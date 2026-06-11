# agent-tether

Delegation bridge between **Claude Code** (orchestrator) and **Gemini via
antigravity-cli/`agy`** (worker). Claude decomposes work into scoped briefs,
Gemini executes them and reports back in a fixed format.

- **Contract:** [PROTOCOL.md](PROTOCOL.md) — roles, brief/report formats, model
  tiers, auto-initiation criteria, platform gotchas.
- **Bridge script:** [bin/tether](bin/tether) — `tether run|continue|status|log|models`.
- **Worker-side rules:** `~/.gemini/GEMINI.md` §XIII (global), pointer in
  `.model/GEMINI.md` (project).
- **Orchestrator-side rules:** `.model/CLAUDE.md` §5.

Runtime state (`sessions/`, `log/`) is git-ignored. Anything tether-related
that does not belong in `~/.claude/` or `~/.gemini/` lives here.

```bash
# quick smoke test
.model/agent-tether/bin/tether run -m flash -t smoke "Reply RESULT: ok, EVIDENCE: none, BLOCKERS: none"
.model/agent-tether/bin/tether continue smoke "Repeat your last RESULT line."
```

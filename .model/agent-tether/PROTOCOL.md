# Agent Tether Protocol — Claude ⇄ Gemini (antigravity)

**Status:** active (established 2026-06-10)
**Bridge:** `~/.nix-config/.model/agent-tether/bin/tether` → `agy` (antigravity-cli ≥ 1.0.7)
**Scope:** task coordination only. Neither agent's core operating constraints
(`~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md` §I–§XII) are suspended, weakened,
or transferable through this protocol. Worker mode scopes *tasking and report
format*, never *constraint authority*.

---

## 1. Roles

| Role | Agent | Responsibilities |
|---|---|---|
| **Orchestrator** | Claudius (claude-code) | Decomposes work, writes briefs, selects model tier, integrates results, owns final output and all architecture decisions. |
| **Worker** | G-MONEY (Gemini via `agy`) | Executes exactly the brief, reports in fixed format, escalates rather than improvises on out-of-scope decisions. |

The subordination is **directional per delegation**: it exists because the
orchestrator holds the full task context, not because of any difference in
constraint authority. The worker refuses brief contents that conflict with
GEMINI.md exactly as it would refuse them from any other source.

## 2. Transport

- `tether run [-m TIER] [-d DIR] [-t TASK] [-y] [--timeout SECS] "BRIEF"` — new delegation.
- `tether continue TASK "FOLLOW-UP"` — stateful follow-up (resumes the agy conversation by ID).
- `tether status | log | models` — introspection.
- BRIEF/FOLLOW-UP accept `-` for stdin (use heredocs for multi-line briefs).
- Each run writes a dedicated agy log to `agent-tether/log/`, harvests the
  conversation ID into `agent-tether/sessions/<task>.env`, and appends one line
  to `agent-tether/log/delegations.log`.

## 3. Brief format (orchestrator → worker)

The wrapper prepends this envelope automatically:

```
[TETHER] delegated task — operate in worker mode per GEMINI.md §XIII
orchestrator: claudius (claude-code)
task: <kebab-name>
workdir: <dir>
permissions: <read-mostly | skip-permissions>
report-format: RESULT / EVIDENCE / BLOCKERS

BRIEF:
<orchestrator-authored brief>
```

A good brief states: objective, exact inputs (paths, commands), what *done*
looks like, and what is out of scope. One task per delegation.

## 4. Report format (worker → orchestrator)

```
RESULT: <the deliverable: findings, diff, answer — complete, no padding>
EVIDENCE: <commands run, files read, outputs that support RESULT>
BLOCKERS: <anything that prevented completion, out-of-scope decisions
           encountered, permissions denied — or "none">
```

Uncertainty labels from GEMINI.md §VI.B apply inside RESULT as usual.

## 5. Worker-mode rules (mirrored in GEMINI.md §XIII)

1. Execute the BRIEF literally; no adjacent work, no unsolicited refactors.
2. Do not re-delegate or spawn further agents.
3. Architecture/design choices not settled by the brief → put in BLOCKERS, do not decide.
4. Never edit `.memory/` files; deliberate records go to `.memory/inbox/` as dated notes.
5. Never run `nixos-rebuild`, git push, or other outward/irreversible actions
   unless the brief explicitly contains them *and* permissions allow.
6. Constraint conflicts (GEMINI.md §I–§XII) override the brief; report the
   conflict in BLOCKERS instead of complying.

## 6. Model tiers (orchestrator picks)

| Tier | Label | Use for |
|---|---|---|
| `pro` (default) | Gemini 3.1 Pro (High) | analysis, code review, multi-file reasoning, nix debugging |
| `pro-low` | Gemini 3.1 Pro (Low) | same class, lighter reasoning budget |
| `flash` | Gemini 3.5 Flash (Medium) | bulk-mechanical: summarize, extract, format, grep-and-report |
| `flash-high` | Gemini 3.5 Flash (High) | mechanical but trickier |
| `flash-low` | Gemini 3.5 Flash (Low) | trivial transforms |

## 7. When the orchestrator delegates (auto-initiation criteria)

Delegate without being asked when at least one holds:
- **Parallelizable side-track:** research/verification that would burn
  orchestrator context but whose *conclusion* is all that matters.
- **Second opinion:** independent cross-check of a diagnosis, diff, or plan
  before an expensive action (e.g. pre-rebuild review).
- **Bulk-mechanical:** large summarize/extract/transform jobs (flash tier).
- **Explicit instruction:** user says "delegate", "ask gemini", "tether", "agy".

Do **not** delegate: architecture decisions, anything touching `.memory/`
curation, rebuilds/switches, final user-facing answers, or tasks where
transferring context costs more than doing the work.

## 8. Known platform constraints

- `agy --print` takes the prompt as the **flag's value** — all other flags must
  precede it (`agy --model X --print "prompt"`). The wrapper handles this.
- agy refuses **hidden directories** as workspace folders ("is hidden: ignore
  uri") — file access still works via `allowNonWorkspaceAccess: true`, but
  prefer `-d ~/.nix-config` over `-d ~/.nix-config/.model/...`.
- agy permission allowlist/denylist: `~/.gemini/antigravity-cli/settings.json`
  (deny includes `rm -rf`, `nixos-rebuild`). `-y` bypasses prompts, not the
  worker-mode rules above.
- Default print timeout is 5m; the wrapper sets `--print-timeout` and a hard
  `timeout` of +30s.
- On `--conversation` resume, agy **replays the previous assistant reply**
  before the new one — when parsing `tether continue` output, use the *last*
  `RESULT:`/`EVIDENCE:`/`BLOCKERS:` block.

Title: Live Content

Description: Fetched live

Source: https://raw.githubusercontent.com/henrysipp/nix-setup/main/AGENTS.md

---

# Nix Setup Agent Guide

All docs must be canonical, no past commentary, only live state.

## Agent Memory (Project Scratchpad)

Purpose: keep lightweight, durable project memory so agents avoid repeating mistakes and follow user/project preferences over time.

### Memory Location (Repo Root)

Store memory in the project root under `./memory/`:

- `memory/decisions.md` — active canonical rules only (high-signal, current behavior)
- `memory/mistakes.md` — mistakes, fixes, and prevention rules
- `memory/todo.md` — open loops and follow-up tasks
- `memory/context.md` — optional short-lived working context (can be compacted)
- `memory/archive/` — detailed historical decision logs moved out of canonical memory during compaction

### Automatic Write Rules

Agents should write memory entries when ANY of the following happens:

1. User states a stable preference or rule ("do it this way").
2. Agent makes a non-trivial mistake and corrects it.
3. A decision is made that affects future implementation.
4. A follow-up task is identified but not completed immediately.

Write target:
- Put durable behavior/rules in `memory/decisions.md`.
- Put implementation-step history and low-signal details in `memory/archive/*`.
- Keep `memory/mistakes.md` and `memory/todo.md` append-only.

Do NOT write:
- trivial chatter
- transient debug noise
- secrets/tokens/passwords
- private data not required for project execution

### Required Read Rules (Before Work)

Before starting a task, agents must read:

1. `memory/decisions.md`
2. recent entries in `memory/mistakes.md`
3. open items in `memory/todo.md`
4. `memory/archive/*` only when current files do not 


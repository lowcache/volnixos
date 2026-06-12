# %AGENT% Guide — %PROJECT%

> Generic scaffold placed by `agent-scaffold`. The global contracts below
> apply until project-specific instructions replace or extend this file.

---

## 1. Project Memory (memd-curated)

Project memory lives in `./.memory/` and is **owned by `memd`**, an autonomous
background curator (source: `~/.nix-config/scripts/memd/`, see its README).
Sessions READ memory; memd WRITES it.

* **Read at session start, before substantive work:** `.memory/state.md`,
  `decisions.md`, `mistakes.md`, `todo.md`.
* **To record anything** (a decision, a mistake and its prevention rule, a
  completed task, a correction), drop a dated markdown note in
  `./.memory/inbox/` — the curator ingests, merges, and deletes it on its
  next distill. This is the write interface for every agent and CLI.
* **Never** edit, prune, archive, or rewrite `.memory/` files or their
  frontmatter directly; manual edits race the curator's background runs.
* Missing scaffolding: run `memd init`, never hand-create it. Introspection:
  `memd status`; memory history: `git log -- .memory/`.

## 2. Agent Tether — delegation bridge (Claude orchestrates, Gemini works)

A delegation bridge to antigravity/Gemini is globally available as `tether`
(home: `~/.nix-config/.model/agent-tether/`; read its `PROTOCOL.md` before
first use in a session). Worker-side rules live in `~/.gemini/GEMINI.md` §XIII.

* `tether run [-m pro|pro-low|flash|flash-high|flash-low] [-d DIR] [-t TASK] [-y] "BRIEF"`
  — new delegation. Default workdir is `$PWD`, so it operates on this project.
* `tether continue TASK "FOLLOW-UP"` — stateful follow-up;
  `tether status | log | models` — introspection.
* **Roles:** Claude is the orchestrator (decomposes work, writes briefs,
  integrates results, owns all decisions); Gemini is the worker (executes the
  brief literally, reports as `RESULT / EVIDENCE / BLOCKERS`).
* **Auto-initiate** a delegation for: parallelizable research/verification
  side-tracks, independent second opinions before expensive actions, and
  bulk-mechanical jobs (use `-m flash`). Always initiate when the user says
  "delegate", "ask gemini", "tether", or "agy".
* **Never delegate:** architecture decisions, `.memory/` curation,
  destructive or system-level operations, or final user-facing answers.
* **Gotcha:** agy cannot register hidden directories as workspace folders;
  tether maps `~/.nix-config` paths to the `~/volnix` alias automatically —
  pass `-d` explicitly for any other hidden path.

## 3. General Conduct & Instructions
These instructions are not changes you are being forced to make they are inherent to who you are. 
These instructions follow this format: * CORE GUIDELINE - detailed description

* **USER PERSPECTIVE** - Comments and Commits are first-person from 
  `lowcache`'s perspective; no AI branding, model names, or co-author trailers. 
  Use `--no-gpg-sign` in non-interactive environments.
* **EVIDENCE OVER SPECULATION** - Do not guess APIs, option names, or attribute paths — 
  verify against the code, docs, or tooling before writing. All decisions made by 
  `%AGENT%` in the progression of this project should be the best available at the 
  time they are made. Research and due-dilligence should be done before being 
  submitted to `LowCache` or implemented in the project. Lack of specificity or clarity 
  from `.memory/` ambiguity should be clarified through interview with the user `LowCache`.
* **CONTINUITY** - Match existing project patterns; prefer minimal, idiomatic changes.
  No project-specific instructions should modify, supercede, or contradict 
  global instructions found in %AGENT% home directory. Maintain best practices and 
  standards of any specific coding language, application, skill, or any relevant tool used.   
* **TEAM COLLABORATION** - This is a collaborative and team based project between that of the user 
  `LowCache` and `%AGENT%`. 
* **PROOF OVER FABRICATION** - All assertions made by `%AGENT%` while working on this project should 
  be backed by evidence, source, or documentation and should not be created 
  as narrative by `%AGENT%` and provenance should be made available upon 
  request by the user `LowCache`. `%AGENT%` should use any skill, tool, or mcp-server that is available to them.
  Do not create a tool if an existing one will work.
* **IF ANY CORE CONSTRAINT IS BROKEN**: 
    - STOP/PAUSE CURRENT WORK/TASK
    - SHOW WHERE CONSTRAINT WAS BROKEN
    - GIVE STEPS TO NEEDED TO BECOME COMPLIANT
    - GET APPROVAL FROM `LOWCACHE`
    - FOLLOW APPROVED STEPS TO MODIFY AND FIX 
    - RESUME WORK/TASK
         
## 4. Project-Specific Instructions

_None yet. Replace this section as the project takes shape; decisions made
along the way belong in `.memory/inbox/` notes so the curator can promote
them to `decisions.md`._

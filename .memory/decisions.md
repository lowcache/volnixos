---
type: decisions
project: Vol NixOS
last_updated: 2026-06-12
status: active
---

# Architectural Decisions (`memory/decisions.md`)

This file catalogs the active, canonical design decisions and system configurations of **Vol NixOS**. AI agents must refer to this document before making any changes.

---

## 1. System State & Directory Mapping

* **Decision (2026-05-31):** Utilize the **Impermanence** paradigm with a volatile `tmpfs` as the root partition (`/`) to ensure a fresh, pristine system state on every boot.
* **State Persistence:** All core configurations, user data, and package caches reside on the `/persist` partition.
* **Symlink Management:** All user configuration dotfiles (e.g. Hyprland, Quickshell, Kitty, Cava, fuzzel) are stored in git under `~/.nix-config/dots/` and symlinked to `~/.config/` via `config.lib.file.mkOutOfStoreSymlink` inside [home/persist.nix](file:///home/lowcache/.nix-config/home/persist.nix).
  * *Reason:* Complete declarative tracking in git while preserving instant, live hot-reloading when editing dotfiles directly (inotify loops work across out-of-store symlinks).

---

## 2. MicroVM Host-Guest Isolated Routing

* **Decision (2026-06-01):** Establish deterministic, isolated network topology for microvm guests using static IPs:
  * Host Tap Bridge (`vm-netgate`): `192.168.100.1`; Guest (`net-gate`): `192.168.100.2` (Tor port `9040` / DNS `5353`)
  * Host Tap Bridge (`vm-tailscale`): `192.168.101.1`; Guest (`tailscale`): `192.168.101.2`
* **DHCP Disabled:** Host-side `DHCPServer` disabled on VM tap interfaces — IP shifts on VM restart would break forwarding config.
* **NetworkManager Exclusion:** All VM tap interfaces explicitly `unmanaged` to avoid allocation conflicts.

---

## 3. Nvidia Hybrid GPU Battery Optimizations

* **Decision (2026-06-01):** Configure Ollama daemon with `"OLLAMA_KEEP_ALIVE=5m"` in [configuration.nix](file:///home/lowcache/.nix-config/nixos/configuration.nix). When idle, Ollama unloads models and closes all CUDA handles, allowing RTD3 (0W) suspend. Zero UX impact: Open WebUI queries trigger model loading on demand.

---

## 4. Krita Qt6 / Wayland Compatibility Wrapper

* **Decision (2026-06-06):** Force Krita to run under XWayland via `symlinkJoin` + `makeWrapper` injecting `QT_QPA_PLATFORM=xcb` in [home/pkgs.nix](file:///home/lowcache/.nix-config/home/pkgs.nix). Reason: Krita 6 (Qt6) native Wayland causes canvas freezes and crashes on document-switching under Hyprland with hybrid GPU.

---

## 5. Secrets Location — sops or `/persist`, NEVER `dots/`

* **Decision (2026-06-09):** Secrets live in exactly two places: **sops-encrypted** (`nixos/secrets.yaml`, committable because encrypted) or **`/persist`** (never git-tracked). Never under `dots/`.
* **Reason:** `dots/` is symlinked into the **public** repo (`github.com/lowcache/volnixos`). The out-of-store symlink already serves live config — git tracking is never required. Blanket-tracking `.gemini` leaked live OAuth tokens (see mistakes.md #8).
* **Pattern:** add to `nixos/secrets.yaml` → declare `sops.secrets.<name>` in `configuration.nix` → export in `home/shell.nix` `shellInit`.
* **Adding agent/tool dirs to `dots/`:** track only declarative config; gitignore runtime/state/credential files with dir-relative patterns; never rely on git to keep a secret out.

---

## 6. Autonomous Project Memory Curation (memd)

* **Decision (2026-06-10, updated 2026-06-12):** Adopt memd for autonomous distillation of project memory files. Deployed via `home/memd.nix`; integrated into Claude Code hooks and `agy` wrapper.
* **Model & Cost Trade-off:** Haiku by default (24/7 background); Sonnet for digests >15k chars. SessionStart injection is text-only.
* **Claude-agnostic hardening (2026-06-12):** `curator_cmd` config key in `memd.py` makes the distill backend pluggable (any CLI that accepts prompt on stdin and emits JSON). Cursors advance only after successful apply — backlog survives backend swap. Antigravity reads (native SQLite) and `.memory/inbox/` interface were already agent-agnostic.
* **Persistence:** `.config/memd/` and `.local/state/memd/` are persisted in `home/persist.nix` (fixed 2026-06-12 — previously wiped on boot).
* **Scope & Constraints:** Manages only `.memory/`. Input: AI transcript backlog + inbox notes. Output: updated memory files + git commits (`.memory/` pathspec only).

---

## 7. Git Subtree for Independent Dotfiles History

* **Decision (2026-06-10):** Use `git subtree` to maintain independent, publishable history for `dots/` without a separate repository or breaking `mkOutOfStoreSymlink` mappings.
* **How it works:** Day-to-day work on main; `git subtree split --prefix=dots -b dots-history` generates a derived branch with `dots/` as repo root. `git subtree pull` merges changes from a published dotfiles remote back.
* **Trade-off:** First split on large history is slow (caches with `--rejoin`); if publishing never needed, `git log -- dots/` suffices.

---

## 8. Scoped Memory for Dotfiles (per-app and directory-wide)

* **Decision (2026-06-10):** Place dotfiles-specific memory in `dots/.memory/` (not individual app folders), with optional per-app subdirectories.
* **Structure:** `dots/.memory/{state,decisions}.md`; optional `dots/.memory/quickshell/state.md`, etc.
* **Rationale:** `dots/` itself is not symlinked (only its children); placing `.memory/` there prevents leakage into `~/.config/`, avoids home-manager rebuilds, and keeps dotfile config from mixing with app runtime state.
* **Interaction with main `.memory/`:** Both apply when working in the dotfiles tree; repo-root `.memory/` is the global source of truth.

---

## 9. Agentic Delegation — Claude Code Delegates Scoped Tasks to Gemini Pro

* **Decision (2026-06-10, updated 2026-06-12):** Enable Claude Code to decompose work into scoped task briefs and delegate to Gemini Pro via `agy`. Gemini operates in worker mode (read-only on `.memory/`, no git operations, no system rebuilds); Claude remains orchestrator and final decision-maker.
* **Implementation:** `~/.local/bin/tether` (declarative out-of-store symlink; global on PATH from 2026-06-12) → `.model/agent-tether/bin/tether` + `.model/agent-tether/PROTOCOL.md`. Default workdir: `$PWD` when non-hidden; `~/.nix-config` paths auto-map to `~/volnix`; hidden fallback to `~/volnix`. Coordination: `~/.gemini/GEMINI.md` §XIII (worker grant), `.model/CLAUDE.md` §5 (orchestrator rules), `.model/GEMINI.md` (worker pointer).
* **Auto-Initiation Criteria:** Delegate on exploratory research, parallelizable fact-gathering, second opinions before expensive actions, bulk-mechanical work. Manual: "delegate", "ask gemini", "tether", "agy".
* **Rules Out:** Delegating architecture decisions, memory curation, system rebuilds, final user-facing answers, git pushes. Worker never re-delegates, never edits `.memory/`, never modifies system state.
* **Rationale:** Leverage Gemini's research depth and parallel exploration without losing authorial ownership or synchronous control.

---

## 10. Global Agent Tooling — memd, tether, agent-scaffold Available in Every Project

* **Decision (2026-06-12):** Deploy `memd`, `tether`, and `agent-scaffold` as globally available tools, not scoped to this repo.
* **Implementation:** Declarative out-of-store symlinks in `~/.local/bin` via `home/memd.nix` (`force = true`, live-editable without rebuild, consistent with dots/ hot-reload philosophy). Sweep timer keeps hermetic Nix-store copy of memd.
* **agent-scaffold:** `scripts/agent-scaffold/agent-scaffold` (fish) + `scripts/agent-scaffold/templates/MODEL.md`. At any git root: renders `.model/{CLAUDE,AGENTS,GEMINI}.md` from template (idempotent, never overwrites); calls `memd init` when `.memory/` missing. Triggers: Claude Code `SessionStart` (before memd brief); `agy` wrapper in `home/shell.nix` (NOT a `$PWD`/cd hook — avoids littering third-party repos on directory traversal). Pattern for future agent CLIs: three-line wrapper calling `agent-scaffold` before launch.
* **Rules Out:** Hand-creating `.memory/` scaffolding (memd init only); editing generated `.model/` files to improve boilerplate (edit template instead); using a cd-hook for scaffold triggering.
* **Rationale:** The tether doctrine and memd protocol previously lived only in this repo's `.model/CLAUDE.md` §5; tether wasn't on PATH. Every new project now self-scaffolds at first session initiation, carrying the full protocol until project-specific instructions replace §4.

---
type: decisions
project: Vol NixOS
last_updated: 2026-06-10
status: active
---

# Architectural Decisions (`memory/decisions.md`)

This file catalogs the active, canonical design decisions and system configurations of **Vol NixOS**. AI agents must refer to this document before making any changes.

---

## 1. System State & Directory Mapping

* **Decision (2026-05-31):** Utilize the **Impermanence** paradigm with a volatile `tmpfs` as the root partition (`/`) to ensure a fresh, pristine system state on every boot. 
* **State Persistence:** All core configurations, user data, and package caches reside on the `/persist` partition.
* **Symlink Management:** All user configuration dotfiles (e.g. Hyprland, Quickshell, Kitty, Cava, fuzzel) are stored in git under `~/.nix-config/dots/` and symlinked to `~/.config/` via `config.lib.file.mkOutOfStoreSymlink` inside [home/persist.nix](file:///home/lowcache/.nix-config/home/persist.nix). 
  * *Reason:* This provides complete declarative tracking in git while preserving instant, live hot-reloading when editing dotfiles directly (inotify loops work perfectly across out-of-store symlinks).

---

## 2. MicroVM Host-Guest Isolated Routing

* **Decision (2026-06-01):** Establish a deterministic, isolated network topology for microvm guests using static IPs:
  * Host Tap Bridge Address (`vm-netgate`): `192.168.100.1`
  * Guest Address (`net-gate`): `192.168.100.2` (Tor transparent proxying port `9040` / DNSPort `5353`)
  * Host Tap Bridge Address (`vm-tailscale`): `192.168.101.1`
  * Guest Address (`tailscale`): `192.168.101.2` (Tailscale mesh networking gateway)
* **DHCP Disabled:** Host-side `DHCPServer` is disabled on VM tap interfaces to eliminate dynamic IP assignment hazards, ensuring network forwarding configurations never experience IP address shifts during VM restarts.
* **NetworkManager Exclusion:** All VM tap interfaces (`vm-netgate` and `vm-tailscale`) are explicitly listed as `unmanaged` in the host's NetworkManager configuration to avoid interface allocation conflicts.

---

## 3. Nvidia Hybrid GPU Battery Optimizations

* **Decision (2026-06-01):** Mitigate hybrid GPU battery drain on the laptop caused by background AI processes:
  * **Ollama Keep-Alive Timeout:** Configure the CUDA-enabled Ollama background daemon with the environment variable `"OLLAMA_KEEP_ALIVE=5m"` in [configuration.nix](file:///home/lowcache/.nix-config/nixos/configuration.nix).
  * **Mechanism:** When no AI models are actively loaded, Ollama completely unloads memory allocations and closes all Nvidia driver CUDA handles. This allows the Nvidia GPU to automatically enter the ultra-low-power Runtime suspend state (RTD3, 0W draw) when idle, extending laptop battery life.
  * **User Experience:** Zero impact on workflows. Open WebUI (`localhost:8080`) queries will dynamically trigger model loading as soon as a prompt is entered.

---

## 4. Krita Qt6 / Wayland Compatibility Wrapper

* **Decision (2026-06-06):** Force Krita to run under the X11 compatibility layer (XWayland) instead of native Wayland.
  * **Implementation:** Wrapped Krita using `symlinkJoin` and `makeWrapper` to inject `QT_QPA_PLATFORM=xcb` in [home/pkgs.nix](file:///home/lowcache/.nix-config/home/pkgs.nix).
  * **Reason:** In Krita 6 (Qt6 transition), native Wayland rendering on Hyprland (especially with Nvidia/AMD hybrid GPU systems) causes document-switching canvas freezes and application crashes. Running under X11/XWayland completely stabilizes canvas updates and tab switching.

---

## 5. Secrets Location — sops or `/persist`, NEVER `dots/`

* **Decision (2026-06-09):** Secrets (API keys, tokens, OAuth creds, private keys) live in exactly two places: **sops-encrypted** (`nixos/secrets.yaml`, committable *because* encrypted) or **`/persist`** (never git-tracked, e.g. `~/.config/sops/age/keys.txt`). They **never** go under `dots/`.
* **Reason:** `dots/` is symlinked into a **public** repo (`github.com/lowcache/volnixos`). The out-of-store symlink already serves live config from disk + `/persist` — git tracking is never required for a working config. Blanket-tracking agent dirs (`.gemini`, and the planned `.claude`) leaked live OAuth tokens to the public repo — see mistakes.md #8.
* **Pattern (three touch-points):** add to `nixos/secrets.yaml` (encrypted) → declare `sops.secrets.<name>.owner = "lowcache"` in `configuration.nix` (decrypts to `/run/secrets/<name>`) → export in `home/shell.nix` `shellInit` (`set -gx VAR (cat /run/secrets/<name>)`).
* **Adding agent/tool dirs to `dots/`:** track only declarative config; gitignore runtime/state/credential files with **dir-relative** patterns; never rely on git to keep a secret out — keep it out of the tree entirely.

---

## 6. Autonomous Project Memory Curation (memd)

* **Decision (2026-06-10):** Adopt memd (headless Claude-based curator) for autonomous distillation of project memory files (`state.md`, `decisions.md`, `todo.md`, `mistakes.md`).
* **Rationale:** AI sessions (from Claude Code, CLI agents, or swarms) naturally accumulate context (transcripts, tool calls, exploration). Without curation, memory files grow incoherent (duplicate facts, stale entries, conversational chatter). memd runs on a 30-minute systemd timer and post-session hooks to process session backlog, extract signal (decisions, state changes, constraints, gotchas, root causes, open threads), and keep memory files concise and actionable for future sessions. This prevents context buildup and keeps memory-to-noise ratio high.
* **Model & Cost Trade-off:** Haiku by default (cost-optimized for 24/7 background operations); Sonnet on demand for large/complex digests > 15k chars (better reasoning on intricate, multi-threaded changes). SessionStart injection is text-only (no synthesis — just index brief).
* **Integration:** Deployed via home-manager (`home/memd.nix`), integrated into Claude Code hooks (SessionStart for brief inject, SessionEnd/PreCompact for autonomous distill). Commits are git-audited to `.memory/` pathspec only to avoid noise; commit messages include brief summaries.
* **Scope & Constraints:** Manages only `.memory/` (not `.claude/`, not `nixos/`, not general project files). Input: AI transcript backlog + inbox notes (`.memory/inbox/`). Output: updated memory files + git commits (`.memory/` only). If a memory entry's *why* or *when* becomes unclear (no context in the repo, lost to compression), memd conservatively keeps it until manually pruned to prevent loss of institutional knowledge.

---

## 7. Git Subtree for Independent Dotfiles History

* **Decision (2026-06-10):** Use `git subtree` to maintain independent, publishable history for `dots/` directory without creating a separate repository or breaking `mkOutOfStoreSymlink` mappings.
* **How it works:** 
  * Day-to-day work stays on main branch; `dots/` is a normal subdirectory.
  * `git subtree split --prefix=dots -b dots-history` generates a derived branch containing only commits that touched `dots/`, with `dots/` rewritten as the repo root.
  * `git subtree pull --prefix=dots <remote> main` merges changes from a published dotfiles remote back into `dots/` on main.
* **Rationale:** Allows dotfiles to have independent, coherent history and be publishable to a remote (appearing as their own repo) without fragmentation. The symlinks continue to work; the split branch is a projection, not a migration.
* **Trade-off:** First `subtree split` on large history is slow (caches on subsequent runs with `--rejoin`); if publishing is never needed, simple `git log -- dots/` provides independent-view without generating a branch.

---

## 8. Scoped Memory for Dotfiles (per-app and directory-wide)

* **Decision (2026-06-10):** Place dotfiles-specific memory in `dots/.memory/` (not in individual app folders under `dots/`), with optional per-app subdirectories for granularity.
* **Structure:**
  ```
  dots/.memory/
    state.md           # dotfiles-wide state
    decisions.md       # dotfiles-wide decisions
    illogical-impulse/ # optional per-app scoping
      state.md
      mistakes.md
    quickshell/
      state.md
  ```
* **Rationale:** `dots/` itself is not symlinked (only its children); placing `.memory/` there prevents leakage into `~/.config/`, avoids triggering home-manager rebuilds, and keeps dotfile config from mixing with app runtime state. Per-app granularity is optional and avoids per-folder clutter.
* **Interaction with main `.memory/`:** Both apply when working in the dotfiles tree; repo-root `.memory/` is the global source of truth; `dots/.memory/` is the dotfiles-scoped layer.

---

## 9. Agentic Delegation — Claude Code Delegates Scoped Tasks to Gemini Pro

* **Decision (2026-06-10):** Enable Claude Code to decompose work into scoped task briefs and delegate them to Gemini Pro via a structured protocol over `agy` (Antigravity CLI). Gemini operates in worker mode (read-only on `.memory/`, no git operations, no system rebuilds); Claude remains orchestrator and final decision-maker.
* **Implementation:** `~/.nix-config/.model/agent-tether/bin/tether` (wrapper + stateful session persistence) + `~/.nix-config/.model/agent-tether/PROTOCOL.md` (shared contract, roles, report format). Coordination file locations: `~/.gemini/GEMINI.md` §XIII (worker grant), `.model/CLAUDE.md` §5 (orchestrator rules), `.model/GEMINI.md` (worker pointer).
* **Auto-Initiation Criteria:** Delegate on exploratory research ("what could we do?"), parallelizable fact-gathering, second opinions before expensive actions (rebuilds, force-pushes), bulk-mechanical work (refactoring, linting, boilerplate). Manual initiation always honored: "delegate", "ask gemini", "tether", "agy".
* **Rules Out:** Delegating architecture decisions, memory curation, system rebuilds, final user-facing answers, or pushing to git. Worker never re-delegates, never edits `.memory/`, never modifies shared system state.
* **Rationale:** Leverage Gemini's strengths (research depth, parallel exploration, sustained focus on mechanical tasks) without losing synchronous control (explicit requests always honored) or authorial ownership (all final decisions, all writes to shared state, remain with Claude/lowcache). Clear worker constraints prevent divergence and keep the repo in a known good state.

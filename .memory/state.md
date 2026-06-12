---
type: state
project: Vol NixOS
last_updated: 2026-06-12
status: active
---

# System State Inventory (`memory/state.md`)

This file is the single source of truth for the active configuration, mapping, and hardware state of **Vol NixOS**.

---

## 1. System & Hardware Profile

* **Hostname:** `volnix`
* **OS Distribution:** NixOS 26.11 (Zokor)
* **Desktop Environment / Compositor:** Hyprland (Wayland)
* **Shell:** Fish (configured via Home Manager)
* **Display Server Mappings:** Native Wayland by default; XWayland (`xwayland.enable = true`) for legacy software.
* **GPU Configuration:** Hybrid Dual GPU (AMD HawkPoint2 iGPU + NVIDIA RTX 4050 Mobile dGPU).

---

## 2. Impermanence & Persistence Mappings

Ephemeral root (`tmpfs` wiped on boot). Permanent data on `/persist`.

### User Dotfiles (Out-of-Store → Git Repo):
* `~/.config/hypr` → `/persist/home/lowcache/.nix-config/dots/hypr`
* `~/.config/quickshell` → `/persist/home/lowcache/.nix-config/dots/quickshell`
* `~/.config/kitty` → `/persist/home/lowcache/.nix-config/dots/kitty`
* `~/.config/cava` → `/persist/home/lowcache/.nix-config/dots/cava`
* `~/.config/fuzzel` → `/persist/home/lowcache/.nix-config/dots/fuzzel`
* `~/.config/wlogout` → `/persist/home/lowcache/.nix-config/dots/wlogout`
* `~/.config/starship.toml` → `/persist/home/lowcache/.nix-config/dots/starship/starship.toml`
* `~/.config/illogical-impulse` → `/persist/home/lowcache/.nix-config/dots/illogical-impulse`

### Persistent Krita Profile:
* `~/.config/kritarc` → `/home/lowcache/Storage/krita-master/kritarc`
* `~/.config/kritadisplayrc` → `/home/lowcache/Storage/krita-master/kritadisplayrc`
* `~/.local/share/krita` → `/home/lowcache/Storage/krita-master/krita`

### Persistent Application Paths:
* `~/Pictures/fromAi/outputs` → `/home/lowcache/Storage/ai-generation/fooocus/outputs`

---

## 3. Isolated MicroVM Guest Network Routing

Guests run inside systemd-wrapped MicroVM instances; VM tap interfaces `unmanaged` in NetworkManager.

* **Tor Net-Gate (`net-gate`):** Host `vm-netgate` → `192.168.100.1`; Guest → `192.168.100.2`; Transparent proxy `9040`; DNS `5353`.
* **Tailscale Gate (`tailscale-vm`):** Host `vm-tailscale` → `192.168.101.1`; Guest → `192.168.101.2`.

---

## 4. Active Workarounds and Wrappers

* **Krita Canvas Switch Freeze (Qt6 Wayland):** Wrapped via `symlinkJoin`/`makeWrapper` in `home/pkgs.nix` forcing `QT_QPA_PLATFORM=xcb`. Qt6 native Wayland crashes on tab switch with hybrid GPU under Hyprland.

* **Brave/GTK File Chooser — FIXED (2026-06-12):** Root cause: Hyprland 0.55.2 raised CAP_SYS_NICE as ambient capability for all spawned clients; xdg-desktop-portal lacked it → `/proc/<pid>/root` denial → all portal calls rejected. Fix: Hyprland 0.55.3 (PRs #14082/#14897) removes CAP_SYS_NICE from ambient set; nixpkgs bumped in commit 8af9821; rebuild + reboot completed 2026-06-12. Post-reboot: CapAmb=0, portal Settings.Read succeeds, Brave downloads functional, dbus-broker active. Fallback (pre-fix): `setpriv --ambient-caps -all --inh-caps -all <app>`.

* **Discrete GPU Battery Drain:** Ollama daemon with `"OLLAMA_KEEP_ALIVE=5m"` → VRAM unloads + CUDA handles released after idle → RTD3 (0W) suspend.

---

## 5. Secrets Management (sops-nix + age)

* **Encrypted store:** `nixos/secrets.yaml`; recipients: host ssh key (`age1eweg3j…`) + user ssh key (`age1fdm66…`). Safe to commit.
* **User editing key:** `~/.config/sops/age/keys.txt` (`AGE-SECRET-KEY-1…`, mode 600). Persisted at `/persist/home/lowcache/.config/sops/age/keys.txt`. `SOPS_AGE_KEY_FILE` set in fish `shellInit`. Edit with `sops edit <file>` (bare `sops <file>` dumps usage).
* **Declared secrets** (decrypted to `/run/secrets/<name>`): `user_password`, `root_password` (`neededForUsers`); `gemini_api_key`, `github_token` (`owner = "lowcache"`). API keys exported in fish `shellInit`: `GEMINI_API_KEY`, `GITHUB_TOKEN`.

---

## 6. Nix Binary Caches & Lix Pinning

* **Substituters:** `hyprland.cachix.org`, `nix-community.cachix.org`, `cache.lix.systems`, `cuda-maintainers.cachix.org`, `cache.numtide.com`, `attic.xuyh0120.win/lantian`. `trusted-users = [ "root" "lowcache" ]` required.
* **Lix pinning:** Keeps `inputs.nixpkgs.follows = "nixpkgs"` and `inputs.lix.url` tracking `lix` main; locked `lix=daa2bc82`, `lix-module=727d859b`. Builds from source (main never on `cache.lix.systems`). Do NOT remove overrides without eval-verifying (`nix eval …toplevel.drvPath`). See mistakes.md #7.
* **volinit input:** `github:lowcache/volinit`, locked `775d8e3`.

---

## 7. Project Memory System (memd)

* **Deployment:** 2026-06-10. Binary: `~/.local/bin/memd` (declarative out-of-store symlink → `scripts/memd/memd.py`; `force = true` in `home/memd.nix`). Hermetic Nix-store copy reserved for `memd-sweep` timer only.
* **Persistence fix (2026-06-12):** `.config/memd/` (registry, config) and `.local/state/memd/` (cursors, ag_index, locks, log) added to `home/persist.nix`. Previously wiped on boot — silent cursor reset / re-distillation of old transcripts. See mistakes.md new entry. `make switch` required to activate declaratively (imperative symlinks already live).
* **Configuration:** `~/.config/memd/config.json`. Key field: `curator_cmd` — optional argv list replacing hardcoded `claude -p` distill backend. Prompt on stdin; `{model}` substituted in argv. Output need only contain one JSON object (fences/prose tolerated). Empty = keep claude path. Cursors advance only after successful apply → backlog replays safely under a new backend. See `scripts/memd/README.md` §"Claude-code independence".
* **Sweep Timer:** `memd-sweep.timer` active; 30-min interval; auto-detects and scaffolds new git repos; distills stale projects; ingests `.memory/inbox/`. No agent CLI session required.
* **Claude Code Integration (`~/.claude/settings.json`):**
  * `SessionStart` — (1) `agent-scaffold`; (2) `memd hook session-start` (brief inject, <200 tokens, no LLM call)
  * `SessionEnd` — autonomous detached distill (Haiku; Sonnet when digest >15k chars)
  * `PreCompact` — distill before context compression
* **Antigravity Trigger:** `agy` wrapper in `home/shell.nix` runs `agent-scaffold` before Antigravity launch. Deliberately NOT a `$PWD` hook — avoids littering third-party repos on `cd`.
* **Transcript Sources:** Claude Code JSONL under `~/.claude/` (cursor-tracked by byte offset); Antigravity SQLite `~/.gemini/antigravity-cli/conversations/*.db` `steps` table, protobuf payloads (native read; legacy `.pb` skipped). Credential redaction on all digest paths.
* **Memory Scope:** `.memory/` only. Git commits limited to `.memory/` pathspec. Cross-CLI interface: drop dated markdown notes in `.memory/inbox/`.
* **Agent instruction files:** `~/.claude/CLAUDE.md` §XI, `~/.gemini/GEMINI.md` §XI, `.model/CLAUDE.md`, `.model/AGENTS.md`, `.model/GEMINI.md`.
* **Status:** Fully operational. Autonomous curation running since 2026-06-12.

---

## 8. Agentic Tether — Claude Code ↔ Gemini Pro (Established 2026-06-10)

* **Purpose:** Delegate scoped task briefs from Claude (orchestrator) to Gemini Pro (worker) via `agy`.
* **Binary:** `~/.local/bin/tether` (declarative out-of-store symlink → `.model/agent-tether/bin/tether`; `force = true` in `home/memd.nix`). Global — available from any project directory as of 2026-06-12.
* **Default Workdir (2026-06-12 change):** `$PWD` when non-hidden; paths under `~/.nix-config` or `~/volnix` auto-map to `~/volnix` alias; any other hidden path falls back to `~/volnix`. Override: `-d DIR`.
* **Shared Contract:** `.model/agent-tether/PROTOCOL.md` — roles, brief envelope format, RESULT/EVIDENCE/BLOCKERS schema, model tier defaults (Gemini 3.1 Pro High for analytical; Flash for bulk-mechanical), auto-initiation criteria.
* **Session State:** conversation IDs in `agent-tether/sessions/`; delegation log at `agent-tether/log/delegations.log`.
* **Config:** `~/.gemini/GEMINI.md` §XIII (worker grant); `.model/CLAUDE.md` §5 (orchestrator rules); `.model/GEMINI.md` (worker pointer).
* **Platform Gotchas:** (1) `agy --print` takes prompt as flag value; all other flags must precede it. (2) agy does NOT resolve symlinks for hidden-dir check. (3) Print-mode conversation resume replays previous reply before generating new one. (4) Model display labels must match `agy models` exactly.
* **Workspace Resolution:** `~/volnix` is a declarative non-hidden symlink → `~/.nix-config` (in `home/persist.nix`); tether defaults to it so agy registers a non-hidden workspace path.
* **Status:** Fully operational. Post-reboot stateful conversation resume verified 2026-06-12.

---

## 9. Agent Scaffold

* **Script:** `scripts/agent-scaffold/agent-scaffold` (fish); `~/.local/bin/agent-scaffold` (declarative out-of-store symlink via `home/memd.nix`; `force = true`).
* **Template:** `scripts/agent-scaffold/templates/MODEL.md` — rendered three times with `%AGENT%` substituted to `Claude` / `agent` / `Gemini` for `.model/CLAUDE.md` / `.model/AGENTS.md` / `.model/GEMINI.md`. Carries: memd protocol (§XI equivalent), full tether doctrine (roles, auto-initiation criteria, never-delegate list, hidden-dir gotcha), general conduct guidelines, placeholder §4 ("Project-Specific Instructions: none yet").
* **Behavior:** At any git root: renders template → `.model/` (idempotent, never overwrites); calls `memd init` when `.memory/` missing (memd registers the project). Silent no-op outside git repos and in `$HOME`.
* **Triggers:** Claude Code `SessionStart` hook (ordered before `memd hook session-start`); `agy` wrapper in `home/shell.nix` (before Antigravity launch).
* **Maintenance:** Edit `scripts/agent-scaffold/templates/MODEL.md` to update boilerplate for all future projects; never hand-edit generated `.model/` files to improve the template.

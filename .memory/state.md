---
type: state
project: Vol NixOS
last_updated: 2026-06-12
status: active
---

# System State Inventory (`memory/state.md`)

This file is the single source of truth for the active configuration, mapping, and hardware state of **Vol NixOS**. It must be updated whenever services are added, network layouts shift, or core directory targets change.

---

## 1. System & Hardware Profile

* **Hostname:** `volnix`
* **OS Distribution:** NixOS 26.11 (Zokor)
* **Desktop Environment / Compositor:** Hyprland (Wayland)
* **Shell:** Fish (configured via Home Manager)
* **Display Server Mappings:** Native Wayland by default, XWayland (via `xwayland.enable = true`) running for legacy/compatibility software.
* **GPU Configuration:** Hybrid Dual GPU (AMD HawkPoint2 iGPU + NVIDIA RTX 4050 Mobile dGPU).

---

## 2. Impermanence & Persistence Mappings

The system utilizes an ephemeral root partition (`tmpfs` wiped on boot). Permanent directories are mapped to `/persist` and symlinked to user home directory space.

### User Dotfiles (Out-of-Store Mapped to Git Repo):
* `~/.config/hypr` ➔ `/persist/home/lowcache/.nix-config/dots/hypr`
* `~/.config/quickshell` ➔ `/persist/home/lowcache/.nix-config/dots/quickshell`
* `~/.config/kitty` ➔ `/persist/home/lowcache/.nix-config/dots/kitty`
* `~/.config/cava` ➔ `/persist/home/lowcache/.nix-config/dots/cava`
* `~/.config/fuzzel` ➔ `/persist/home/lowcache/.nix-config/dots/fuzzel`
* `~/.config/wlogout` ➔ `/persist/home/lowcache/.nix-config/dots/wlogout`
* `~/.config/starship.toml` ➔ `/persist/home/lowcache/.nix-config/dots/starship/starship.toml`
* `~/.config/illogical-impulse` ➔ `/persist/home/lowcache/.nix-config/dots/illogical-impulse`

### Persistent Krita Profile (Mapped to Storage):
* `~/.config/kritarc` ➔ `/home/lowcache/Storage/krita-master/kritarc`
* `~/.config/kritadisplayrc` ➔ `/home/lowcache/Storage/krita-master/kritadisplayrc`
* `~/.local/share/krita` ➔ `/home/lowcache/Storage/krita-master/krita`

### Persistent Application Paths:
* `~/Pictures/fromAi/outputs` ➔ `/home/lowcache/Storage/ai-generation/fooocus/outputs`

---

## 3. Isolated MicroVM Guest Network Routing

Guests run inside systemd-wrapped MicroVM instances. Network interfaces are marked as `unmanaged` in NetworkManager.

* **Tor Net-Gate (`net-gate`):**
  * Host Tap Interface: `vm-netgate` (IP: `192.168.100.1`)
  * Guest VM IP: `192.168.100.2`
  * Transparent Proxy Port: `9040` (Tor)
  * DNS Proxy Port: `5353` (Tor)
* **Tailscale Gate (`tailscale-vm`):**
  * Host Tap Interface: `vm-tailscale` (IP: `192.168.101.1`)
  * Guest VM IP: `192.168.101.2`

---

## 4. Active Workarounds and Wrappers

* **Krita Canvas Switch Freeze (Qt6 Wayland Crash):**
  * **Wrapper:** Wrapped using `symlinkJoin` and `makeWrapper` in `home/pkgs.nix` to force `QT_QPA_PLATFORM=xcb`.
  * **Reason:** Qt6 native Wayland canvas redrawing crashes when switching tabs/documents under Hyprland with NVIDIA/AMD hybrid graphics.

* **Brave/GTK File Chooser Failure — FIXED (2026-06-12):**
  * **Root cause diagnosis (2026-06-12):** The nixpkgs `programs.hyprland.enable` module creates `security.wrappers.Hyprland` with `cap_sys_nice+ep`. Hyprland 0.55.2 raises this as an **ambient capability** for all spawned clients (kitty, Brave, antigravity-ide, keybind-launched apps). xdg-desktop-portal runs as a capless systemd user service. When resolving a client's app-id, the portal opens `/proc/<client>/root` (ptrace-read-gated magic symlink). The kernel denies access because target has CAP_SYS_NICE but opener lacks it → EACCES → portal app-id registration fails → **all** portal calls rejected with `AccessDenied: Unable to open /proc/<pid>/root` → file choosers broken system-wide. Diagnosis method: 2×2 matrix (openers × targets × `/proc` files) identified ptrace-READ gate; `gdbus call` reproduced exact error; `setpriv --ambient-caps -all` confirmed ambient cap was the variable. dbus-broker vs dbus-daemon red herring (both pass pidfds; the 2026-06-09 "proof" succeeded only because test ran from a terminal inheriting the same cap as clients).
  * **Fix applied (2026-06-12):** Hyprland 0.55.3 (released 2026-06-08, PRs #14082/#14897) removes CAP_SYS_NICE from ambient set. nixpkgs bump in commit 8af9821; rebuild + reboot completed. dbus-daemon workaround reverted (disproven; see mistakes.md #10).
  * **Post-reboot verification (all passed):** (1) `grep CapAmb /proc/$$/status` → `0000000000000000`; (2) `gdbus call … org.freedesktop.portal.Settings.Read` → succeeds (was AccessDenied); (3) Brave downloads, file-roller operations functional; (4) dbus-broker.service active. System fully resolved.
  * **Fallback workaround (pre-fix):** `setpriv --ambient-caps -all --inh-caps -all <app>` drops ambient caps, restoring portal access instantly (useful if Hyprland <0.55.3 deployed elsewhere).

* **Discrete GPU Battery Drain:**
  * **Daemon:** Ollama background daemon runs with `"OLLAMA_KEEP_ALIVE=5m"`.
  * **Reason:** Forces VRAM unloading and driver handle release after 5 minutes of idle time, allowing the dGPU to enter RTD3 (0W suspend state).

---

## 5. Secrets Management (sops-nix + age)

* **Encrypted store:** `nixos/secrets.yaml` (sops, age), `defaultSopsFile` in `configuration.nix`. Recipients: the **host** ssh key (`/persist/etc/ssh/ssh_host_ed25519_key` → `age1eweg3j…`, used by sops-nix at activation) and the **user** ssh key (`~/.ssh/id_ed25519` → `age1fdm66…`, used for editing). Encrypted → safe to commit.
* **User editing key:** `~/.config/sops/age/keys.txt` — native `AGE-SECRET-KEY-1…`, mode `600`, derived once from `~/.ssh/id_ed25519` via `ssh-to-age -private-key`. Persisted: `.config/sops` added to `home/persist.nix` config list **and** the key copied into `/persist/home/lowcache/.config/sops/age/keys.txt` (impermanence bind-mounts that over `~/.config/sops`; it does **not** migrate tmpfs data, so the manual copy into `/persist` is mandatory). `SOPS_AGE_KEY_FILE` set in fish `shellInit` → `sops nixos/secrets.yaml` works with no env prefix.
* **Gotcha:** `~/.ssh/id_ed25519` is passphrase-protected and sops/age cannot use an encrypted ssh key non-interactively — hence the one-time conversion to a passphrase-free native age key. CLI is `pkgs.sops` + `ssh-to-age` (`home/pkgs.nix`); edit with the `edit` subcommand (`sops edit <file>` — bare `sops <file>` dumps usage in this version).
* **Declared secrets** (`configuration.nix` `sops.secrets`, decrypted to `/run/secrets/<name>` at activation): `user_password`, `root_password` (`neededForUsers`); `gemini_api_key`, `github_token` (`owner = "lowcache"`). The two API keys export to env in fish `shellInit`: `GEMINI_API_KEY`, `GITHUB_TOKEN` ← `/run/secrets/*`.

---

## 6. Nix Binary Caches & Lix Pinning

* **Substituters** (`nixos/configuration.nix` `nix.settings`, merged with the `cache.nixos.org` default): `hyprland.cachix.org`, `nix-community.cachix.org`, `cache.lix.systems`, `cuda-maintainers.cachix.org`, `cache.numtide.com`, `attic.xuyh0120.win/lantian` — each with its trusted public key. `trusted-users = [ "root" "lowcache" ]` (required, or non-default substituters are ignored).
* **Lix pinning (2026-06-08, post-recovery):** Working state **KEEPS** the overrides — `lix-module` has `inputs.nixpkgs.follows = "nixpkgs"` and `inputs.lix.url` tracking `lix` main; locked `lix=daa2bc82`, `lix-module=727d859b`. This **builds Lix from source every switch** (slow) because main is never on `cache.lix.systems` — accepted as the cost of a working build. An attempt to remove the overrides for cache hits BROKE eval (module 2.96 vs lix 2.94-pre → removed `mdbook-linkcheck`) and was reverted via `git checkout fb63b6f`. **Do NOT** remove these overrides or `nix flake update lix-module` without eval-verifying first; real cache hits require pinning a matched Lix *release*, not main. See mistakes.md #7.
* **volinit input:** flake input label `volinit`, `github:lowcache/volinit`, locked at `775d8e3`; `infernal-init` node dropped.

---

## 7. Project Memory System (memd)

* **Deployment Date:** 2026-06-10
* **Binary Location:** `~/.local/bin/memd` (symlink, deployed via home-manager)
* **Configuration:** `~/.config/memd/config.json`
* **State & Logs:** `~/.local/state/memd/` (cursor tracking, distill history, audit log at `memd.log`)
* **Home Manager Module:** `home/memd.nix` (imported in `home/default.nix`; `memd-sweep` timer active after next `make`)
* **Claude Code Integration (hooks in `~/.claude/settings.json`):**
  * `SessionStart` — brief memory context injection (index only, <200 tokens; no LLM call)
  * `SessionEnd` — autonomous detached distill (Haiku; Sonnet when digest >15k chars)
  * `PreCompact` — distill before context compression (Haiku)
* **Transcript Sources:**
  * Claude Code: per-session JSONL under `~/.claude/` (cursor-tracked by byte offset)
  * Antigravity: `~/.gemini/antigravity-cli/conversations/*.db` — SQLite `steps` table with protobuf payloads. Attribution via content-based matching (workspace header records *launch dir*, not working dir — unreliable for project mapping; content matching required). Legacy `.pb` files skipped. 9+ conversations attributed to this repo as of 2026-06-10, baselined.
* **Credential Redaction:** All digest paths (claude, antigravity, inbox) pass a redaction filter before reaching the curator (OAuth `ya29.` tokens, GitHub PATs, `sk-` keys, AWS keys, JWTs, `*_token` JSON values).
* **Memory Scope:** `.memory/` only (`state.md`, `decisions.md`, `todo.md`, `mistakes.md`, `archive/`). Git commits limited to `.memory/` pathspec.
* **Cross-CLI/swarm interface:** Drop dated markdown notes in `.memory/inbox/`; curator ingests and deletes on next distill.
* **Agent instruction files updated (2026-06-10):** `~/.claude/CLAUDE.md` §XI, `~/.gemini/GEMINI.md` §XI, `.model/CLAUDE.md`, `.model/AGENTS.md`, `.model/GEMINI.md` — old self-managed memory protocol replaced by memd platform rules (read-only in session; inbox for deliberate notes; no direct edits).
* **Status:** Operational. First live distill 2026-06-10 (commit `d3cef27`). Sweep timer starts after next `make`.

---

## 8. Agentic Tether — Claude Code ↔ Gemini Pro (Established 2026-06-10)

* **Purpose:** Enable Claude Code to decompose work into scoped task briefs and delegate them to Gemini Pro via a structured protocol; coordinate skills, tools, and plugins autonomously or on explicit instruction.
* **Bridge Script:** `~/.nix-config/.model/agent-tether/bin/tether` — wrapper over `agy --print` (run / continue / status / log / models). Sessions persist conversation IDs in `agent-tether/sessions/`; delegation log at `agent-tether/log/delegations.log`; runtime state git-ignored.
* **Shared Contract:** `~/.nix-config/.model/agent-tether/PROTOCOL.md` — full specification of roles, brief envelope format, RESULT/EVIDENCE/BLOCKERS report schema, model tier defaults (Gemini 3.1 Pro High for analytical work; Flash Low/Medium for bulk-mechanical), auto-initiation criteria, and verified platform gotchas.
* **Config Structure:**
  * `~/.gemini/antigravity-cli/` — granular per-session settings
  * `~/.gemini/` — global skills, plugins, shared configuration
  * `~/.gemini/GEMINI.md` §XIII — worker-mode grant (sanctions `[TETHER]` envelope; §I–§XII remain fully in force)
  * `.model/CLAUDE.md` §5 — orchestrator rules (auto-initiation criteria, deferral to worker on scoped tasks)
  * `.model/GEMINI.md` — worker-side project pointer and agy platform notes
* **Workspace Resolution (2026-06-10 discovery):** agy rejects hidden directories as workspace folders ("is hidden: ignore uri"); `~/.nix-config` itself is hidden and fails registration. Workaround: `~/volnix` is a declarative non-hidden symlink added to `home/persist.nix` (force mapping `~/.nix-config` → `/persist/home/lowcache/.nix-config` → `~/volnix` at rebuild). Tether defaults to `-d ~/volnix` unless overridden with `-d <path>`. Note: agy does *not* resolve symlinks when checking for hidden paths, so the non-hidden target of the symlink (not the symlink itself) matters. File access still works via `allowNonWorkspaceAccess: true` even when workspace registration fails, but workspace context (indexing, project-aware tools) requires a non-hidden path.
* **Symlink Status (2026-06-12):** Declaratively mapped in `home/persist.nix` (verified post-reboot via `readlink -f ~/volnix`). Post-rebuild verification confirmed; activation timing works correctly.
* **Platform Gotchas Discovered (2026-06-10):**
  1. `agy --print` takes the prompt as the flag's *value*; any other flags must precede `--print`, or they are silently consumed as the prompt text.
  2. agy does NOT resolve symlinks when checking for hidden directories (checks the symlink's own path, not its target). Non-hidden symlinks register cleanly.
  3. `agy --conversation <id>` resume in print mode replays the previous assistant's reply before generating a new one. Parse the last RESULT block from the output to distinguish old reply from new.
  4. Model display labels must match `agy models` output exactly (e.g., "Gemini 3.1 Pro (High)"). Verification via `model_config_manager` log lines (`model_config_manager.go`), not model self-report in the text output.
* **Status (2026-06-12):** Fully operational. End-to-end handshake verified on Gemini 3.1 Pro (High); stateful conversation resume verified (worker correctly recalled original task name from same conversation). Committed: `a1cced5 "Establish Claude-Gemini agent tether"`.

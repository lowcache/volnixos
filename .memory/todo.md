---
type: todo
project: Vol NixOS
last_updated: 2026-06-12
status: active
---

# Open Tasks and Enhancement Roadmap (`memory/todo.md`)

---

## Completed in 2026-06-12 Session — Global Agent Tooling

* [x] **Persist memd state dirs (`home/persist.nix`):** `.config/memd` and `.local/state/memd` added; fixes silent cursor/registry wipe on boot (was a real bug).
* [x] **Global PATH tooling (`home/memd.nix`):** Declarative out-of-store symlinks (`force = true`) for `memd`, `tether`, and `agent-scaffold` in `~/.local/bin`. Sweep timer keeps hermetic Nix-store copy.
* [x] **Tether default workdir generalized:** `$PWD` when non-hidden; `~/.nix-config` paths auto-map to `~/volnix`; other hidden paths fall back to `~/volnix`. Five path cases verified.
* [x] **agent-scaffold created:** `scripts/agent-scaffold/agent-scaffold` (fish) + `scripts/agent-scaffold/templates/MODEL.md`. Renders `.model/CLAUDE.md`/`AGENTS.md`/`GEMINI.md`; calls `memd init` when `.memory/` missing. Idempotent, git-root only. End-to-end test passed.
* [x] **SessionStart hook wired:** `agent-scaffold` added before `memd hook session-start` in `~/.claude/settings.json`. JSON validated, command pipe-tested.
* [x] **memd claude-agnostic (`curator_cmd`):** Optional argv config key replacing hardcoded `claude -p` backend; cursors advance only on successful apply. `agy` wrapper in `home/shell.nix` adds second trigger. `py_compile` + `memd status` pass. README updated. `make build` passed.

---

## Pending — Immediate

* [ ] **`make switch`** to activate persistence fix (`.config/memd`, `.local/state/memd`) and declarative symlinks in `home/memd.nix`. Imperative symlinks already live and functional; switch required for declarative durability across rebuilds. Requires sudo.

---

## Known Issues & Follow-Ups

* [ ] **Re-test Super-tap search after next Hyprland bump (0.55.4+):** Hyprland 0.55.3 broke Super-tap (Super_L alone) due to catchall-bind interrupt handling change (PR #14743). Confirmed upstream regression (caelestia-dots/caelestia#436, open 2026-06-12). Workaround: comment out `searchToggleReleaseInterrupt` catchall in `dots/hypr/hyprland/keybinds.conf:11` (trade-off: lose unbound-key cancel for Super+unbound combos). See mistakes.md.
* [ ] **Stale exclude entries in memd registry:** `/tmp/scaffold-test` and `/tmp/st2` added via `memd exclude` during testing (2026-06-12). Harmless; clean up manually in `~/.config/memd/config.json` `exclude` array if desired.

---

## CRITICAL BLOCKERS (Unchanged)

* [ ] **Rotate OAuth tokens (Google/Gemini):** Live tokens exposed in public repo commit `2ccdd52` (`.gemini` dir added to `dots/`). Removed from working tree and current commits, but **remain in historical commits** on both local and remote. Repository history scrub (`git filter-repo`) still pending. See mistakes.md #8.

---

## Pending Declarative Hardening & Workaround Reversions

* [ ] **Guard `asus-shutdown` hang declaratively:** Currently mitigated by global `DefaultTimeoutStopSec=10s` + manual `kill -9`. Fix: `systemd.services.asus-shutdown.serviceConfig.SendSIGKILL = lib.mkForce true;` or per-unit `TimeoutStopSec`. Verify exact unit name via `systemctl cat asus-shutdown.service` first. (See mistakes.md #2.)
* [ ] **`limbo` plaintext passwords:** `nixos/limbo/configuration.nix` uses `initialPassword = "root"`/`"nixos"`. Acceptable for scratch; switch to `hashedPasswordFile`/sops if `limbo` ever becomes real.

---

## Pending Dotfiles Infrastructure

* [ ] **Implement git subtree Makefile targets:** `subtree-split`, `subtree-pull`, `subtree-log` for dotfiles subtree workflow. Deferred from 2026-06-10.
* [ ] **Set up `dots/.memory/` directory and scaffold:** Once subtree targets in place, create initial `state.md` for dotfiles-wide config. See decision #8.

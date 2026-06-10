---
type: todo
project: Vol NixOS
last_updated: 2026-06-10
status: active
---

# Open Tasks and Enhancement Roadmap (`memory/todo.md`)

This file catalogs open loops, enhancement ideas, and pending validation tasks for **Vol NixOS**.

---

## Completed in 2026-06-10 Session

* [x] **Fix illogical-impulse color typo:** `#90C722q` → `#90C722` in `themes/amalgamation.json` and regenerate via `apply_theme.py`. Quickshell now loads the config correctly.

---

## Pending Verification Tasks

* [ ] **Verify Brave File Chooser Dialogue:** Open Brave browser, trigger a download or upload action, and verify that the GTK/Portal file picker window displays correctly and allows saving/loading files. **Status (2026-06-10):** Still failing with the known dbus-broker pidfd bug (mistakes.md #10). Workaround (`services.dbus.implementation = "dbus"`) is in place but has not been verified post-rebuild. Gated on either: (a) rebuilding and verifying the workaround works, OR (b) waiting for `xdg-desktop-portal` ≥ 1.21.1 in nixpkgs to land and revert the workaround. See mistakes.md #10 for diagnosis and revert trigger.

* [ ] **Verify file-roller Dialogue:** Open file-roller file manager and confirm it can browse, open files, and perform archive operations without portal errors. Related to the same dbus-broker issue as Brave.

---

## Pending Agentic Tether Implementation (2026-06-10)

* [ ] **Build agentic tether between Claude Code and Antigravity/Gemini Pro:** Enable Claude Code to delegate, orchestrate, and manage tasks with Gemini Pro via `agy` CLI; initialization automatic or on explicit instruction. **Config scope:** `~/.gemini/antigravity-cli/` (granular), `~/.gemini/` (global skills/plugins), `~/.gemini/GEMINI.md` (canonical truth), plus workspace `~/.nix-config/.models/agent-tether/` (orchestration files). **Status:** Scoped; discovery phase (validating `agy` CLI, Antigravity config structure) interrupted by tool error (working directory deleted, parallel bash call cancelled). **To resume:** Validate `agy` availability and version, audit Antigravity config directories, design delegation/task-coordination protocol, and build initial orchestration templates.

---

## Pending Declarative Hardening & Workaround Reversions

* [ ] **Guard `asus-shutdown` hang declaratively:** Currently mitigated only by global `DefaultTimeoutStopSec=10s` + manual `kill -9`. Make deterministic, e.g. `systemd.services.asus-shutdown.serviceConfig.SendSIGKILL = lib.mkForce true;` or per-unit `TimeoutStopSec`. Verify exact unit name via `systemctl cat asus-shutdown.service` first. (See mistakes.md #2 for context.)

* [ ] **`limbo` plaintext passwords:** `nixos/limbo/configuration.nix` uses `initialPassword = "root"`/`"nixos"` which land world-readable in `/nix/store`. Acceptable for scratch host; switch to `hashedPasswordFile`/sops if `limbo` ever becomes real. (See mistakes.md #2 for context.)

* [ ] **Revert dbus-broker → dbus-daemon workaround:** Two sub-tasks (both open and viable):
  * Monitor packaged `xdg-desktop-portal` version on every `make update`. Currently 1.20.4 (bug fixed upstream in ≥1.21.1). Check with: `nix eval .#nixosConfigurations.volnix.config.xdg.portal.package.version`
  * When ≥1.21.1 lands: delete `services.dbus.implementation = lib.mkForce "dbus";` from `nixos/configuration.nix`, rebuild, and verify portals work: `gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Settings.ReadAll '[]'` must return a settings dict (not `AccessDenied`). (See mistakes.md #10 for full diagnosis and reversion trigger.)

---

## Pending Dotfiles Infrastructure

* [ ] **Implement git subtree Makefile targets:** Add helper targets for dotfiles subtree workflow (as per decision #7). Targets should include: `subtree-split` (generate dots-history branch), `subtree-pull` (merge from remote), `subtree-log` (view independent history). Started in session 2026-06-10 but not completed (digest truncation). Verify Makefile edits and complete if needed.

* [ ] **Set up `dots/.memory/` directory and scaffold:** Once subtree targets are in place, create `dots/.memory/` and add initial `state.md` for dotfiles-wide configuration. (See decision #8.)

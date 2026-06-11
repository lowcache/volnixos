---
type: todo
project: Vol NixOS
last_updated: 2026-06-11
status: active
---

# Open Tasks and Enhancement Roadmap (`memory/todo.md`)

This file catalogs open loops, enhancement ideas, and pending validation tasks for **Vol NixOS**.

---

## Completed in 2026-06-10 Session

* [x] **Fix illogical-impulse color typo:** `#90C722q` → `#90C722` in `themes/amalgamation.json` and regenerate via `apply_theme.py`. Quickshell now loads the config correctly.
* [x] **Establish agent tether (Claude↔Gemini delegation bridge):** Built via `~/.nix-config/.model/agent-tether/bin/tether` wrapper over `agy --print`. Verified end-to-end on Gemini 3.1 Pro (High); stateful conversation resume confirmed. Committed: `a1cced5`. See decisions.md #9 and state.md §8.

---

## CRITICAL BLOCKERS

* [ ] **Rotate OAuth tokens (Google/Gemini):** Live tokens were exposed in public repo commit `2ccdd52` (`.gemini` dir added to `dots/`, tracked despite .gitignore rules). Tokens have been removed from working tree and current commits, but **remain in historical commits** on both local and remote. **Status (2026-06-10):** Tokens are fully compromised; must be rotated immediately. Repository history scrub (via `git filter-repo --invert-paths`) still pending. See mistakes.md #8 for full diagnosis.

---

## Pending Verification Tasks

* [ ] **Verify Brave File Chooser Dialogue:** Open Brave browser, trigger a download or upload action, and verify that the GTK/Portal file picker window displays correctly and allows saving/loading files. **Status (2026-06-11):** dbus-broker portal failures confirmed post-reboot; `gdbus call` test returns `GDBus.Error:org.freedesktop.DBus.Error.AccessDenied: Portal operation not allowed: Unable to open /proc/<pid>/root`. Gated on: (a) applying the dbus-daemon workaround (`services.dbus.implementation = lib.mkForce "dbus";` in configuration.nix), rebuilding, rebooting, OR (b) `xdg-desktop-portal` ≥ 1.21.1 landing in nixpkgs (fixes pidfd bug upstream). See mistakes.md #10 for full diagnosis.

* [ ] **Verify file-roller Dialogue:** Open file-roller file manager and confirm it can browse, open files, and perform archive operations without portal errors. Related to the same dbus-broker issue as Brave. Gated on dbus-daemon workaround application.

* [ ] **Verify tuigreet environment variable loading post-rebuild:** After rebuild/reboot with the tuigreet `--env` workaround in place (or wrapper script), verify that session environment variables (GTK_USE_PORTAL, XDG_DATA_DIRS, etc.) are correctly set in the compositor session. Check via `echo $GTK_USE_PORTAL` in a terminal inside the session (should print `1`, not empty). **Status (2026-06-10):** Workaround (explicit `--env` flags to tuigreet) added; verification pending post-rebuild. See mistakes.md for prevention rule.

---

## Pending Declarative Hardening & Workaround Reversions

* [ ] **Fix volnix symlink activation timing:** The `~/volnix` symlink (declared in `home/persist.nix`, used by tether for workspace discovery) disappeared post-reboot before home-manager activation completed. Manually recreated with `ln -sn /persist/home/lowcache/.nix-config /home/lowcache/volnix`. Next session needs to move the symlink creation to NixOS system activation (before user session starts) or defer tether invocation until after home-manager completes. Verify correct approach and apply. See mistakes.md (new 2026-06-11 entry) for activation-ordering details.

* [ ] **Guard `asus-shutdown` hang declaratively:** Currently mitigated only by global `DefaultTimeoutStopSec=10s` + manual `kill -9`. Make deterministic, e.g. `systemd.services.asus-shutdown.serviceConfig.SendSIGKILL = lib.mkForce true;` or per-unit `TimeoutStopSec`. Verify exact unit name via `systemctl cat asus-shutdown.service` first. (See mistakes.md #2 for context.)

* [ ] **`limbo` plaintext passwords:** `nixos/limbo/configuration.nix` uses `initialPassword = "root"`/`"nixos"` which land world-readable in `/nix/store`. Acceptable for scratch host; switch to `hashedPasswordFile`/sops if `limbo` ever becomes real. (See mistakes.md #2 for context.)

* [ ] **Revert dbus-broker → dbus-daemon workaround:** Two sub-tasks (both open and viable):
  * Monitor packaged `xdg-desktop-portal` version on every `make update`. Currently 1.20.4 (bug fixed upstream in ≥1.21.1). Check with: `nix eval .#nixosConfigurations.volnix.config.xdg.portal.package.version`
  * When ≥1.21.1 lands: delete `services.dbus.implementation = lib.mkForce "dbus";` from `nixos/configuration.nix`, rebuild, and verify portals work: `gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Settings.ReadAll '[]'` must return a settings dict (not `AccessDenied`). (See mistakes.md #10 for full diagnosis and reversion trigger.)

---

## Pending Dotfiles Infrastructure

* [ ] **Implement git subtree Makefile targets:** Add helper targets for dotfiles subtree workflow (as per decision #7). Targets should include: `subtree-split` (generate dots-history branch), `subtree-pull` (merge from remote), `subtree-log` (view independent history). Started in session 2026-06-10 but not completed (digest truncation). Verify Makefile edits and complete if needed.

* [ ] **Set up `dots/.memory/` directory and scaffold:** Once subtree targets are in place, create `dots/.memory/` and add initial `state.md` for dotfiles-wide configuration. (See decision #8.)

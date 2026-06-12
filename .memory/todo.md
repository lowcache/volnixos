---
type: todo
project: Vol NixOS
last_updated: 2026-06-12
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

## Pending Verification & Fix Decision Tasks

* [ ] **Resolve file-chooser/portal bug (CAP_SYS_NICE root cause):** Diagnosis complete (2026-06-12); real root cause is Hyprland ambient CAP_SYS_NICE blocking xdg-portal ptrace, **not** dbus-broker. Two fix candidates: **(A) surgical—drop cap from wrapper** (`security.wrappers.Hyprland` via `lib.mkForce`; loses compositor SCHED_RR); **(B) patch xdg-portal to handle EACCES gracefully** (preserves Hyprland performance). Gemini's upstream research (tether task `portal-cap-upstream-research`, delegated 2026-06-12) underway to check if upstream portal already has a published fix. **Immediate workaround for any broken app:** `setpriv --ambient-caps -all --inh-caps -all <app>`. **Action:** (1) Await Gemini research; (2) if no upstream patch, decide A vs B; (3) apply fix and verify `gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Settings.ReadAll '[]'` returns a settings dict (not `AccessDenied`).

* [ ] **Verify Brave File Chooser Dialogue:** Open Brave browser, trigger a download or upload action, and verify that the GTK/Portal file picker window displays correctly and allows saving/loading files. **Status (2026-06-12):** Portal calls return `GDBus.Error:org.freedesktop.DBus.Error.AccessDenied` due to CAP_SYS_NICE ptrace block (see above). Workaround: `setpriv --ambient-caps -all brave` succeeds. Verification deferred until fix candidate A or B is applied.

* [ ] **Verify file-roller Dialogue:** Open file-roller file manager and confirm it can browse, open files, and perform archive operations without portal errors. Gated on portal fix (same root cause as Brave).

* [ ] **Verify tuigreet environment variable loading post-rebuild:** After rebuild/reboot with the tuigreet `--env` workaround in place (or wrapper script), verify that session environment variables (GTK_USE_PORTAL, XDG_DATA_DIRS, etc.) are correctly set in the compositor session. Check via `echo $GTK_USE_PORTAL` in a terminal inside the session (should print `1`, not empty). **Status (2026-06-10):** Workaround (explicit `--env` flags to tuigreet) added; verification pending post-rebuild. See mistakes.md for prevention rule.

---

## Pending Declarative Hardening & Workaround Reversions

* [ ] **Fix volnix symlink activation timing:** The `~/volnix` symlink (declared in `home/persist.nix`, used by tether for workspace discovery) disappeared post-reboot before home-manager activation completed. Manually recreated with `ln -sn /persist/home/lowcache/.nix-config /home/lowcache/volnix`. Next session needs to move the symlink creation to NixOS system activation (before user session starts) or defer tether invocation until after home-manager completes. Verify correct approach and apply. See mistakes.md (2026-06-11 entry) for activation-ordering details.

* [ ] **Revert dbus-broker → dbus-daemon workaround (SAFE TO REMOVE; WAS WRONG):** **Update (2026-06-12):** The hypothesis in mistakes.md #10 is disproven. dbus-daemon 1.16.2 also passes pidfds (`ProcessFD`); the 2026-06-09 "proof" succeeded only because the test ran from a terminal, inheriting the same ambient cap as clients. The real root cause is Hyprland CAP_SYS_NICE (see above). The `services.dbus.implementation = lib.mkForce "dbus";` workaround is a no-op; revert it back to default `"broker"` after applying the final CAP_SYS_NICE fix (to verify broker still works). Action: (1) Delete the `services.dbus.implementation` line from `nixos/configuration.nix`; (2) rebuild; (3) reboot; (4) verify file choosers work (portal fix from above must be in place).

* [ ] **Guard `asus-shutdown` hang declaratively:** Currently mitigated only by global `DefaultTimeoutStopSec=10s` + manual `kill -9`. Make deterministic, e.g. `systemd.services.asus-shutdown.serviceConfig.SendSIGKILL = lib.mkForce true;` or per-unit `TimeoutStopSec`. Verify exact unit name via `systemctl cat asus-shutdown.service` first. (See mistakes.md #2 for context.)

* [ ] **`limbo` plaintext passwords:** `nixos/limbo/configuration.nix` uses `initialPassword = "root"`/`"nixos"` which land world-readable in `/nix/store`. Acceptable for scratch host; switch to `hashedPasswordFile`/sops if `limbo` ever becomes real. (See mistakes.md #2 for context.)

---

## Pending Dotfiles Infrastructure

* [ ] **Implement git subtree Makefile targets:** Add helper targets for dotfiles subtree workflow (as per decision #7). Targets should include: `subtree-split` (generate dots-history branch), `subtree-pull` (merge from remote), `subtree-log` (view independent history). Started in session 2026-06-10 but not completed (digest truncation). Verify Makefile edits and complete if needed.

* [ ] **Set up `dots/.memory/` directory and scaffold:** Once subtree targets are in place, create `dots/.memory/` and add initial `state.md` for dotfiles-wide configuration. (See decision #8.)

---
type: todo
project: Vol NixOS
last_updated: 2026-06-12
status: active
---

# Open Tasks and Enhancement Roadmap (`memory/todo.md`)

---

## Completed in 2026-06-12 Session

* [x] **Fix eval blockers (nixpkgs bump migration):** (1) `systemd.user.extraConfig = "DefaultTimeoutStopSec=5s"` → `systemd.user.settings.Manager.DefaultTimeoutStopSec = "5s"` in `nixos/configuration.nix:117`; (2) `nixpkgs-fmtrrrr` → `nixpkgs-fmt` typo in `home/pkgs.nix:170`. Eval now clean. Committed in pending rebuild.
* [x] **Revert dbus-broker → dbus-daemon workaround (SAFE TO REMOVE; WAS WRONG):** `services.dbus.implementation = lib.mkForce "dbus"` removed from `nixos/configuration.nix`. Hypothesis in mistakes.md #10 (dbus-broker pidfd) is **proven incorrect** — dbus-daemon 1.16.2 also passes pidfds; the 2026-06-09 "proof" succeeded only because test ran from terminal inheriting ambient cap as clients. Real root cause is Hyprland CAP_SYS_NICE (see mistakes.md entry below). dbus-broker re-enabled as default (per uwsm). Bundled with rebuild.
* [x] **Apply Hyprland 0.55.3 (Option A for CAP_SYS_NICE fix):** nixpkgs bump bundled in commit 8af9821; dry-run eval confirms Hyprland 0.55.3 in closure (released 2026-06-08). Rebuild + reboot completed.
* [x] **Verify Hyprland CAP_SYS_NICE fix and portal restoration post-rebuild:** All checks passed in fresh terminal post-reboot: (1) `grep CapAmb /proc/$$/status` → `0000000000000000`; (2) `gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Settings.Read "org.freedesktop.appearance" "color-scheme"` → `(<<uint32 0>>,)` (was AccessDenied); (3) Brave downloads, file-roller operations functional; (4) dbus-broker.service active. See state.md §4 for full details.
* [x] **Verify volnix symlink activation post-rebuild:** `readlink -f ~/volnix` → `/persist/home/lowcache/.nix-config`. Declaratively mapped in `home/persist.nix`; no longer requires manual recreation. Fully functional.

---

## Known Issues & Follow-Ups

* [ ] **Re-test Super-tap search after next Hyprland bump (0.55.4+):** Hyprland 0.55.3 broke Super-tap (Super_L alone) due to catchall-bind interrupt handling change (PR #14743). Confirmed as known upstream regression (caelestia-dots/caelestia#436, open as of 2026-06-12). Workaround: comment out `searchToggleReleaseInterrupt` catchall in `dots/hypr/hyprland/keybinds.conf:11`, but that removes unbound-key cancel protection. If 0.55.4+ upstream fixes it, remove this task and simplify keybinds.conf. See mistakes.md for full diagnosis.

---

## CRITICAL BLOCKERS (Unchanged)

* [ ] **Rotate OAuth tokens (Google/Gemini):** Live tokens were exposed in public repo commit `2ccdd52` (`.gemini` dir added to `dots/`). Tokens removed from working tree and current commits, but **remain in historical commits** on both local and remote. Repository history scrub still pending. See mistakes.md #8.

---

## Pending Declarative Hardening & Workaround Reversions

* [ ] **Guard `asus-shutdown` hang declaratively:** Currently mitigated only by global `DefaultTimeoutStopSec=10s` + manual `kill -9`. Make deterministic, e.g. `systemd.services.asus-shutdown.serviceConfig.SendSIGKILL = lib.mkForce true;` or per-unit `TimeoutStopSec`. Verify exact unit name via `systemctl cat asus-shutdown.service` first. (See mistakes.md #2 for context.)

* [ ] **`limbo` plaintext passwords:** `nixos/limbo/configuration.nix` uses `initialPassword = "root"`/`"nixos"` which land world-readable in `/nix/store`. Acceptable for scratch host; switch to `hashedPasswordFile`/sops if `limbo` ever becomes real. (See mistakes.md #2 for context.)

---

## Pending Dotfiles Infrastructure

* [ ] **Implement git subtree Makefile targets:** Add helper targets for dotfiles subtree workflow (split, pull, log). Deferred from 2026-06-10 session (digest truncation). Targets should include: `subtree-split` (generate dots-history branch), `subtree-pull` (merge from remote), `subtree-log` (view independent history).

* [ ] **Set up `dots/.memory/` directory and scaffold:** Once subtree targets are in place, create initial `state.md` for dotfiles-wide configuration. Optional per-app subdirectories for granularity. See decision #8.

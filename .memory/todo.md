---
type: todo
project: Vol NixOS
last_updated: 2026-06-12
status: active
---

# Open Tasks and Enhancement Roadmap (`memory/todo.md`)

---

## Completed in 2026-06-12 Session

* [x] **Fix eval blockers (nixpkgs bump migration):** (1) `systemd.user.extraConfig = "DefaultTimeoutStopSec=5s"` → `systemd.user.settings.Manager.DefaultTimeoutStopSec = "5s"` in `nixos/configuration.nix:117` (option deprecated/removed in new nixpkgs); (2) `nixpkgs-fmtrrrr` → `nixpkgs-fmt` typo in `home/pkgs.nix:170`. Eval now clean. Committed in pending rebuild.
* [x] **Revert dbus-broker → dbus-daemon workaround (SAFE TO REMOVE; WAS WRONG):** `services.dbus.implementation = lib.mkForce "dbus"` removed from `nixos/configuration.nix`. Hypothesis in mistakes.md #10 (dbus-broker pidfd) is **proven incorrect** — dbus-daemon 1.16.2 also passes pidfds; the 2026-06-09 "proof" succeeded only because test ran from terminal inheriting ambient cap as clients. Real root cause is Hyprland CAP_SYS_NICE (see todo item below). dbus-broker re-enabled as default (per uwsm `--force`). Bundled with rebuild.
* [x] **Apply Hyprland 0.55.3 (Option A for CAP_SYS_NICE fix):** nixpkgs bump bundled; dry-run eval confirms Hyprland 0.55.3 in pending closure (released 2026-06-08, fixes ambient cap inheritance). Rebuild imminent (tty2 session).

---

## IN PROGRESS (Post-Rebuild Verification Pending)

* [ ] **Verify Hyprland CAP_SYS_NICE fix and portal restoration post-rebuild:** Post-switch on tty2, run in fresh terminal: (1) `grep CapAmb /proc/$$/status` → should be all zeros (`0000000000000000`); (2) `gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Settings.Read "org.freedesktop.appearance" "color-scheme"` → should return `(<<uint32 0>>,)` (not `AccessDenied` error); (3) Brave Browser download dialog (Ctrl+Shift+J, trigger download) and file-roller archive operations (open file chooser); (4) `readlink ~/volnix` → `/persist/home/lowcache/.nix-config` (declarative symlink). If failures persist, troubleshoot with immediate workaround: `setpriv --ambient-caps -all <app>`. See state.md §4 and mistakes.md for full context.

---

## CRITICAL BLOCKERS (Unchanged)

* [ ] **Rotate OAuth tokens (Google/Gemini):** Live tokens were exposed in public repo commit `2ccdd52` (`.gemini` dir added to `dots/`). Tokens removed from working tree and current commits, but **remain in historical commits** on both local and remote. Repository history scrub still pending. See mistakes.md #8.

---

## Pending Declarative Hardening & Workaround Reversions

* [ ] **Verify volnix symlink activation post-rebuild:** `~/volnix` declaratively mapped in `home/persist.nix` (no longer manually recreated). Post-rebuild, verify `readlink ~/volnix` → `/persist/home/lowcache/.nix-config`. If missing after session boot, check `home/default.nix` import and home-manager activation timing vs. tether first-use.

* [ ] **Guard `asus-shutdown` hang declaratively:** Currently mitigated only by global `DefaultTimeoutStopSec=10s` + manual `kill -9`. Make deterministic, e.g. `systemd.services.asus-shutdown.serviceConfig.SendSIGKILL = lib.mkForce true;` or per-unit `TimeoutStopSec`. Verify exact unit name via `systemctl cat asus-shutdown.service` first. (See mistakes.md #2 for context.)

* [ ] **`limbo` plaintext passwords:** `nixos/limbo/configuration.nix` uses `initialPassword = "root"`/`"nixos"` which land world-readable in `/nix/store`. Acceptable for scratch host; switch to `hashedPasswordFile`/sops if `limbo` ever becomes real. (See mistakes.md #2 for context.)

---

## Pending Dotfiles Infrastructure

* [ ] **Implement git subtree Makefile targets:** Add helper targets for dotfiles subtree workflow (split, pull, log). Deferred from 2026-06-10 session (digest truncation). Targets should include: `subtree-split` (generate dots-history branch), `subtree-pull` (merge from remote), `subtree-log` (view independent history).

* [ ] **Set up `dots/.memory/` directory and scaffold:** Once subtree targets are in place, create initial `state.md` for dotfiles-wide configuration. Optional per-app subdirectories for granularity. See decision #8.

---
type: todo
project: Vol NixOS
last_updated: 2026-06-10
status: active
---

# Open Tasks and Enhancement Roadmap (`memory/todo.md`)

This file catalogs open loops, enhancement ideas, and pending validation tasks for **Vol NixOS**.

---

## Pending Verification Tasks

* [ ] **Verify Brave File Chooser Dialogue:** Open Brave browser, trigger a download or upload action, and verify that the GTK/Portal file picker window displays correctly and allows saving/loading files. (Gated on xdg-desktop-portal ≥ 1.21.1; see mistakes.md #10 for full diagnosis and reversion trigger.)

---

## Pending Declarative Hardening & Workaround Reversions

* [ ] **Guard `asus-shutdown` hang declaratively:** Currently mitigated only by global `DefaultTimeoutStopSec=10s` + manual `kill -9`. Make deterministic, e.g. `systemd.services.asus-shutdown.serviceConfig.SendSIGKILL = lib.mkForce true;` or per-unit `TimeoutStopSec`. Verify exact unit name via `systemctl cat asus-shutdown.service` first. (See mistakes.md #2 for context.)

* [ ] **`limbo` plaintext passwords:** `nixos/limbo/configuration.nix` uses `initialPassword = "root"`/`"nixos"` which land world-readable in `/nix/store`. Acceptable for scratch host; switch to `hashedPasswordFile`/sops if `limbo` ever becomes real. (See mistakes.md #2 for context.)

* [ ] **Revert dbus-broker → dbus-daemon workaround:** Two sub-tasks (both open and viable):
  * Monitor packaged `xdg-desktop-portal` version on every `make update`. Currently 1.20.4 (bug fixed upstream in ≥1.21.1). Check with: `nix eval .#nixosConfigurations.volnix.config.xdg.portal.package.version`
  * When ≥1.21.1 lands: delete `services.dbus.implementation = lib.mkForce "dbus";` from `nixos/configuration.nix`, rebuild, and verify portals work: `gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Settings.ReadAll '[]'` must return a settings dict (not `AccessDenied`). (See mistakes.md #10 for full diagnosis and reversion trigger.)

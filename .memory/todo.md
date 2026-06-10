---
type: todo
project: Vol NixOS
last_updated: 2026-06-10
status: active
---

# Open Tasks and Enhancement Roadmap (`memory/todo.md`)

This file catalogs open loops, enhancement ideas, and pending validation tasks for **Vol NixOS**.

---

## 1. Pending Verification Tasks (Immediate Priority)

* [x] **Verify Ollama VRAM Unloading (2026-06-10):** Confirmed that Ollama unloads VRAM after 5 minutes of idle time per `OLLAMA_KEEP_ALIVE=5m` configuration. GPU power draw drops to suspend levels (0W–2W).
* [x] **Verify Fooocus Outputs Symlink (2026-06-10):** Confirmed that `~/Pictures/fromAi/outputs` correctly resolves to `/home/lowcache/Storage/ai-generation/fooocus/outputs` and images can be read/written.
* [ ] **Verify Brave File Chooser Dialogue:** Open Brave browser, trigger a download or upload action, and verify that the GTK/Portal file picker window displays correctly and allows saving/loading files. (Gated on dbus-broker → dbus-daemon workaround and/or xdg-desktop-portal ≥ 1.21.1; see todo.md §2.)

---

## 2. Declarative Hardening & Scheduled Reversions (discovered during 2026-06-01 audit)

* [ ] **Guard `asus-shutdown` hang declaratively:** `memory/mistakes.md#2` is currently only mitigated by the global `DefaultTimeoutStopSec=10s` plus a manual `kill -9`. Make it deterministic, e.g. `systemd.services.asus-shutdown.serviceConfig.SendSIGKILL = lib.mkForce true;` (or a short per-unit `TimeoutStopSec`). VERIFY the exact unit name (`systemctl cat asus-shutdown.service`) before adding the override so we don't create a phantom unit.
* [ ] **`limbo` plaintext passwords:** `nixos/limbo/configuration.nix` uses `initialPassword = "root"`/`"nixos"`, which land world-readable in `/nix/store`. Acceptable for a scratch host; switch to `hashedPasswordFile`/sops if `limbo` ever becomes real.
* [ ] **Revert dbus-broker → dbus-daemon workaround** once xdg-desktop-portal is fixed in nixpkgs. Currently forcing `services.dbus.implementation = lib.mkForce "dbus";` to work around upstream portal bug #1953 (pidfd path triggers bad `O_NOFOLLOW` open of `/proc/<pid>/root`, breaking all portals). Full diagnosis: mistakes.md #10. Fixed upstream in 1.21.x/1.22.0 line; as of 2026-06, **nixpkgs unstable + 26.11 still ship 1.20.4** (buggy version).
  * On every `make update`, check packaged portal version: `nix eval .#nixosConfigurations.volnix.config.xdg.portal.package.version 2>/dev/null` (currently 1.20.4).
  * When it reaches **≥ 1.21.1**: delete the `dbus.implementation = lib.mkForce "dbus";` line, rebuild, and verify portal is functional: `gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Settings.ReadAll '[]'` (must return a settings dict, not `AccessDenied`).

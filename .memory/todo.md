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

* [ ] **Verify Ollama VRAM Unloading:** After running a model in Open WebUI, wait 5 minutes and run `nvidia-smi` to verify that Ollama unloads the model from VRAM, showing `0 MiB` usage, and that the Nvidia GPU power draw drops to suspend levels (0W–2W).
* [x] **Verify MicroVM Static Connectivity (2026-06-09, post-volnix switch):** `net-gate` auto-starts (`microvm.vms.net-gate.autostart = true`, `nixos/vms.nix:9`) — `ping 192.168.100.2` OK, tap `vm-netgate` up at `192.168.100.1`. **`tailscale` is `autostart = false`** (`nixos/vms.nix:107`) — on-demand BY DESIGN; `192.168.101.2` / `vm-tailscale` tap absent until `sudo systemctl start microvm@tailscale.service`. Not a regression.
* [ ] **Verify Fooocus Outputs Symlink:** Access `~/Pictures/fromAi/outputs` to verify the symlink correctly resolves to `/home/lowcache/Storage/ai-generation/fooocus/outputs` and that images can be read/written.
* [ ] **Verify Brave File Chooser Dialogue:** Open Brave browser, trigger a download or upload action, and verify that the GTK/Portal file picker window displays correctly and allows saving/loading files.

---

## 2. Recommended Configuration Enhancements

* [ ] **Host-Independence for Rebuild Scripts:** Generalize `home/shell.nix` aliases (e.g. `nxrbs` and `nxrbb`) to dynamic paths like `~/.nix-config` instead of hardcoding `/persist/home/lowcache` to prevent crash behaviors on non-persistent hosts (like `limbo`).
* [ ] **Generalize priv-sync Sync Paths:** Modify `LIVE_HOME` inside `priv-sync` in `home/shell.nix` to use Home Manager variables dynamically (e.g., `${config.home.homeDirectory}`) instead of a hardcoded path.
* [ ] **Replace Docker Device option for Fooocus:** In `nixos/configuration.nix`, update the Fooocus docker container parameter `extraOptions` from the Kubernetes-style `["--device" "nvidia.com/gpu=0"]` to standard Docker GPU offloading `["--gpus" "all"]` to prevent container initialization failures.
  * *Caveat (2026-06-01):* `hardware.nvidia-container-toolkit.enable = true` generates CDI specs, and `nvidia.com/gpu=0` IS the modern CDI device form the toolkit expects. Verify the container actually fails to start before switching — `--gpus all` is the older runtime-hook style and may not be an improvement here.

---

## 3. Declarative Hardening (discovered during 2026-06-01 audit)

* [ ] **Guard `asus-shutdown` hang declaratively:** `memory/mistakes.md#2` is currently only mitigated by the global `DefaultTimeoutStopSec=10s` plus a manual `kill -9`. Make it deterministic, e.g. `systemd.services.asus-shutdown.serviceConfig.SendSIGKILL = lib.mkForce true;` (or a short per-unit `TimeoutStopSec`). VERIFY the exact unit name (`systemctl cat asus-shutdown.service`) before adding the override so we don't create a phantom unit.
* [ ] **Define or drop the `forge` container:** `forggo`/`forgstp` aliases in `home/shell.nix` were commented out because no `docker-forge.service` exists (only `fooocus`). Either declare a `forge` oci-container in `nixos/configuration.nix` (the `Storage/ai-generation/forge` tmpfiles dir is already created) and re-enable the aliases, or remove them.
* [ ] **`.gitignore` footgun:** `nixos/*.yaml` silently ignores any NEW yaml dropped in `nixos/` (current `secrets.yaml`/`.sops.yaml` survive only because they were force-added). Consider narrowing the rule so a future secret file isn't lost.
* [ ] **`limbo` plaintext passwords:** `nixos/limbo/configuration.nix` uses `initialPassword = "root"`/`"nixos"`, which land world-readable in `/nix/store`. Acceptable for a scratch host; switch to `hashedPasswordFile`/sops if `limbo` ever becomes real.

---

## 4. De-Infernal Rebrand — COMPLETE (2026-06-10)

All renames applied, switch live on `volnix`, commits pushed to `github.com/lowcache/volnixos.git`.

* [x] Hostname `infernalnix` → `volnix`; `nixosConfigurations.volnix`, `networking.hostName`, Makefile, shell aliases, README updated.
* [x] Repo renamed `infernalnixos` → `volnixos`; remote URL + clone URL + flake description URL updated.
* [x] `infernal-init` → `volinit` flake input flipped; locked at `775d8e3`; eval-verified.
* [x] Safe `switch --flake .#volnix` performed (2026-06-09); rebrand commits pushed (2026-06-10).
* [ ] Optional cosmetic: `mv ~/CodeRepo/infernal-init ~/CodeRepo/volinit` (dir name only; live build uses `github:lowcache/volinit`).

---

## 5. Revert dbus-broker → dbus-daemon workaround once portal is fixed in nixpkgs (added 2026-06-09)

We force `services.dbus.implementation = lib.mkForce "dbus";` (nixos/configuration.nix) to dodge upstream xdg-desktop-portal bug #1953 — broker's pidfd path triggers a bad `O_NOFOLLOW` open of `/proc/<pid>/root`, breaking ALL portals (file chooser, downloads). Full diagnosis: mistakes.md #10. Fixed upstream in the 1.21.x/1.22.0 line, but as of 2026-06 **nixpkgs unstable + 26.11 still ship 1.20.4** (the buggy version).

* [ ] **On every `make update`, check the packaged portal version** until resolved:
      `nix eval .#nixosConfigurations.volnix.config.xdg.portal.package.version 2>/dev/null`
      **Installed/running now: 1.20.4.**
* [ ] When it reaches **≥ 1.21.1**: delete the `dbus.implementation = lib.mkForce "dbus";` line, rebuild, and verify:
      `gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Settings.ReadAll '[]'`
      (must return a settings dict, not `AccessDenied`).

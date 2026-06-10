---
type: todo
project: Vol NixOS
last_updated: 2026-06-10
status: active
---

# Open Tasks and Enhancement Roadmap (`memory/todo.md`)

This file catalogs open loops, enhancement ideas, and pending validation tasks for **Vol NixOS**.

---

## 0. ACTIVATION DRIFT — running system is behind the repo (found 2026-06-01)

* **Critical:** A build audit showed the live box is NOT running this config:
  * `booted-system` = `...-infernalnix-26.05.20260515` (old generation, pre-reboot)
  * `current-system` = a `26.11.20260531` build switched live ~15:27 (no reboot since)
  * `nixos-rebuild build` of current HEAD produces a THIRD, different store path
* **Proof the fix never activated:** the running generation still has the *misspelled* `~/Pictures/fromAi/ouputs` symlink pointing INTO `/nix/store/.../home-manager-files/...ouputs` — i.e. the pre-`mistakes.md#4` state. The repo source is correct (`outputs`, out-of-store to `Storage`), but it was committed and never switched. **`mistakes.md#4` is fixed in source, NOT on the machine.**
* **Consequence:** todo.md §1 checks below "fail" mostly because the config isn't live, not because it's wrong. MicroVM `net-gate` (autostart) is `inactive (dead)` since 16:35; taps absent; pings fail.
* **Action:** Do a clean `switch` the SAFE way (per `mistakes.md#1` — session restart kills it): run inside `tmux`/`systemd-run --scope`, e.g.
  `systemd-run --scope --user-unit=rebuild bash -c 'sudo nixos-rebuild switch --flake ~/.nix-config#volnix'`
  then re-run §1 verifications. The build itself is confirmed green (exit 0).

---

## 1. Pending Verification Tasks (Immediate Priority)

* [ ] **Verify Ollama VRAM Unloading:** After running a model in Open WebUI, wait 5 minutes and run `nvidia-smi` to verify that Ollama unloads the model from VRAM, showing `0 MiB` usage, and that the Nvidia GPU power draw drops to suspend levels (0W–2W).
* [x] **Verify MicroVM Static Connectivity (2026-06-09, post-volnix switch):** `net-gate`
      auto-starts (`microvm.vms.net-gate.autostart = true`, `nixos/vms.nix:9`) — `ping 192.168.100.2`
      OK, tap `vm-netgate` up at `192.168.100.1`. **`tailscale` is `autostart = false`**
      (`nixos/vms.nix:107`) — it is **on-demand BY DESIGN**, so `192.168.101.2` / the `vm-tailscale`
      tap will NOT exist until `sudo systemctl start microvm@tailscale.service`. A dead
      `192.168.101.2` is NOT a regression — do not chase it as a fault. (Flip to `autostart = true`
      only if always-on tailscale is wanted.)
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

## 4. De-Infernal Rebrand — rename "infernal" out of everything (IN PROGRESS 2026-06-08)

**Name LOCKED: `vol`** (chosen for the volatile/impermanent tmpfs-root architecture; "clever but
ambiguous to performance", reads as volatile-memory/volume not failure). Derived tokens:
host `volnix`, repo `vol-nixos`, flake input `vol-init`, brand text "Vol NixOS".
`lowcache` stays the GitHub handle/umbrella; only project names change. Cross-repo effort,
coordinated with `infernal-init` (repo+binary) and `infernalcode`/`infernalbits`.

* **DONE in THIS repo (`~/.nix-config`), 2026-06-08 — internal renames only, no rebuild run:**
  * [x] Hostname `infernalnix` → **`volnix`** — `nixosConfigurations.volnix` (flake.nix),
        `networking.hostName` (nixos/configuration.nix), `HOST` (Makefile), `nxrbs`/`nxrbb`
        (home/shell.nix), README rebuild commands + `limbo` prose.
        ⚠️ **Activation:** next switch MUST target `#volnix`; bare `nixos-rebuild` keyed on the
        live hostname `infernalnix` will fail until the box switches and renames itself.
  * [x] Flake `description` brand "Infernal NixOS" → "Vol NixOS" (repo URL left until rename).
  * [x] `.memory/*` + `.model/*` brand text "Infernal NixOS"/"Infernal" → "Vol NixOS"/"Vol"
        (this header set). `infernal-init`/`infernalnixos` tokens deliberately preserved.
* **DONE 2026-06-08 (cont.) — repo `infernalnixos` → `volnixos`:** GitHub rename live; this repo's
  `git remote set-url origin git@github.com:lowcache/volnixos.git` done; clone URL (README L203)
  + flake `description` URL flipped to `volnixos.git`.
* **DONE 2026-06-08 — `infernal-init` → `volinit` input flip:** upstream `volinit` pushed
  (commit `775d8e3`, `result/bin/volinit` build-verified). Flipped here: flake input label +
  url `github:lowcache/volinit`, `home/pkgs.nix` `inputs.volinit`, the `volinit` binary call +
  `vol` abbr (home/shell.nix L86-87,120), README §2.3. `nix flake lock` locked `volinit` →
  `775d8e3` and dropped the `infernal-init` node (Lix pins untouched). **Eval-verified:**
  `…volnix…toplevel.drvPath` → `nixos-system-volnix-26.11…drv` (exit 0).
* **REMAINING (lowcache):**
  * [ ] **Activate:** safe `switch --flake .#volnix` inside `tmux`/`systemd-run` (mistakes.md #1).
        Reboot afterward to load the volnix-built kernel/nvidia modules (mistakes.md #6).
  * [ ] Optional housekeeping: `mv ~/CodeRepo/infernal-init ~/CodeRepo/volinit` (README now points
        there; the live build uses `github:lowcache/volinit`, so the dir name is cosmetic).
  * [ ] Commit the `~/.nix-config` rebrand (working tree still dirty as of this entry).
* Context also lives in `infernal-init/.memory/todo.md`. Banner already reads "LowCache"; if a
  separate banner brand is wanted it needs figlet/tagline re-render in the infernal-init repo.

---

## 5. Revert dbus-broker → dbus-daemon workaround once portal is fixed in nixpkgs (added 2026-06-09)

We force `services.dbus.implementation = lib.mkForce "dbus";` (nixos/configuration.nix) to dodge
upstream xdg-desktop-portal bug #1953 — broker's pidfd path triggers a bad `O_NOFOLLOW` open of
`/proc/<pid>/root`, breaking ALL portals (file chooser, downloads). Full diagnosis: mistakes.md #10.
Fixed upstream in the 1.21.x/1.22.0 line, but as of 2026-06 **nixpkgs unstable + 26.11 still ship
1.20.4** (the buggy version).

* [ ] **On every `make update`, check the packaged portal version** until resolved:
      `nix eval --raw .#nixosConfigurations.volnix.config.environment.systemPackages 2>/dev/null`
      is noisy; simplest is to check the running/derivation version, e.g.
      `nix eval .#nixosConfigurations.volnix.config.xdg.portal.package.version 2>/dev/null` or look
      for `xdg-desktop-portal-1.2x` in the new system closure. **Installed/running now: 1.20.4.**
* [ ] When it reaches **≥ 1.21.1**: delete the `dbus.implementation = lib.mkForce "dbus";` line
      (returns the session bus to broker + restores pidfd credential checking), rebuild, and verify
      the file chooser with:
      `gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.Settings.ReadAll '[]'`
      (must return a settings dict, not `AccessDenied`).

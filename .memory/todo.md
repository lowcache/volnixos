---
type: todo
project: Infernal NixOS
last_updated: 2026-06-08
status: active
---

# Open Tasks and Enhancement Roadmap (`memory/todo.md`)

This file catalogs open loops, enhancement ideas, and pending validation tasks for **Infernal NixOS**.

---

## 0. ACTIVATION DRIFT — running system is behind the repo (found 2026-06-01)

* **Critical:** A build audit showed the live box is NOT running this config:
  * `booted-system` = `...-infernalnix-26.05.20260515` (old generation, pre-reboot)
  * `current-system` = a `26.11.20260531` build switched live ~15:27 (no reboot since)
  * `nixos-rebuild build` of current HEAD produces a THIRD, different store path
* **Proof the fix never activated:** the running generation still has the *misspelled* `~/Pictures/fromAi/ouputs` symlink pointing INTO `/nix/store/.../home-manager-files/...ouputs` — i.e. the pre-`mistakes.md#4` state. The repo source is correct (`outputs`, out-of-store to `Storage`), but it was committed and never switched. **`mistakes.md#4` is fixed in source, NOT on the machine.**
* **Consequence:** todo.md §1 checks below "fail" mostly because the config isn't live, not because it's wrong. MicroVM `net-gate` (autostart) is `inactive (dead)` since 16:35; taps absent; pings fail.
* **Action:** Do a clean `switch` the SAFE way (per `mistakes.md#1` — session restart kills it): run inside `tmux`/`systemd-run --scope`, e.g.
  `systemd-run --scope --user-unit=rebuild bash -c 'sudo nixos-rebuild switch --flake ~/.nix-config#infernalnix'`
  then re-run §1 verifications. The build itself is confirmed green (exit 0).

---

## 1. Pending Verification Tasks (Immediate Priority)

* [ ] **Verify Ollama VRAM Unloading:** After running a model in Open WebUI, wait 5 minutes and run `nvidia-smi` to verify that Ollama unloads the model from VRAM, showing `0 MiB` usage, and that the Nvidia GPU power draw drops to suspend levels (0W–2W).
* [ ] **Verify MicroVM Static Connectivity:** Run `ping 192.168.100.2` and `ping 192.168.101.2` from the host to verify that the `net-gate` and `tailscale` guest MicroVMs are fully accessible via their new static IP allocations.
* [ ] **Verify Fooocus Outputs Symlink:** Access `~/Pictures/fromAi/outputs` to verify the symlink correctly resolves to `/home/lowcache/Storage/ai-generation/fooocus/outputs` and that images can be read/written.

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

## 4. De-Infernal Rebrand — rename "infernal" out of everything (QUEUED 2026-06-08)

lowcache is removing the literal **"infernal"** brand from ALL projects/repos and replacing it
with a name **NOT YET DECIDED**. `lowcache` stays the GitHub handle/umbrella; only project names
change. Cross-repo effort, coordinated with `infernal-init` (repo+binary) and `infernalcode`/
`infernalbits`. Wait for the chosen name before starting.

* **Scope in THIS repo (`~/.nix-config`):**
  * [ ] Repo name `infernalnixos` (remote `git@github.com:lowcache/infernalnixos.git`).
  * [ ] Hostname **`infernalnix`** — `nixosConfigurations.infernalnix`, used in rebuild
        commands / `make switch` / flake refs. ⚠️ Rename deliberately; it affects activation.
  * [ ] Flake `description = "Infernal NixOS - Imprecation & Impermanence by LowCache ..."`.
  * [ ] The `infernal-init` flake input (name + URL) — renames in lockstep with that repo.
  * [ ] `.memory/*` `project: Infernal NixOS` headers + any "Infernal" references.
* Context lives in `infernal-init/.memory/todo.md` (the rename is its NEXT ACTIVE TASK) and the
  session auto-memory. Note: the banner already reads "LowCache"; if the final name ≠ LowCache,
  the banner figlet/tagline need re-rendering too.

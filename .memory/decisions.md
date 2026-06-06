# Architectural Decisions (`memory/decisions.md`)

This file catalogs the active, canonical design decisions and system configurations of **Infernal NixOS**. AI agents must refer to this document before making any changes.

---

## 1. System State & Directory Mapping

* **Decision (2026-05-31):** Utilize the **Impermanence** paradigm with a volatile `tmpfs` as the root partition (`/`) to ensure a fresh, pristine system state on every boot. 
* **State Persistence:** All core configurations, user data, and package caches reside on the `/persist` partition.
* **Symlink Management:** All user configuration dotfiles (e.g. Hyprland, Quickshell, Kitty, Cava, fuzzel) are stored in git under `~/.nix-config/dots/` and symlinked to `~/.config/` via `config.lib.file.mkOutOfStoreSymlink` inside [home/persist.nix](file:///home/lowcache/.nix-config/home/persist.nix). 
  * *Reason:* This provides complete declarative tracking in git while preserving instant, live hot-reloading when editing dotfiles directly (inotify loops work perfectly across out-of-store symlinks).

---

## 2. MicroVM Host-Guest Isolated Routing

* **Decision (2026-06-01):** Establish a deterministic, isolated network topology for microvm guests using static IPs:
  * Host Tap Bridge Address (`vm-netgate`): `192.168.100.1`
  * Guest Address (`net-gate`): `192.168.100.2` (Tor transparent proxying port `9040` / DNSPort `5353`)
  * Host Tap Bridge Address (`vm-tailscale`): `192.168.101.1`
  * Guest Address (`tailscale`): `192.168.101.2` (Tailscale mesh networking gateway)
* **DHCP Disabled:** Host-side `DHCPServer` is disabled on VM tap interfaces to eliminate dynamic IP assignment hazards, ensuring network forwarding configurations never experience IP address shifts during VM restarts.
* **NetworkManager Exclusion:** All VM tap interfaces (`vm-netgate` and `vm-tailscale`) are explicitly listed as `unmanaged` in the host's NetworkManager configuration to avoid interface allocation conflicts.

---

## 3. Nvidia Hybrid GPU Battery Optimizations

* **Decision (2026-06-01):** Mitigate hybrid GPU battery drain on the laptop caused by background AI processes:
  * **Ollama Keep-Alive Timeout:** Configure the CUDA-enabled Ollama background daemon with the environment variable `"OLLAMA_KEEP_ALIVE=5m"` in [configuration.nix](file:///home/lowcache/.nix-config/nixos/configuration.nix).
  * **Mechanism:** When no AI models are actively loaded, Ollama completely unloads memory allocations and closes all Nvidia driver CUDA handles. This allows the Nvidia GPU to automatically enter the ultra-low-power Runtime suspend state (RTD3, 0W draw) when idle, extending laptop battery life.
  * **User Experience:** Zero impact on workflows. Open WebUI (`localhost:8080`) queries will dynamically trigger model loading as soon as a prompt is entered.

---

## 4. Krita Qt6 / Wayland Compatibility Wrapper

* **Decision (2026-06-06):** Force Krita to run under the X11 compatibility layer (XWayland) instead of native Wayland.
  * **Implementation:** Wrapped Krita using `symlinkJoin` and `makeWrapper` to inject `QT_QPA_PLATFORM=xcb` in [home/pkgs.nix](file:///home/lowcache/.nix-config/home/pkgs.nix).
  * **Reason:** In Krita 6 (Qt6 transition), native Wayland rendering on Hyprland (especially with Nvidia/AMD hybrid GPU systems) causes document-switching canvas freezes and application crashes. Running under X11/XWayland completely stabilizes canvas updates and tab switching.


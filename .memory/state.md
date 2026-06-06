---
type: state
project: Infernal NixOS
last_updated: 2026-06-06
status: active
---

# System State Inventory (`memory/state.md`)

This file is the single source of truth for the active configuration, mapping, and hardware state of **Infernal NixOS**. It must be updated whenever services are added, network layouts shift, or core directory targets change.

---

## 1. System & Hardware Profile

* **Hostname:** `infernalnix`
* **OS Distribution:** NixOS 26.11 (Zokor)
* **Desktop Environment / Compositor:** Hyprland (Wayland)
* **Shell:** Fish (configured via Home Manager)
* **Display Server Mappings:** Native Wayland by default, XWayland (via `xwayland.enable = true`) running for legacy/compatibility software.
* **GPU Configuration:** Hybrid Dual GPU (AMD HawkPoint2 iGPU + NVIDIA RTX 4050 Mobile dGPU).

---

## 2. Impermanence & Persistence Mappings

The system utilizes an ephemeral root partition (`tmpfs` wiped on boot). Permanent directories are mapped to `/persist` and symlinked to user home directory space.

### User Dotfiles (Out-of-Store Mapped to Git Repo):
* `~/.config/hypr` ➔ `/persist/home/lowcache/.nix-config/dots/hypr`
* `~/.config/quickshell` ➔ `/persist/home/lowcache/.nix-config/dots/quickshell`
* `~/.config/kitty` ➔ `/persist/home/lowcache/.nix-config/dots/kitty`
* `~/.config/cava` ➔ `/persist/home/lowcache/.nix-config/dots/cava`
* `~/.config/fuzzel` ➔ `/persist/home/lowcache/.nix-config/dots/fuzzel`
* `~/.config/wlogout` ➔ `/persist/home/lowcache/.nix-config/dots/wlogout`
* `~/.config/starship.toml` ➔ `/persist/home/lowcache/.nix-config/dots/starship/starship.toml`

### Persistent Krita Profile (Mapped to Storage):
* `~/.config/kritarc` ➔ `/home/lowcache/Storage/krita-master/kritarc`
* `~/.config/kritadisplayrc` ➔ `/home/lowcache/Storage/krita-master/kritadisplayrc`
* `~/.local/share/krita` ➔ `/home/lowcache/Storage/krita-master/krita`

### Persistent Application Paths:
* `~/Pictures/fromAi/outputs` ➔ `/home/lowcache/Storage/ai-generation/fooocus/outputs`

---

## 3. Isolated MicroVM Guest Network Routing

Guests run inside systemd-wrapped MicroVM instances. Network interfaces are marked as `unmanaged` in NetworkManager.

* **Tor Net-Gate (`net-gate`):**
  * Host Tap Interface: `vm-netgate` (IP: `192.168.100.1`)
  * Guest VM IP: `192.168.100.2`
  * Transparent Proxy Port: `9040` (Tor)
  * DNS Proxy Port: `5353` (Tor)
* **Tailscale Gate (`tailscale-vm`):**
  * Host Tap Interface: `vm-tailscale` (IP: `192.168.101.1`)
  * Guest VM IP: `192.168.101.2`

---

## 4. Active Workarounds and Wrappers

* **Krita Canvas Switch Freeze (Qt6 Wayland Crash):**
  * **Wrapper:** Wrapped using `symlinkJoin` and `makeWrapper` in `home/pkgs.nix` to force `QT_QPA_PLATFORM=xcb`.
  * **Reason:** Qt6 native Wayland canvas redrawing crashes when switching tabs/documents under Hyprland with NVIDIA/AMD hybrid graphics.
* **Discrete GPU Battery Drain:**
  * **Daemon:** Ollama background daemon runs with `"OLLAMA_KEEP_ALIVE=5m"`.
  * **Reason:** Forces VRAM unloading and driver handle release after 5 minutes of idle time, allowing the dGPU to enter RTD3 (0W suspend state).

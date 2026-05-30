# Resolving GPU-Related Screen and Laptop Freezes

This plan addresses screen and laptop freezes on your hybrid AMD CPU/iGPU + NVIDIA RTX 4050 dGPU laptop under NixOS (using Hyprland).

## User Review Required

> [!IMPORTANT]
> The primary cause of the severe screen and laptop lockups is the global environment variables defined in your Home Manager configuration (`home/session.nix`). 
> Setting `__NV_PRIME_RENDER_OFFLOAD = "1"`, `__GLX_VENDOR_LIBRARY_NAME = "nvidia"`, and `GBM_BACKEND = "nvidia-drm"` globally forces your entire desktop session (including Hyprland) to run on your dedicated NVIDIA GPU rather than your integrated AMD GPU.
> Under Wayland (Hyprland), running the main compositor on the dGPU in a hybrid setup causes extreme instability, prevents the dGPU from sleeping, and leads to hard lockups when power transitions occur. We will disable these global variables so that the desktop runs on the stable AMD iGPU, while you can still run heavy games/apps on the NVIDIA GPU on-demand using your existing `nvrun` helper alias.

> [!WARNING]
> We will disable `supergfxd` (the GPU-switching daemon) in your `nixos/configuration.nix`.
> The `supergfxd` daemon conflicts directly with your hardcoded NixOS `hardware.nvidia.prime.offload` settings. When both are active, `supergfxd` unloads modules dynamically, causing the graphics stack to lock up and freeze. Using standard PRIME offload is the most stable and recommended configuration under NixOS for modern laptops.

> [!TIP]
> We will change `hardware.nvidia.open = false;` to use the proprietary NVIDIA driver instead of the open-source kernel modules, and set `powerManagement.finegrained = true;`. 
> The `nvidia-open` modules compile against the running kernel, which can lead to severe conflicts/crashes with your highly optimized, custom-patched `cachyos` kernel. The proprietary driver is much more stable here. Furthermore, enabling `finegrained` power management allows the RTX 4050 to sleep in the deepest D3cold low-power state when not in use, which prevents lockups during state transitions and saves battery.

## Proposed Changes

---

### Home Manager Configuration

#### [MODIFY] [session.nix](file:///home/nondeus/.nix-config/home/session.nix)
- Comment out the global Nvidia environment variables so that the desktop session (Hyprland) renders on the integrated AMD GPU.
- Users can run specific apps on the NVIDIA GPU using the existing shell alias `nvrun`.

---

### NixOS System Configuration

#### [MODIFY] [configuration.nix](file:///home/nondeus/.nix-config/nixos/configuration.nix)
- Set `services.supergfxd.enable = false;` to prevent conflicts with standard NixOS PRIME offload.

#### [MODIFY] [hardware-configuration.nix](file:///home/nondeus/.nix-config/nixos/hardware-configuration.nix)
- Set `hardware.nvidia.open = false;` to use the more stable proprietary NVIDIA driver kernel modules.
- Set `hardware.nvidia.powerManagement.finegrained = true;` to allow dynamic power-saving states for your RTX 4050 GPU, preventing freezes during power transitions.

## Verification Plan

### Automated Tests
- Run `nix flake check` or `nixos-rebuild build` to verify the configuration syntax is 100% correct and builds without compilation/syntax errors:
  ```bash
  nix flake check --flake /home/nondeus/.nix-config
  ```

### Manual Verification
- Rebuild and switch your NixOS configuration:
  ```bash
  sudo nixos-rebuild switch --flake /home/nondeus/.nix-config/#nondeus
  ```
- Reboot the system.
- Run `hyprctl gpubind` or check the loaded kernel modules/GPU power status.
- Verify the desktop runs smoothly on the AMD GPU, and verify you can launch specific heavy workloads on the Nvidia GPU using `nvrun <application-name>`.

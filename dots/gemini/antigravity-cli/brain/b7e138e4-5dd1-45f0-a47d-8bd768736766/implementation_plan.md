# Hybrid GPU System Freeze and Stability Solution (Updated)

A detailed plan to resolve system freezes and kernel panics on an AMD Ryzen + NVIDIA RTX 4050 hybrid laptop running NixOS. This plan consolidates all browser configurations into a single `browsers.nix` file (replacing `brave.nix`), keeps Brave with custom stability flags, removes standard Chromium, adds Floorp (Firefox fork) as a stable backup, and applies crucial kernel stability parameters.

## User Review Required

> [!IMPORTANT]
> To address your modularity request and ensure complete system stability:
> 1. **Consolidated Browser Configuration:** Instead of creating multiple new files, we will rename/transition `brave.nix` to a single `browsers.nix` file. This single file will configure both Brave (with stability flags) and install Floorp (`floorp-bin`).
> 2. **Brave Stability Flags:** We will add the `--disable-features=WaylandWpColorManagerV1` flag to Brave's `commandLineArgs` to prevent Wayland-specific GPU hangs under Hyprland.
> 3. **Remove Chromium:** We will remove the standard `chromium` package from your `pkgs.nix` file.
> 4. **Apply General System Stability Fixes:** We will add essential kernel parameters to `configuration.nix` to handle AMD iGPU display power management, CPU C-states, and PCIe link transitions.

## Proposed Changes

---

### NixOS Kernel Configuration

#### [MODIFY] [configuration.nix](file:///home/nondeus/.nix-config/nixos/configuration.nix)

Add critical stability parameters to `boot.kernelParams` to resolve AMD iGPU display power management hangs, Ryzen C-state crashes, and PCIe power conflicts:
* `amdgpu.dcdebugmask=0x10`: Disables Panel Self Refresh (PSR) on the AMD 780M, which is the most common source of iGPU display freezes.
* `amdgpu.gpu_recovery=1`: Enables automatic AMD GPU driver resets so any minor graphical hang does not lock up the kernel.
* `processor.max_cstate=5`: Prevents deep CPU C-state transitions that cause sudden hardware freezes on mobile Ryzen 7000 series chips.
* `pcie_port_pm=off`: Disables PCIe port power management, preventing the PCIe link from hanging during NVIDIA dGPU power-state handoffs.

---

### Home Manager Package & Browser Configuration

#### [MODIFY] [pkgs.nix](file:///home/nondeus/.nix-config/home/pkgs.nix)
* Remove `chromium` from the `hyprland` package list.

#### [MODIFY] [default.nix](file:///home/nondeus/.nix-config/home/default.nix)
* Replace `./brave.nix` with `./browsers.nix` in the imported modules list.

#### [DELETE] [brave.nix](file:///home/nondeus/.nix-config/home/brave.nix)
* Remove the old Brave-only configuration file.

#### [NEW] [browsers.nix](file:///home/nondeus/.nix-config/home/browsers.nix)
* Create a single, consolidated browser configuration module:

```nix
{ config, pkgs, lib, ... }: {
  # Brave Browser (Primary)
  programs.chromium = {
    enable = true;
    package = pkgs.brave;
    commandLineArgs = [
      "--ozone-platform-hint=auto"
      "--disable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoEncoder,WaylandWpColorManagerV1"
      "--disable-gpu-memory-buffer-video-frames"
      "--enable-features=TouchpadOverscrollHistoryNavigation"
      "--enable-gpu-rasterization"
      "--enable-oop-rasterization"
      "--enable-zero-copy"
    ];
  };

  # Floorp Browser (Stable Firefox Fork Backup)
  home.packages = [
    pkgs.floorp-bin
  ];
}
```

## Verification Plan

### Automated Tests
* Validate the NixOS configuration using:
  ```bash
  nix flake check /home/nondeus/.nix-config
  ```

### Manual Verification
1. Apply the configuration using `nixos-rebuild switch --flake /home/nondeus/.nix-config#nondeus`.
2. Verify that the new kernel parameters are active after a reboot:
  ```bash
  cat /proc/cmdline
  ```
3. Launch Brave and verify that it starts up and hardware acceleration works without system freezing.
4. Launch Floorp and verify smooth rendering and operation.
5. Run Ollama services and Open-WebUI alongside the browsers to verify overall system stability.

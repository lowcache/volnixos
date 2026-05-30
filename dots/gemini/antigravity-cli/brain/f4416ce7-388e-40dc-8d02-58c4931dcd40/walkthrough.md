# GPU Freezing Resolution Walkthrough

The configuration changes to address GPU-related freezes on your hybrid AMD + NVIDIA laptop have been successfully applied and verified.

## Summary of Accomplishments

### 1. Fixed Session Environment Variables
- **File:** [session.nix](file:///home/nondeus/.nix-config/home/session.nix#L46-L51)
- **Change:** Commented out the system-wide global NVIDIA environment variables (`GBM_BACKEND = "nvidia-drm";`, `__NV_PRIME_RENDER_OFFLOAD = "1";`, `__GLX_VENDOR_LIBRARY_NAME = "nvidia";`, `__VK_LAYER_NV_optimus = "NVIDIA_only";`, and `LIBVA_DRIVER_NAME = "nvidia";`).
- **Impact:** Hyprland and standard user interface components will now run on the stable integrated AMD GPU. Heavy workloads can still be offloaded on-demand using your existing `nvrun` helper alias.

### 2. Resolved Service Conflicts
- **File:** [configuration.nix](file:///home/nondeus/.nix-config/nixos/configuration.nix#L239)
- **Change:** Disabled `services.supergfxd.enable = true` by changing it to `false`.
- **Impact:** Prevents the `supergfxd` dynamic GPU switching daemon from conflicting with the hardcoded NixOS PRIME offload configuration, which previously led to graphical and module deadlocks.

### 3. Configured Stable Driver & Dynamic Power Management
- **File:** [hardware-configuration.nix](file:///home/nondeus/.nix-config/nixos/hardware-configuration.nix#L25-L30)
- **Change:** 
  - Changed `hardware.nvidia.open = true;` to `false` to use the proprietary NVIDIA kernel modules.
  - Changed `hardware.nvidia.powerManagement.finegrained = false;` to `true` to enable dynamic run-time D3cold power management.
- **Impact:** The proprietary driver resolves stability issues with compiling open-source modules against the custom-patched CachyOS kernel, and `finegrained` power management lets the RTX 4050 dGPU dynamically enter a deep sleep state when idle, avoiding power transition lockups.

### 4. Corrected Pre-existing Flake Compilation Bug
- **File:** [flake.nix](file:///home/nondeus/.nix-config/flake.nix#L62)
- **Change:** Fixed the package output path for the MicroVM guest system from `config.microvm` to `config.config.microvm`.
- **Impact:** Resolved a compilation error that previously caused `nix flake check` to fail on evaluation.

---

## Validation Results

We performed automated syntactical and semantic validation checks:

1. **Host Build dry-run check:**
   ```bash
   nix build /home/nondeus/.nix-config#nixosConfigurations.nondeus.config.system.build.toplevel --no-link --dry-run
   ```
   * **Result:** **Success**. All configurations parsed correctly, and all required derivations generated successfully.
   
2. **Flake syntax and consistency check:**
   ```bash
   nix flake check /home/nondeus/.nix-config --no-build
   ```
   * **Result:** **Success**. The flake successfully evaluated all configurations and attributes.

---

## Next Steps

To apply these modifications to your active system:
1. Rebuild and switch your NixOS configuration by executing:
   ```bash
   nxrbs
   ```
   *(Which calls `sudo nixos-rebuild switch --flake /persist/home/nondeus/.nix-config/#nondeus`)*
2. Reboot your laptop:
   ```bash
   reboot
   ```

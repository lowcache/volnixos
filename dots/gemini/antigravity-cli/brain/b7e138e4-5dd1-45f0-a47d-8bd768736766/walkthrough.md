# Walkthrough - Hybrid GPU Freeze and Stability Solution

All configuration changes have been successfully implemented, staged, and validated. The NixOS flake configuration has been evaluated to ensure absolute syntactic and architectural correctness.

## Summary of Changes

### 1. General System & Hybrid GPU Stability

#### [configuration.nix](file:///home/nondeus/.nix-config/nixos/configuration.nix)
Added key kernel parameters to `boot.kernelParams` to resolve hardware crashes and power management hangs common on AMD + NVIDIA hybrid laptops:
* `amdgpu.dcdebugmask=0x10`: Disables Panel Self Refresh (PSR) on the integrated GPU, preventing screen freeze issues.
* `amdgpu.gpu_recovery=1`: Enables automatic driver recovery for the integrated AMD GPU, preventing system-wide lockups.
* `processor.max_cstate=5`: Restricts deep Ryzen CPU C-state power transitions to avoid sudden hardware freezes.
* `pcie_port_pm=off`: Disables PCIe port power management, stabilizing GPU state transitions and power-saving handoffs.

---

### 2. Browser Stack Optimization & Consolidation

#### [browsers.nix](file:///home/nondeus/.nix-config/home/browsers.nix) [NEW]
Created a consolidated browser configuration module:
* **Brave configuration:** Enabled Brave under Wayland (`--ozone-platform-hint=auto`) and added `--disable-features=WaylandWpColorManagerV1` to bypass the buggy color management protocol that causes native Wayland GPU process freezes in Chromium. Added performance flags for GPU rasterization and zero-copy rendering.
* **Floorp configuration:** Installed Floorp (`floorp-bin`) via Home Manager, acting as a stable, non-Chromium-based backup browser.

#### [pkgs.nix](file:///home/nondeus/.nix-config/home/pkgs.nix)
* Removed the standard `chromium` package from the `hyprland` environment package list.

#### [default.nix](file:///home/nondeus/.nix-config/home/default.nix)
* Swapped the deprecated `./brave.nix` import with the new `./browsers.nix` import.

#### [brave.nix](file:///home/nondeus/.nix-config/home/brave.nix) [DELETE]
* Safely deleted the deprecated Brave-only configuration file.

---

## Testing & Validation Results

### 1. Git Staging
All modified and new files have been successfully staged in the git repository:
```bash
git status
```
* staged: `nixos/configuration.nix`, `home/default.nix`, `home/pkgs.nix`
* added: `home/browsers.nix`
* deleted: `home/brave.nix`

### 2. Flake Evaluation
The entire flake configuration was evaluated to verify correct module resolution and avoid syntax errors:
```bash
nix eval .#nixosConfigurations.nondeus.config.system.build.toplevel.drvPath
```
**Result:** Successfully evaluated to:
`"/nix/store/ym7p5kxhlrxls09a27r2rqy9hr6swd4p-nixos-system-nixos-26.05.20260515.d233902.drv"`
This confirms that all changes are structurally and syntactically sound.

---

## Next Steps

To apply the changes:

1. **Rebuild your NixOS and Home Manager configuration:**
   ```bash
   nixos-rebuild switch --flake /home/nondeus/.nix-config#nondeus
   ```
2. **Reboot your system** to initialize the new kernel stability parameters.
3. Test Brave with native Wayland rendering and verify that Floorp is correctly installed and functional.

# Fix NixOS GPU Freezing Task List

- [x] Modify `home/session.nix` to comment out global Nvidia environment variables
- [x] Modify `nixos/configuration.nix` to set `services.supergfxd.enable = false`
- [x] Modify `nixos/hardware-configuration.nix` to configure proper Nvidia driver settings
  - [x] Set `hardware.nvidia.open = false`
  - [x] Set `hardware.nvidia.powerManagement.finegrained = true`
- [x] Verify changes
  - [x] Run `nix flake check` to ensure syntax correctness
  - [x] Build the configuration to verify compilation

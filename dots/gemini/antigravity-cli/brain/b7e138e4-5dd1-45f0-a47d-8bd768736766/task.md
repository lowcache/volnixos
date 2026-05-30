# Task: Hybrid GPU System Freeze and Stability Solution

- `[x]` Configure NixOS kernel stability parameters in `nixos/configuration.nix`
- `[x]` Remove `chromium` package from `home/pkgs.nix`
- `[x]` Create consolidated `home/browsers.nix` for Brave and Floorp
- `[x]` Update Home Manager module imports in `home/default.nix` to use `browsers.nix` instead of `brave.nix`
- `[x]` Delete old `home/brave.nix` configuration file
- `[x]` Validate the NixOS flake configuration

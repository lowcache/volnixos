---
name: nix-home-manager-expert
description: Deep expertise in designing, packaging, and maintaining modular Home Manager user profiles, interactive shells, custom window managers (Hyprland), and symlinked dotfile structures on NixOS.
---

# Nix Home Manager Expert Instruction Set

When this skill is active, you must evaluate, layout, and troubleshoot user-space environments under standard modular Home Manager constraints.

## Core Directives

1. **User-Space Modularity:**
   - Organize home configurations into dedicated files (e.g. `shell.nix`, `pkgs.nix`, `session.nix`, `browsers.nix`).
   - Import modules cleanly via the `imports` block under `home-manager` configurations.

2. **Aesthetic Dotfiles & Symlinks:**
   - Manage user config files using out-of-store symlinks (`config.lib.file.mkOutOfStoreSymlink`) mapping the git config workspace directories to `$HOME/.config/` paths. This keeps changes live and editable.
   - Design configurations to support dynamic theme systems (like matching colors with structural roles across Kitty, Starship, and Hyprland).

3. **Window Session & App Managers:**
   - Configure Wayland window managers (Hyprland) executing under Universal Wayland Session Manager (UWSM) boundaries to ensure clean systemd environment imports.
   - Map GTK/Qt theme modules, desktop portal layers, and unmanaged tap boundaries gracefully.

4. **Interactive Shells & Aliases:**
   - Construct robust Fish configuration blocks containing custom functions, completions, welcome graphics (`infernal-init`), and quick navigational shortcuts.

5. **No GPG Sign Hangs:**
   - Commit any modifications using the `--no-gpg-sign` flag exclusively to prevent execution stalls.

## Execution Tools
- **`home-manager generations`**: Lists active and historic user environment generations.
- **`home-manager switch`**: Compiles and activates user-space configurations.

# Implementation Plan - Nix-on-Droid Samsung Galaxy S26 Ultra & Laptop Integration

Refactoring your existing monolithic `Infernal NixOS` repository into a clean, modular structure. This allows sharing your core terminal tools, prompt styling, Git settings, and editor preferences with your Samsung Galaxy S26 Ultra (`aarch64-linux`) while completely isolating laptop-specific hardware packages, display servers, and systemd modules.

---

## User Review Required

> [!NOTE]
> **Modularity Strategy**: 
> * We will extract the shared terminal configuration (starship, git settings, micro configuration, and standard fish shell parameters) into a common platform-agnostic layer.
> * Machine-specific details (e.g., desktop window manager options, Lanzaboote, MicroVMs, systemd modules, and `/persist` absolute paths) will reside in host-specific configurations.

> [!WARNING]
> **Proot and Systemd Limitations on Android**:
> * Because Android utilizes unprivileged `proot` sandboxing, systemd configs inside `home/session.nix` will cause build errors if loaded on the phone. This plan moves them exclusively into the desktop layer.
> * Impermanence is unsupported on Android; all absolute persistent routes (`/persist`) are isolated from the phone's Home Manager profile.

---

## Open Questions

> [!IMPORTANT]
> 1. **Shizuku Integration Pathing**:
>    * Would you prefer to store the `rish` (Shizuku) wrapper script directly in your declarative configuration repository, or would you prefer to keep it managed locally on the device (generating the template via the Shizuku app and placing it in a git-ignored directory like `~/.local/bin/`)?
> 2. **Android Package Selection**:
>    * Are there any specific network utilities or development libraries you want included on the S26 Ultra that should not be on your desktop, or do you want to keep the package manifest minimal?

---

## Proposed Changes

We will split configurations under `home/` into a platform-agnostic core (`home/common.nix`, `home/shell-common.nix`), a desktop-specialized profile (`home/desktop.nix`), and a mobile-specialized profile (`home/droid.nix`).

### 1. Platform-Agnostic Core

Separates pure command-line interfaces and environments from display managers and hardware parameters.

#### [NEW] [common.nix](file:///home/nondeus/.nix-config/home/common.nix)
* A platform-agnostic profile that loads shared terminal environments:
  ```nix
  { config, pkgs, lib, ... }: {
    imports = [ ./shell-common.nix ];
    home.stateVersion = "24.11";
  }
  ```

#### [NEW] [shell-common.nix](file:///home/nondeus/.nix-config/home/shell-common.nix)
* Contains core Fish settings, standard CLI aliases (e.g., `ls` as `eza`, `..`, `extract`, `rmspcs`), global Git properties, Starship prompts, Direnv hooks, and Micro syntax highlight settings.

---

### 2. Desktop-Specific Modules

Preserves your Hyprland, Wayland, Brave, GPG keys, systemd services, and state persistence configs.

#### [NEW] [desktop.nix](file:///home/nondeus/.nix-config/home/desktop.nix)
* Imports `home/common.nix` alongside laptop-specific configurations: `home/pkgs.nix`, `home/session.nix`, `home/persist.nix`, and `home/brave.nix`.
* Implements systemd configurations (e.g., `services.ssh-agent.enable = true`).
* Restores desktop-only terminal shortcuts (such as `nvrun`, `bootbios`, `nxrbs`, `wifi`) and complex desktop script functions (`setwall` and `priv-sync`).

#### [DELETE] [default.nix](file:///home/nondeus/.nix-config/home/default.nix)
* Replaced by `home/desktop.nix` to prevent monolithic package resolution.

#### [DELETE] [shell.nix](file:///home/nondeus/.nix-config/home/shell.nix)
* Replaced by `home/shell-common.nix` and `home/desktop.nix` Fish profiles.

---

### 3. Android-Specific Modules

Configures settings, utilities, and bindings tailored for the Snapdragon processor.

#### [NEW] [droid.nix](file:///home/nondeus/.nix-config/home/droid.nix)
* Imports `home/common.nix` and declares Android-specific package manifests (e.g., `htop`, `jq`, `fd`, `ripgrep`, `eza`).
* Establishes the target Android username (`nix-on-droid`) and dynamic home directory pathing (`/data/data/com.tuxera.nixondroid/files/home`).

#### [NEW] [configuration.nix](file:///home/nondeus/.nix-config/nix-on-droid/configuration.nix)
* Configures system-level settings for the Nix-on-Droid container.
* Sets Fish as the active terminal environment inside the Android app wrapper.

---

### 4. Flake Entrypoint

Integrates both systems into your repository output definition.

#### [MODIFY] [flake.nix](file:///home/nondeus/.nix-config/flake.nix)
* Add `nix-on-droid` to inputs.
* Route `home-manager.users.nondeus` inside the laptop definition to target the new `home/desktop.nix`.
* Add `nixOnDroidConfigurations.default` targeting `aarch64-linux`, importing `./nix-on-droid/configuration.nix`, and mapping user `nix-on-droid` to `./home/droid.nix`.

---

## Verification Plan

### Automated Dry-Run Tests
To verify syntax validity and module compatibility before deploying to the phone:
1. Test desktop compilation status:
   ```bash
   nix build .#nixosConfigurations.nondeus.config.system.build.toplevel --dry-run
   ```
2. Test Android target compilation status (requires setting up a cross-compilation pipeline or verifying standard nix-on-droid evaluation structures):
   ```bash
   nix eval .#nixOnDroidConfigurations.default.activationPackage --dry-run
   ```

### Manual Verification
1. Verify laptop builds and activates with no broken symbolic links or environment paths.
2. Bootstrap Nix-on-Droid on the Samsung Galaxy S26 Ultra.
3. Clone the refactored config folder and execute `nix-on-droid switch --flake .#default --impure`.
4. Validate that Fish prompt, Micro editing rules, and basic Git settings function on the phone exactly as they do on the laptop.

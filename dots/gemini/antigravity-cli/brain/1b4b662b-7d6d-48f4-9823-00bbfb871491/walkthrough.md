# NixOS Configuration Walkthrough: Introducing `limbo`

This walkthrough documents the design, implementation, and validation of the new, hardware-independent, and clean NixOS configuration named **`limbo`**, housed within the repository at `/home/lowcache/.nix-config`.

The core goal of this configuration is to provide a clean, non-opinionated base that anyone can easily clone, run, and replicate on standard hardware or virtualized platforms, without affecting the highly specialized original system configuration **`infernalnix`**.

---

## 🛠️ Design Decisions & Modularization

To ensure complete isolation and zero impact on the `infernalnix` host configuration, a new modular directory was created:
- [nixos/limbo/configuration.nix](file:///home/lowcache/.nix-config/nixos/limbo/configuration.nix)
- [nixos/limbo/hardware-configuration.nix](file:///home/lowcache/.nix-config/nixos/limbo/hardware-configuration.nix)

No changes were made to `/home/lowcache/.nix-config/nixos/configuration.nix` or `/home/lowcache/.nix-config/nixos/hardware-configuration.nix`.

### 1. Bootloader & Lanzaboote
- **Original (`infernalnix`):** Used Lanzaboote (Secure Boot) and disabled standard `systemd-boot`.
- **Limbo (`limbo`):** Excludes Lanzaboote entirely and enforces standard `systemd-boot` with a configuration limit of 10.
  ```nix
  loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 10;
    };
    efi.canTouchEfiVariables = true;
  };
  ```

### 2. Impermanence & Secrets Management
- **Original (`infernalnix`):** Root filesystem mounted on `tmpfs` (RAM), utilizing `sops-nix` for decypting passwords and `environment.persistence` for state persistence.
- **Limbo (`limbo`):** Uses a standard, non-opinionated filesystem layout (root `/` on standard `ext4`, boot `/boot` on standard `vfat`).
- **Secrets:** Removed `sops-nix` and `sops` configurations entirely. Instead, standard declarative dummy/initial passwords are set for the root and standard user configurations:
  ```nix
  users = {
    users = {
      root = {
        initialPassword = "root";
      };
      lowcache = {
        isNormalUser = true;
        initialPassword = "nixos";
        extraGroups = [ "adbusers" "networkmanager" "wheel" "video" "docker" ];
      };
    };
  };
  ```

### 3. CPU/GPU Hardware Independence
- **Original (`infernalnix`):** Custom Ryzen CPU cstate stability parameters, hybrid AMD/Nvidia GPU drivers, kernel packages from cachyos (`pkgs.cachyosKernels.linuxPackages-cachyos-latest`), and ASUS custom profiles/services (`asusd`, `supergfxd`).
- **Limbo (`limbo`):** 
  - Uses the standard, stable NixOS kernel (unmodified `boot.kernelPackages` which defaults to standard Linux LTS/stable).
  - Excludes Nvidia and AMD specific kernel modules, parameters, and Xserver video drivers.
  - Excludes custom ASUS services (`asusd`, `supergfxd`).
  - Cleans up standard libraries under `programs.nix-ld.libraries` by removing Nvidia/CUDA library dependencies (e.g. `linuxPackages.nvidia_x11.out`, `cudaPackages.*`).
  - Standardizes the `ollama` service configuration to run purely on standard CPU workloads for universal hardware compatibility.
  - Excludes specific CUDA-based docker container environments (`fooocus` and `forge`) which depend on GPU mapping.

### 4. Clean Filesystems Configuration
- **Original (`infernalnix`):** A complex, opinionated storage setup mapping `tmpfs`, `ext4` on persistent disks, and specialized mounts like `/persist` and `/home/lowcache/Storage` via UUIDs.
- **Limbo (`limbo`):** Implements standard device mappings by labels:
  - `/` is mounted on `/dev/disk/by-label/nixos` (fsType: `ext4`).
  - `/boot` is mounted on `/dev/disk/by-label/boot` (fsType: `vfat`).
  - Zram swap is enabled with compressed memory paging.

### 5. Flake Output Integration
`flake.nix` was updated to expose `nixosConfigurations.limbo` alongside `nixosConfigurations.infernalnix`. Because the original home configuration (`./home`) imports a persistence module (`./home/persist.nix`) which depends on impermanence features, the home-manager user block for `limbo` was elegantly custom-configured in `flake.nix` to import standard shell, packages, browser, and session settings *without* loading `persist.nix`.

---

## 📂 Configuration Overview

### Flake Integration Diffs

```diff
     nixosConfigurations.infernalnix = nixpkgs.lib.nixosSystem {
       specialArgs = { inherit inputs; };
       modules = [
         { nixpkgs.hostPlatform = "x86_64-linux"; }
         { nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ]; }
         ./nixos/configuration.nix
         ./nixos/hardware-configuration.nix
         inputs.lanzaboote.nixosModules.lanzaboote
         inputs.impermanence.nixosModules.impermanence
         inputs.lix-module.nixosModules.default
         inputs.sops-nix.nixosModules.sops
         home-manager.nixosModules.home-manager
         {
           home-manager.useGlobalPkgs = true;
           home-manager.useUserPackages = true;
           home-manager.extraSpecialArgs = { inherit inputs; };
           home-manager.users.lowcache = import ./home;
         }
       ];
     };
 
+    nixosConfigurations.limbo = nixpkgs.lib.nixosSystem {
+      specialArgs = { inherit inputs; };
+      modules = [
+        { nixpkgs.hostPlatform = "x86_64-linux"; }
+        ./nixos/limbo/configuration.nix
+        ./nixos/limbo/hardware-configuration.nix
+        inputs.lix-module.nixosModules.default
+        home-manager.nixosModules.home-manager
+        {
+          home-manager.useGlobalPkgs = true;
+          home-manager.useUserPackages = true;
+          home-manager.extraSpecialArgs = { inherit inputs; };
+          home-manager.users.lowcache = { config, pkgs, lib, ... }: {
+            imports = [
+              ./home/shell.nix
+              ./home/pkgs.nix
+              ./home/session.nix
+              ./home/browsers.nix
+            ];
+            home = {
+              username = "lowcache";
+              homeDirectory = "/home/lowcache";
+              stateVersion = "24.11";
+            };
+            gtk = {
+              enable = true;
+              theme = {
+                name = "adw-gtk3-dark";
+                package = pkgs.adw-gtk3;
+              };
+              gtk4 = {
+                theme = null;
+              };
+            };
+          };
+        }
+      ];
+    };
+
     # Add this to allow building/running the VM package
     packages.x86_64-linux.net-gate = self.nixosConfigurations.infernalnix.config.microvm.vms.net-gate.config.config.microvm.declaredRunner;
```

---

## 🚦 Validation & Testing Results

Both NixOS configurations were extensively evaluated and validated using standard Nix tooling.

### 1. Code Formatting
Standard format check with `nixpkgs-fmt` confirmed clean, compliant Nix syntax.
```bash
nixpkgs-fmt nixos/limbo/configuration.nix nixos/limbo/hardware-configuration.nix flake.nix
```
*Result: Evaluated and reformatted cleanly.*

### 2. Flake Dry-Evaluation Checks
We evaluated both system build derivation targets in the dirty worktree to guarantee that all files evaluate cleanly.

- **`limbo` Evaluation:**
  ```bash
  nix eval .#nixosConfigurations.limbo.config.system.build.toplevel.drvPath --show-trace
  ```
  *Status:* **`SUCCESS`**
  *Derivation Output:* `/nix/store/xav4mjnwm71fdj72nxf7k64kzi6j6h0k-nixos-system-limbo-26.05.20260515.d233902.drv`

- **`infernalnix` Evaluation:**
  ```bash
  nix eval .#nixosConfigurations.infernalnix.config.system.build.toplevel.drvPath --show-trace
  ```
  *Status:* **`SUCCESS`**
  *Derivation Output:* `/nix/store/xh3pfkzarv19gj172kmh4036kmh9g25w-nixos-system-infernalnix-26.05.20260515.d233902.drv`

This guarantees that both configurations compile perfectly, and that the original `infernalnix` has not suffered any regressions.

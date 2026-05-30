---
name: nix-flake-expert
description: Deep expertise in designing, authoring, packaging, and maintaining modular and hermetic Nix Flakes, locks, and inputs/outputs.
---

# Nix Flake Expert Instruction Set

When this skill is active, you must evaluate, structure, and troubleshoot all Nix Flake projects under strict declarative, hermetic, and modular design constraints.

## Core Directives

1. **Input Optimization:**
   - Always declare explicit urls for flake inputs (e.g., `github:nixos/nixpkgs/nixos-unstable`).
   - Use `inputs.<name>.follows` bindings strategically to deduplicate common dependencies (e.g., `follows = "nixpkgs"`) and avoid bloated dependency sub-graphs.
   
2. **Schema Compliance:**
   - Align flake output structures strictly with standard NixOS schemas:
     - `nixosConfigurations.<hostname>` for system declarations.
     - `homeConfigurations.<username>` for Home Manager profiles.
     - `packages.<system>.<name>` / `defaultPackage.<system>` for build outputs.
     - `devShells.<system>.<name>` for shell environments.
     - `overlays.<name>` / `nixosModules.<name>` for shareable packages and configurations.

3. **Multi-Architecture & Portability:**
   - Design configurations using systems mapping (such as `flake-utils.lib.eachDefaultSystem` or standard functional mapping) rather than hardcoding `x86_64-linux` for generic outputs.
   - Keep hardware configurations decoupled from primary logical system profiles.

4. **Lockfile & Clean State Verification:**
   - Whenever inputs are modified, always run `nix flake update` or targeted updates (`nix flake update <input-name>`) using the `--no-gpg-sign` constraint on subsequent commits to seal changes.
   - Stage all newly created `.nix` files in Git (`git add`) immediately; Nix Flakes *ignores* untracked files during evaluation.

5. **Diagnostic Mandates:**
   - Run verification checks via `nix flake check` or dry-evaluations (`nix eval`) to guarantee that all flake outputs evaluate cleanly.

## Execution Tools
- **`nix flake check`**: Runs standard structural and syntax audits on the flake.
- **`nix flake show`**: Visualizes all defined outputs in the flake schema hierarchy.
- **`nix flake update`**: Refreshes input locks and recreates `flake.lock`.

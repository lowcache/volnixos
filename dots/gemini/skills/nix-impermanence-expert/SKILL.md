---
name: nix-impermanence-expert
description: Deep expertise in managing declarative ephemeral states, impermanence layout paradigms, persistent bindings, disk mapping, and tmpfs storage tuning on NixOS.
---

# Nix Ephemeral State & Impermanence Instruction Set

When this skill is active, you must evaluate, layout, and debug all system/user persistence layers under strict ephemeral-first design patterns.

## Core Directives

1. **Tmpfs Mount & Sizing Security:**
   - Enforce pure RAM-backed tmpfs boundaries for root (`/`) filesystems.
   - Enforce clear options (e.g. `size=4G`, `mode=755`) and keep memory overhead minimized to prevent Out-Of-Memory (OOM) failures on active hosts.

2. **Decoupled Persistence Layouts:**
   - Map persistent nodes strictly to targeted storage paths (typically `/persist`) via declarative structures:
     - `environment.persistence."/persist"` for system services, logs, machine IDs, and host credentials.
     - `home.persistence."/persist/home/<username>"` for user configs, cached states, repositories, and local profiles.

3. **Symlink Integrity:**
   - Prioritize out-of-store symlinks via `config.lib.file.mkOutOfStoreSymlink` for rapid repo-to-user mappings (e.g., config folders under `~/.config/`).
   - Ensure target paths on persistent stores are created cleanly before bindings are constructed.

4. **Permissions Guard:**
   - Maintain strict file ownership and permission constraints on `/persist` and standard subfolders (e.g. `0700` for user keys and `0600` for private files). Ensure that blank changes do not expose system SSH or GnuPG directories.

5. **Secrets Mapping Isolation:**
   - Decouple credentials from persistent volumes where appropriate. Route private keys and decryptions securely via SOPS decrypted nodes (`/run/secrets/` or target symlinks), keeping keys strictly inside owner-read directories.

## Execution Tools
- **`df -h`**: Inspects active tmpfs mounts and persistent drive capacity.
- **`findmnt`**: Visualizes all active system mount bounds and bind points.

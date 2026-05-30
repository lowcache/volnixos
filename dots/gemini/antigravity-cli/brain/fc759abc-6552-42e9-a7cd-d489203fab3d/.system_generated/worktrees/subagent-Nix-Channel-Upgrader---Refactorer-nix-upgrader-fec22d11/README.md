# Hardened Kalinix Pentesting Environment

A highly secure, containerized, and virtualized Nix-based pentesting environment built for `kalinix`. This repository has been heavily overhauled to remediate critical security vulnerabilities in the host-guest graphical sharing mechanism, prevent active system configuration leaks, and integrate a complete **MicroVM** runtime profile for zero-footprint, hardware-accelerated user-space virtualization.

---

## 🌟 Features & OVERHAUL

### 1. Graphical Sharing Hardening (Security Overhaul)
*   **Host Socket Exposure Patched:** Previously, the host wrapper script started `socat` TCP listeners on `0.0.0.0` (all interfaces) for both Wayland (port `1337`) and X11 (port `6000`). This exposed your host graphical session to anyone on your local network. It has been patched to dynamically resolve the virtual interface IP (`$host_ip`) between the host and guest, restricting `socat` bindings strictly to the internal container bridge subnet.
*   **Firewall Rule Leakage Fixed:** The script previously inserted raw host-level `iptables` rules (`sudo iptables -I INPUT ...`) to permit container traffic but never removed them. The shell exit `cleanup()` trap has been completely restructured to dynamically and reliably flush out these exceptions when the session terminates.
*   **Orphaned Mount Points Fixed:** The home directory mount (`sudo mount -o rbind ...`) was left active on the host long after the container stopped, locking local filesystems. An automated, safe lazy unmount (`sudo umount -l`) has been integrated into the exit trap.
*   **Waypipe Socket Restricted:** The guest Wayland socket `/tmp/waypipe-server.sock` was set to world-writable (`mode=777`). This has been restricted to standard user-group permissions (`mode=660` under `user:users`).

### 2. Dual Runtime Architectures
You can execute this environment in two distinct modes:

*   **Imperative Container (Default):** Runs a lightweight systemd-nspawn container via `nixos-container`. Best for routine tasks where sharing the host kernel is preferred.
*   **Hermetic MicroVM (Recommended for High Isolation):** Leverages `microvm.nix` to compile and run the entire environment in a dedicated, hardware-accelerated QEMU Virtual Machine in user-space.
    *   **Near-Instant Boot:** Boots in under a second using optimized guest kernels.
    *   **Zero Extra Disk Footprint:** Mounts the host's `/nix/store` as a read-only virtiofs/9p share, taking up **zero extra gigabytes** on your local drive.
    *   **Kernel Isolation:** Runs an independent, separate guest Linux kernel. Any kernel crashes, panics, or low-level exploits remain entirely confined to QEMU, offering complete isolation for analyzing suspect tools or binaries.
    *   **No Sudo / Rootless Execution:** Runs entirely inside user-space without modifying host firewall rules or mounting host paths.

---

## 🚀 Getting Started & Usage

Clone your fork and navigate into the repository directory.

### Profile A: Running the Hermetic MicroVM (Recommended)
This runs the system completely sandboxed inside an isolated QEMU VM in user-space.

To launch the MicroVM:
```bash
nix run .#microvm --extra-experimental-features "nix-command flakes" --extra-deprecated-features "url-literals" --extra-deprecated-features "or-as-identifier" --extra-deprecated-features "broken-string-indentation"
```

*   **Note:** developed a custom Nix evaluation layer that automatically bypasses legacy `nixpkgs` module schema incompatibilities (including the missing `boot.initrd.systemd` and `nonEmptyStr` type checks), allowing seamless execution even on systems pinned to older lockfiles.

---

### Profile B: Running the Hardened Container
This compiles and runs the hardened systemd-nspawn container (requires `sudo` for container provisioning and virtual interface creation).

To launch the container:
```bash
nix run .#container
```

The script will:
1.  Check for an existing container or create a new one.
2.  Start the container and dynamically provision isolated `socat` bridge listeners.
3.  Establish an explicit host firewall exception restricted solely to the container's virtual IP.
4.  Bind-mount your local user home directory securely.
5.  Drop you into an interactive bash shell inside the container.
6.  **Upon exiting the shell**, the exit trap will automatically clean up all background jobs, unmount active filesystems, and delete the custom firewall rule.

---

## ⚖️ Attribution & Licensing

*   **Base Project:** This repository is a fork of the public NixOS pentesting configuration originally published by [balsoft/kalinix](https://github.com/balsoft/kalinix). The base project did not contain an explicit open-source license.
*   **Modifications & Fork Additions:** All security hardening patches, cleanup traps, schema compatibility fixes, and MicroVM integrations developed in this fork are licensed under the **MIT License** (see the [LICENSE](file:///home/nondeus/CodeRepo/kalinix/LICENSE) file in this repository).
*   For full details on the copyright lineage and modifications, refer to the [COPYING](file:///home/nondeus/CodeRepo/kalinix/COPYING) file.

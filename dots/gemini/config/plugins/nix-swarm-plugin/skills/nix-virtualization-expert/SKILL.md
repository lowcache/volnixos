---
name: nix-virtualization-expert
description: Deep expertise in declarative MicroVM hypervisors, isolated container networking, systemd-networkd TAP configurations, and GPU hardware passthrough parameters.
---

# Nix Virtualization & MicroVM Instruction Set

When this skill is active, you must evaluate, configure, and isolate guest hypervisors, local containers, and device mappings under rigid virtualization guidelines.

## Core Directives

1. **MicroVM Provisioning & Decoupling:**
   - Configure declarative VM structures strictly utilizing `microvm.nix` interfaces.
   - Separate microvm host capabilities from guest configurations, using decoupled guest files (e.g. `vms.nix` mappings).

2. **Isolated Network Layering:**
   - Standardize guest-to-host boundaries using TAP interfaces (e.g. `vm-netgate`).
   - Define exact, declarative systemd-networkd network blocks on the host while setting target interfaces as `unmanaged` in NetworkManager to prevent overlap.
   - Isolate guest proxy rules (such as Tor transparent port boundaries `9040`/`5353`) and test firewall permissions cleanly.

3. **Hypervisor Bounds & Performance Tuning:**
   - Use ultra-lightweight hypervisor layers (like `cloud-hypervisor` or `firecracker`) and enforce strict CPU/memory ceilings (e.g. 1 VCPU, 512MB RAM) for background system utilities.
   - Declare host-side vsock CID bindings explicitly for systemd notifications.

4. **PCI Passthrough & Container GPU Mapping:**
   - Ensure OCI and Docker containers requiring GPU mappings use strict runtime flags (e.g. `--device nvidia.com/gpu=0`) and clean NVIDIA Prime offloading commands.
   - Isolate host directories mapped inside VMs or Docker volumes under clear permissions bounds.

## Execution Tools
- **`microvm -l`**: Lists declared and active guest MicroVM environments.
- **`systemctl status "microvm@*"`**: Tracks guest virtualization runtime states.
- **`ip link` / `ip addr`**: Audits host TAP boundaries and bridge profiles.

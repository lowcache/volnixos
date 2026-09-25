# asus-ryzen-nvidia hardware module

Hardware-specific NixOS config for an ASUS laptop with an AMD Ryzen CPU
(integrated Radeon graphics), a discrete NVIDIA GPU (PRIME offload), and an
NVMe SSD. Root is tmpfs (impermanence); swap/filesystems stay in
`nixos/hardware-configuration.nix`, not here.

## Files

- `default.nix` — entry point; imports `gpu.nix`, `kernel.nix` and
  `keyboard-rgb.nix`. Imported from `nixos/hardware-configuration.nix`.
- `gpu.nix` — AMD + NVIDIA graphics stack: `hardware.graphics` (VA-API/VDPAU),
  AMD OpenCL, NVIDIA driver (open kernel module, fine-grained power
  management), PRIME offload bus IDs, container toolkit, X video drivers.
- `kernel.nix` — CachyOS kernel, GPU kernel modules/params, latency and
  stability tuning (sysctl: memory, panic recovery, scheduling, network/BBR),
  `hardware.uinput`.
- `keyboard-rgb.nix` — `hardware.asus.keyboardRgb`: writes the TUF keyboard
  effect to `kbd_rgb_mode` directly, because asusd registers only `Static` for
  this product family and no-ops every other effect. Off by default.

## Forking for different hardware

1. Copy this directory to `nixos/hardware/<your-machine>/`.
2. Point the import in `nixos/hardware-configuration.nix` at it.
3. Different GPU vendor/topology: replace `gpu.nix` wholesale.
4. Different CPU/latency needs: edit or gut `kernel.nix` (the sysctl block is
   tuning, not correctness — safe to drop entirely).
5. Also swap the `nixos-hardware` imports in `hardware-configuration.nix`
   (`common-cpu-amd`, `common-gpu-nvidia`, `common-pc-laptop-ssd`) to match.

## Hardware-specific values you must check

- **PRIME bus IDs** (`gpu.nix`): `amdgpuBusId = "PCI:102:0:0"`,
  `nvidiaBusId = "PCI:1:0:0"`. Get yours from `lspci | grep -E 'VGA|3D'` and
  convert each hex field to decimal (`66:00.0` hex → `PCI:102:0:0`). Wrong
  IDs mean offload silently fails or X refuses to start.
- **`processor.max_cstate=1`** (`kernel.nix` kernelParams): keeps the CPU out
  of deep sleep states for latency/stability at a battery-life cost. Remove
  it for non-latency-sensitive machines.
- **`vm.swappiness = 180`** (`kernel.nix` sysctl): only sensible with
  `zramSwap` enabled (set in `hardware-configuration.nix`). With disk-only
  swap, use a conventional value (≤ 60) or remove it.
- **`kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest`**
  (`kernel.nix`): requires the chaotic/cachyos overlay from the flake.
  Replace with `pkgs.linuxPackages_latest` (or omit for the nixpkgs default)
  on a generic setup.

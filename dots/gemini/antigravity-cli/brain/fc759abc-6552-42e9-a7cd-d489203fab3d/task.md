# Hardening Kalinix Container & MicroVM Integration Tasks

- `[x]` Harden host launcher script `scripts/run-container`
  - `[x]` Restrict `socat` listeners to bind to the virtual bridge interface IP rather than `0.0.0.0`
  - `[x]` Clean up `iptables` rule on trap exit
  - `[x]` Clean up `rbind` mount point via lazy unmount on exit
- `[x]` Harden container configuration in `configuration.nix`
  - `[x]` Restrict waypipe socket permissions
  - `[x]` Make host/gateway IP detection more robust
- `[x]` Integrate `microvm.nix` into `flake.nix`
  - `[x]` Add `microvm` input
  - `[x]` Add `nixosConfigurations.microvm` output profile
  - `[x]` Configure hypervisor, 9p store sharing, and user networking
- `[x]` Perform validation & formatting checks
- `[x]` Generate walkthrough documentation

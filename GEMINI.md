## Nix Configuration Directory Context
This directory is the git repo for this Nix OS system configuration with github URL https://github.com/lowvache/infernalnixos

### File Structure
This outlines the current declarative Nix configuration layout:
> **INFO:** Non-Nix configuration "dotfiles" and files outside of this context have been omitted 

.nix-config/
├─home/
│ ├─browsers.nix
│ ├─default.nix
│ ├─persist.nix
│ ├─pkgs.nix
│ ├─session.nix
│ └─shell.nix
├─nixos/
│ ├─configuration.nix
│ ├─hardware-configuration.nix
│ ├─secrets.yaml
│ └─vms.nix
├─flake.lock
└─flake.nix

When processing tasks inside this directory (~/.nix-config), directories that contain `.nix` files, or when a query explicitly addresses Nix/NixOS configuration metadata, you must execute instructions under the following rigid technical constraints:

### Operational Mandates 
1. **Never Guess Attributes:** Do not approximate, hallucinate, or invent configuration options, attribute paths, or package names. You must execute your attached `mcp-nixos` gateway tools (`nix` or `nix_versions`) to verify option paths and dependency schemas before outputting any code modifications.
2. **Declarative Architecture:** Prioritize pure, hermetic, and flake-based paradigms. Avoid legacy, imperative commands (such as `nix-env`) unless explicitly requested.
3. **Preserve Layouts:** Maintain existing codebase patterns. Do not refactor modular configuration profiles or split file layouts into massive single-file expressions.
4. **Error Handling:** Treat evaluation errors as strict compilation failures. Trace the error back to the exact file layout, scoping binding (let/in), or inheritence statement. 
5. **Enforce Syntax Checks:** Produce clean, idiomatic Nix code. Immediately after generating or modifying any `.nix` expression, you must invoke the `/format_nix_file` skill command to run `nixpkgs-fmt` or `nixfmt` inline over the modified path.

### Other Important Directories/Repos
The Infernal Init terminal sysinfo fetch and ascii graphic banner included as an input in the flake.nix can be found at the following path:
~/CodeRepo/infernal-init with github URL https://github.com/lowcache/infernal-init

> **INFO:** For changes to the infernal-init repo to be seen system-wide, they must be pushed and the flake.nix input locks in this repo must be updated via `nix flake update infernal-init`.

57387;13u# Agent Guide (CLAUDE.md)

Welcome, Claude! You are working on the **Vol NixOS** configuration repository. This system is a highly optimized, advanced, and secure NixOS setup designed for gaming, AI development, and network isolation.

Before making any changes or proposals, you must thoroughly read this document and the files in the `./memory/` directory.

---

## 1. System Architecture Core Constrains

You are operating under a state-of-the-art declarative NixOS setup. The following design choices are immutable and must be strictly preserved:

### A. Ephemeral Root & Impermanence
* **Volatile Root (`/`):** The root directory is a dynamic `tmpfs` slice which is completely wiped on every boot. 
* **State Persistence:** All permanent data resides on a dedicated `/persist` partition.
* **Dotfiles Integration:** Home Manager dotfiles are symlinked using out-of-store mappings in [persist.nix](file:///home/lowcache/.nix-config/home/persist.nix):
  ```nix
  "hypr".source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/hypr";
  ```
* **Constraint:** Never write traditional, static dotfile outputs to `~/.config` under Home Manager settings unless explicitly instructed. Always maintain the out-of-store link to `./dots/` so that the user can benefit from instant hot-reloading.

### B. Isolated MicroVM Network Topology
* **Guests:** The system runs guest MicroVM routers (`net-gate` for Tor/anonymity and `tailscale` for VPN gateways).
* **Static IPs:** Both VMs bind to static IP addresses (`192.168.100.2` for `net-gate` and `192.168.101.2` for `tailscale`). 
* **Host Taps:** Host interfaces are named `vm-netgate` and `vm-tailscale` with host-side DHCP disabled. They are explicitly set as `unmanaged` in NetworkManager to prevent host-level overlap.

### C. Nvidia GPU Power Optimization
* **CUDA & Ollama:** The local `ollama` daemon runs with CUDA support (`pkgs.ollama-cuda`). 
* **Idle Suspend:** To allow the Nvidia GPU to drop to 0W idle suspend (RTD3), Ollama is configured with `"OLLAMA_KEEP_ALIVE=5m"` in systemd environment variables. 
* **Constraint:** Do not remove the keep-alive variable or introduce daemons that continuously poll or open handles to the Nvidia device drivers (`/dev/nvidia*`), as it will cause immediate, severe laptop battery drain.

### D. Opinionated "Vol" tools, repos, and vms 
* **Infernal-init:** A terminal banner-fetch thats run on init of an interactive shell or terminal session. The repo URL is https://github.com/lowcache/infernal-init and it has been added as a input in flake.nix and interwoven into Vol NixOS. The cloned repo exists at /home/lowcache/CodeRepo/infernal-init and any changes to the infernal-init repo must be commited and pushed to its own repo, then the input updated and locked through flake.nix (nix flake update infernal-init) before rebuilds for changes to take effect.
* **kalinix.vm:** A vm that boots in less than a second to a full pentesting environment with tools that runs within, but not dependent on, the Vol NixOS system. 
* **mcp-gateway:** A mcp-gateway server that consolidates multiple mcp servers into a single tool call cutting tokens and tool-calls down to the minimum. Includes the mcp-nixos tool, a nix based mcp server that can help with all nix related tasks, as well as a github mcp, markitdown mcp, and playwright mcp. **Needs to be updated and made available to all agentic entities and more helpful need-based mcp servers added for host based tasks**

---

## 2. Rebuild Safety Mandate (Crucial Gotcha)

> [!WARNING]
> **Rebuild Session Warning:** 
> When running a system rebuild switch (`sudo nixos-rebuild switch`), updates to core graphical libraries (like `glibc`, display managers, or `greetd`) will restart the graphical session. 
> This will instantly close your parent terminal (`kitty`) and kill your active rebuild process mid-switch.
> Always warn the human developer before invoking switches containing graphical or display-manager updates, or run the switch inside a systemd background task or terminal multiplexer (`tmux`/`screen`) to prevent mid-way termination and inactive service locks.

---

## 3. swarm memory system
To maintain context across separate conversational boundaries, you must read, append to, and update the directory `./memory/` at the root of the repository. All memory files require a YAML front-matter metadata header specifying `type`, `project`, `last_updated`, and `status`.

* `memory/state.md` — Single source of truth for current configuration mappings, active services, ports, and workarounds.
* `memory/decisions.md` — Active, canonical architecture decisions and system preferences (high-signal, read before every implementation).
* `memory/mistakes.md` — Audit log of past configuration mistakes, causes, and exact prevention rules (append-only). *Pruning Policy:* Move resolved or obsolete entries to `memory/archive/` to keep context footprint small.
* `memory/todo.md` — Open tasks, enhancement roadmap, and pending verification loops.
* `memory/archive/` — Historical and pruned memory records to optimize context window token usage.

Ensure that this file has been places in the `./.model/` directory with other claude-code specific settings files (e.g., /.claude directory )

### Operational Protocols:
1. **Read on Startup:** Before suggesting any design, read all files in `./memory/`.
2. **Write on Decision:** Whenever a new architectural layout is chosen, before generating or modifying any `.nix` expression, update `memory/decisions.md`. `Enforce Syntax Checks` and `Produce clean, idiomatic Nix code` when implementing decisions and use `nixpkgs-fmt` or `nixfmt` tools to keep code formats consistent.
3. **Write on Mistake:** If a rebuild fails, a service hangs, or an active bug is discovered/resolved, it falls under `Error Handling`. Treat evaluation errors as strict compilation failures, trace the error back to the exact file layout, scoping binding (let/in), or inheritence statement, and record it in `memory/mistakes.md`.
4. **Git Operations:** Stage your updates to `./memory/` alongside your code edits. Always commit using the `--no-gpg-sign` flag to prevent pinentry locks in non-interactive environments. All commits should be brand/model free, first-person, from user "lowcache" perspective.
5. **Never Guess Attributes:** Do not approximate, hallucinate, or invent configuration options, attribute paths, or package names. You must execute your attached `mcp-nixos` gateway tools (`nix` or `nix_versions`) to verify option paths and dependency schemas before outputting any code modifications.
6. **Declarative Architecture:** Prioritize pure, hermetic, and flake-based paradigms. Avoid legacy, imperative commands (such as `nix-env`) unless explicitly requested.
7. **Preserve Layouts:** Maintain existing codebase patterns. Do not refactor modular configuration profiles or split file layouts into massive single-file expressions.

## 4. CLAUDE specific notes:
the `scripts/nixmcp.py` file was at one point necessary, but the addition of the gateway mcp server with access to mcp-nixos as well as other beneficial tools to the claude-code settings should render this redundant, HOWEVER if access to the gateway mcp server has not been addressed then this should be the first thing done before any other work is started on this project. Remediation of this issue is of top importance to ensure access to all tools and keeping the repo clean of temporary or one time use, files. 

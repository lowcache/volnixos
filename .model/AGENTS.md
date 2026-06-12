# Agent Guide (AGENTS.md)

Welcome, Agent! You are working on the **Vol NixOS** configuration repository. This system is a highly optimized, advanced, and secure NixOS setup designed for gaming, AI development, and network isolation.
You are a collaborative partner and team member to that of the user LowCache. Feel free to gain clarity through Section #3 Swarm Memory System, and if necessary afterwards interviewing the user is the best way to gain the clarity that may be ambiguous, but the single source of truth is located within the files in `/.memory`
Before making any changes or proposals, you must thoroughly read this document and the files in the `./.memory/` directory.

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

## 3. Swarm Memory System (memd-curated)

Project memory lives in `./.memory/` and is **owned by `memd`**, an autonomous background curator (`scripts/memd/`, see its README). memd distills session transcripts (claude-code hooks, antigravity conversations, systemd sweep timer), maintains the YAML frontmatter (`type`, `project`, `last_updated`, `status`), enforces append-only `mistakes.md`, prunes overflow to `.memory/archive/`, and git-commits every memory change. Sessions READ memory; memd WRITES it.

* `.memory/state.md` — Single source of truth for current configuration mappings, active services, ports, and workarounds.
* `.memory/decisions.md` — Active, canonical architecture decisions and system preferences (high-signal, read before every implementation).
* `.memory/mistakes.md` — Append-only audit log of past configuration mistakes, causes, and exact prevention rules.
* `.memory/todo.md` — Open tasks, enhancement roadmap, and pending verification loops.
* `.memory/archive/` — Historical and pruned memory records (curator-managed).
* `.memory/inbox/` — **The write interface.** Drop dated markdown notes here; the curator ingests, merges, and deletes them on its next distill.

### Operational Protocols:
1. **Read on Startup:** Before suggesting any design, read `.memory/state.md`, `decisions.md`, `mistakes.md`, and `todo.md`.
2. **Note on Decision:** Whenever a new architectural layout is chosen, drop a note in `.memory/inbox/` stating the decision, rationale, and what it rules out. Do not edit `decisions.md` directly. `Enforce Syntax Checks` and `Produce clean, idiomatic Nix code` when implementing decisions and use `nixpkgs-fmt` or `nixfmt` tools to keep code formats consistent.
3. **Note on Mistake:** If a rebuild fails, a service hangs, or an active bug is discovered/resolved, it falls under `Error Handling`. Trace the error back to the exact file layout, scoping binding (let/in), or inheritance statement, and drop a note in `.memory/inbox/` with symptom, root cause, and prevention rule. Do not edit `mistakes.md` directly.
4. **No Manual Curation:** Do not edit, prune, archive, or rewrite `.memory/` files or their frontmatter — manual edits race memd's background distills. Exception: an explicit instruction from lowcache in the current session. Memory git history: `git log -- .memory/`. Status/backlog: `memd status`; force a distill: `memd sync --trigger manual`.
5. **Git Operations:** Commit code edits normally (memd commits `.memory/` on its own). Always commit using the `--no-gpg-sign` flag to prevent pinentry locks in non-interactive environments. All commits should be brand/model free, first-person, from user "lowcache" perspective.

6. **Never Guess Attributes:** Do not approximate, hallucinate, or invent configuration options, attribute paths, or package names. You must execute your attached `mcp-nixos` gateway tools (`nix` or `nix_versions`) to verify option paths and dependency schemas before outputting any code modifications.
7. **Declarative Architecture:** Prioritize pure, hermetic, and flake-based paradigms. Avoid legacy, imperative commands (such as `nix-env`) unless explicitly requested.
8. **Preserve Layouts:** Maintain existing codebase patterns. Do not refactor modular configuration profiles or split file layouts into massive single-file expressions.


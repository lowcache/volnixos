<div align="center">

<p>
<img alt="title img banner" src="./assets/ms6pkfms6pkfms6p.png">
</p>
<p>
  <img alt="NixOS unstable" src="https://img.shields.io/badge/NixOS-unstable-5277C3?style=flat-square&amp;logo=nixos&amp;logoColor=white">
  <img alt="Hyprland" src="https://img.shields.io/badge/WM-Hyprland-00AAFF?style=flat-square&amp;logo=hyprland&amp;logoColor=white">
  <a href="https://github.com/lowcache/volinit"><img alt="banner: volinit" src="https://img.shields.io/badge/banner-volinit-b00000?style=flat-square"></a>
  <a href="https://github.com/lowcache/volnixos/commits/main"><img alt="Last commit" src="https://img.shields.io/github/last-commit/lowcache/volnixos?style=flat-square&amp;logo=git&amp;logoColor=white&amp;label=last%20commit&amp;color=5277C3"></a>
</p>
</div>

A declarative, highly optimized, and ephemeral NixOS system configuration based on Nix Flakes. This setup integrates advanced system virtualization, low-latency performance kernels, encrypted secret management, secure boot configurations, and a bespoke Qt6/QML window manager desktop shell.

---
<!-- TOC -->

- [System Architecture Overview](#system-architecture-overview)
  - [Declarative Package Engine: Lix](#declarative-package-engine-lix)
  - [Ephemeral Root & Impermanence](#ephemeral-root--impermanence)
  - [CachyOS High-Performance Kernel & Sysctls](#cachyos-high-performance-kernel--sysctls)
  - [Native UEFI Secure Boot & Cryptography](#native-uefi-secure-boot--cryptography)
  - [Tor Anonymity Gateway MicroVM](#tor-anonymity-gateway-microvm)
  - [GPU CUDA-Accelerated Containerization & Services](#gpu-cuda-accelerated-containerization--services)
- [Graphical Rice & User Experience: "illogical-impulse"](#graphical-rice--user-experience-illogical-impulse)
  - [Bespoke Quickshell Panel ii](#bespoke-quickshell-panel-ii)
  - [JSON Theme Colorscheme Engine](#json-theme-colorscheme-engine)
  - [System Welcome Banner: volinit](#system-welcome-banner-volinit)
  - [Advanced Work Safety Daemon](#advanced-work-safety-daemon)
- [Directory and Configuration Layout](#directory-and-configuration-layout)
  - [Nix Flake & Modular Config Files](#nix-flake--modular-config-files)
  - [Complete Nix Config Directory Structure](#complete-nix-config-directory-structure)
- [Key Scripts & Management Commands](#key-scripts--management-commands)
  - [Makefile](#makefile)
  - [Workspace Operations with Fish functionsd](#workspace-operations-with-fish-functionsd)
  - [Fish functions in home/shell.nix](#fish-functions-in-homeshellnix)
  - [Memd, Tether, and Agent-Scaffold](#memd-tether-and-agent-scaffold)
    - [Memd](#memd)
    - [Tether](#tether)
    - [Agent-Scaffold](#agent-scaffold)
- [Limbo: Hardware-Independent & Clean Replicable Config](#limbo-hardware-independent--clean-replicable-config)
  - [Directory Layout](#directory-layout)
  - [Disk Partitioning & Labeling](#disk-partitioning--labeling)
  - [Installation Walkthrough](#installation-walkthrough)
  - [Rebuilding & Managing Limbo](#rebuilding--managing-limbo)

<!-- /TOC -->

---

> **[!WARNING]**
>
> **Hardware Specificity & Replication Warning**
> This configuration is highly tailored and proprietary to a specific hardware environment (Ryzen CPU + AMD/Nvidia Hybrid GPU ASUS Laptop) and local user setups. You can skip these modifications entirely by using the pre-configured **`limbo`** profile, a clean, generic version of this system designed to run on any standard x86_64 hardware. See [Section 5](#5-limbo-hardware-independent--clean-replicable-config) for details.
>

---

## 1. System Architecture Overview

```mermaid
graph TD
    A[Hardware: Ryzen CPU + Nvidia/AMD GPUs] --> B[CachyOS Kernel]
    B --> C[Lanzaboote Secure Boot]
    B --> D[Impermanence: Ephemeral Root /]
    D --> E[Persistent State /persist]
    E --> F[Home Manager & User Space]
    F --> G[Hyprland + UWSM Desktop]
    G --> H[Quickshell: illogical-impulse QML]
    E --> I[net-gate MicroVM Tor Gateway]
    F --> J[Docker: Stable Diffusion CUDA Containerization]
```

### 1.1 Declarative Package Engine: Lix

The standard C++ Nix daemon is replaced with **Lix** (via `lix-module`), a modern, high-performance implementation focused on speed and reliable flake evaluations.

### 1.2 Ephemeral Root & Impermanence

This machine employs the **Impermanence** paradigm (`nix-community/impermanence`).

- The root filesystem (`/`) is wiped or rebuilt on every boot, keeping the OS entirely clean.
- Important files, cache states, configurations, and user directories are mapped selectively onto a persistent partition at `/persist`.
- **Out-of-store Symlinks:** Dotfiles in user space are mapped via `config.lib.file.mkOutOfStoreSymlink` to the git repository under `/persist$HOME/.nix-config/dots/`. This allows modifications in the repository (e.g., config changes) to take effect instantly without needing a full `home-manager switch`.

### 1.3 CachyOS High-Performance Kernel & Sysctls

A custom-configured CachyOS Kernel (`pkgs.cachyosKernels.linuxPackages-cachyos-latest`) is compiled with extreme low-latency performance characteristics:

- Full preemption model (`preempt=full`) and thread IRQs (`threadirqs`) for real-time interactivity under high load.
- Sysctl-level kernel overrides for refined memory and scheduling control:
  - Highly aggressive virtual memory mapping (`vm.max_map_count = 2147483642`) and swappiness (`vm.swappiness = 180`).
  - Scheduling bandwidth slices optimized (`kernel.sched_cfs_bandwidth_slice_us = 3000`).
  - High-throughput network tuning incorporating BBR congestion control (`net.ipv4.tcp_congestion_control = bbr`) and fq queueing disciplines (`net.core.default_qdisc = fq`).
  - Dedicated GPU stability overrides to counter AMD + NVIDIA hybrid GPU and Ryzen C-state conflicts (`processor.max_cstate=1`, `amdgpu.gpu_recovery=1`).

### 1.4 Native UEFI Secure Boot & Cryptography

- **Lanzaboote:** Native integration (`nix-community/lanzaboote`) implements secure boot without disabling hardware locks by generating and registering key bundles under `/etc/secureboot`.
- **SOPS-Nix:** Secret files are encrypted via Mozilla SOPS inside `secrets.yaml` and decrypted locally on boot using host age SSH keys (`/persist/etc/ssh/ssh_host_ed25519_key`) to populate system user and root passwords securely.

### 1.5 Tor Anonymity Gateway (MicroVM)

An isolated background gateway MicroVM named `net-gate` is run declaratively via **microvm.nix**:

- Powered by `cloud-hypervisor` utilizing VSOCK CID bindings and a 1 VCPU / 512MB RAM minimal memory allocation.
- Automatically launches a transparent **Tor proxy** routing DNSPort (`5353`) and TransPort (`9040`) for secure client interactions.
- Placed on a virtual host tap network (`vm-netgate`) with local network boundaries (`192.168.100.1/24`) and explicit host-side systemd-networkd isolation rules. NetworkManager is instructed to treat the tap as unmanaged to prevent overlap.

### 1.6 GPU CUDA-Accelerated Containerization & Services

The system is configured as an AI development workstation:

- **Docker OCI Configurations:** Declarative, non-autostarting stable diffusion services for **Fooocus** and **Forge WebUI** equipped with direct host Nvidia GPU hardware passthrough (`nvidia.com/gpu=0`).
- **Local AI Stack:** An Ollama runner backed by CUDA-compiled dependencies (`pkgs.ollama-cuda`) and Open-WebUI run system-wide, integrated dynamically with ffmpeg binaries.
- **Nix-LD Wrapper:** An exhaustive compilation of standard and graphics-related libraries are configured within `nix-ld` to run unpatched Linux binaries (including CUDA/OpenGL drivers) natively.

---

## 2. Graphical Rice & User Experience: "illogical-impulse"

The desktop setup operates on **Hyprland** launched under the **Universal Wayland Session Manager (UWSM)** to handle systemd-managed environmental boundaries, using **tuigreet** and `greetd` as the primary greeter.

```
~/.nix-config/dots/
├─quickshell/
│ └─ii/                # Bespoke Qt6/QML shell environment
├─illogical-impulse/   # Custom colorschemes and updates config
├─kitty/               # Modus Vivendi / Custom GPU terminal themes
├─starship/            # Custom starship prompt profiles
├─fuzzel/              # Application launcher ini files
├─wlogout/             # Custom Wayland logout layout and stylesheet
└─cava/                # Console audio visualizer configuration
```

### 2.1 Bespoke Quickshell Panel (ii)

The user interface features a deep desktop shell written using **Quickshell** (QML + Qt6).

- Renders system panels, dynamic workspace icons, status trackers, and resource indicators directly onto Wayland.
- System variables dynamically expose custom Qt6 paths and `QML2_IMPORT_PATH` directories to load libraries cleanly from both system profiles and local directories.
- Includes custom utilities like a screenshot tool (utilizing grim, slurp, and swappy) and custom overlays.

### 2.2 JSON Theme Colorscheme Engine

Instead of generic wallpaper generation, this setup relies on a highly sophisticated, custom-built colorscheme compiler engine (`apply_theme.py` / `apply_theme.bin` under `~/.config/illogical-impulse/scripts/`).

- Reads structured JSON theme matrices stored under `~/.nix-config/dots/illogical-impulse/themes/` (such as `petrified_spittoon.json`, `vivendi_tinted.json`, `horizon_neon.json`, and `skumring.json`).
- Parses theme palettes and mapping schemas to dynamically patch color configurations in real time across different components:
  - **`Appearance.qml`**: Recompiles material and semantic roles to dynamically adjust Quickshell styling.
  - **Hyprland Borders**: Injects matching border highlights into `~/.config/hypr/hyprland/colors.conf`.
  - **Kitty Terminal**: Rewrites terminal colors and tab-bar layouts in `~/.config/kitty/current.conf` and `~/.config/kitty/tab_bar.py`.
  - **Starship Prompt**: Synthesizes custom palette hashes directly inside `~/.config/starship.toml`.
- The pipeline integrates with `switchwall.sh` and `applycolor.sh` to programmatically update wallpaper positions on multiple monitors and hot-reload virtual terminal color escape sequences (`/dev/pts/*`) along with Qt/Kvantum assets dynamically.

### 2.3 System Welcome Banner: `volinit`

A custom-developed terminal system information fetch and stylized ASCII art banner application (`volinit`) is packaged natively:

- Pulled declaratively via Nix Flakes input bindings from the upstream repository `lowcache/volinit`.
- Runs instantly on launch to provide an aesthetic, low-overhead system status display.
- Tracked locally under `~/CodeRepo/volinit/` and can be pushed/pulled independently, then updated globally using `nix flake update volinit`.

### 2.4 Advanced Work Safety Daemon

Inside the `illogical-impulse` configurations lies a highly advanced safety filter:

- Continuously scans networks for specific SSID keywords (e.g., "cafe", "public", "school", "guest").
- When a target network is active, the system triggers the `workSafety` policy to automatically filter clipboards and prevent background loads of explicit sites or NSFW wallpapers in public environments.

---

## 3. Directory and Configuration Layout

### 3.1 Nix Flake & Modular Config Files

- **`flake.nix`**: System inputs, CachyOS kernel overlays, lanzarboote/sops imports, `volinit` fetch modules, and system configurations mapping.
- **`nixos/`**:
  - `configuration.nix`: Main hardware definitions, system services, Docker OCI setups, greetd settings, Nix-LD graphics libraries, and kernel parameter flags.
  - `vms.nix`: Declares `net-gate` MicroVM configuration, Tor services, and systemd-networkd TAP rules.
  - `hardware-configuration.nix`: Physical file system mounts and host boot requirements.
  - `secrets.yaml`: SOPS-encrypted passwords and private keys.
- **`home/`**:
  - `default.nix`: Imports desktop GTK, user state values, and modular directories.
  - `pkgs.nix`: Houses explicit developer tools, Qt6 libraries, custom desktop engines, and pre-configured AI MCP servers.
  - `persist.nix`: Impermanence mapping rules specifying directories and out-of-store symlink coordinates.
  - `session.nix`: Strict global path exports, including crucial `QML2_IMPORT_PATH` entries for custom panels.
  - `shell.nix`: Fish configurations, git signatures, terminal profiles, and custom operational scripts.
  - `browsers.nix`: Hardware-accelerated Brave (Chromium) settings alongside secondary Floorp browsers.

### 3.2 Complete Nix Config Directory Structure

```bash
.nix-config/
├── .model
├── .memory
├── assets
│   └── ms6pkfms6pkfms6p.png
├── dots
├── flake.lock
├── flake.nix
├── home
│   ├── browsers.nix
│   ├── default.nix
│   ├── memd.nix
│   ├── persist.nix
│   ├── pkgs.nix
│   ├── session.nix
│   └── shell.nix
├── Makefile
├── nixos
│   ├── configuration.nix
│   ├── hardware-configuration.nix
│   ├── limbo
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   ├── secrets.yaml
│   └── vms.nix
├── README.md
└── scripts
    ├── agent-scaffold
    │   ├── agent-scaffold
    │   └── templates
    │       └── MODEL.md
    ├── memd
    │   ├── memd.py
    │   ├── __pycache__
    │   │   └── memd.cpython-313.pyc
    │   └── README.md
    └── nixmcp.py
```

---

## 4. Key Scripts & Management Commands

### 4.1 Makefile

To facilitate fast operations, a Makefile system has been implemented for most of the necessary operations from within the Nix Config directory.

```bash
Vol NixOS Helper Makefile

System Operations:
  make switch         Rebuild and switch system live (Default HOST: volnix)
  make build          Build system configuration without switching
  make test           Temporarily switch to configuration (no boot entry)
  make dry-activate   See what service transitions will happen
  make boot           stage the rebuild for the next boot

MicroVM Guest Operations:
  make run-netgate    Start the Tor net-gate MicroVM runner
  make run-tailscale  Start the Tailscale-vm MicroVM runner

Flake & Code Maintenance:
  make check          Check flake lock and schema validity
  make fmt            Auto-format all Nix expressions using nixpkgs-fmt
  make update         Update all flake inputs
  make update-nixpkgs Update only the nixpkgs input
  make gc             Garbage collect older Nix store derivations
  make ghc            Adds changes and creates commit with generic description

Dotfiles Subtree (independent history for dots/, single repo):
  make dots-log       Show history scoped to dots/ (read-only, no remote needed)
  make dots-split     (Re)generate the 'dots-history' projection branch of dots/
  make dots-remote URL=<git-url>   Add the standalone 'dotfiles' remote (one-time)
  make dots-push      Publish dots/ history to dotfiles/main
  make dots-pull      Merge changes from dotfiles/main back into dots/

Colorscheme / Themes (in dots/illogical-impulse/themes):
  make theme-list                 List available themes
  make theme-apply THEME=<name>   Apply a theme by name (regenerates + reloads)
  make theme-check THEME=<name>   Validate a theme (hex + dangling refs + completeness)
  make theme-new NAME="My Theme" [COLORS="#a #b ..."] [FROM=<file>] [APPLY=1] [FORCE=1]
                                  Generate a new standards-compliant theme from colors
Help with Makefile commands
  make help          Displays this help menu
```

### 4.2 Workspace Operations with Fish functionsd

- **`priv-sync`**: Safely rsyncs live persistent directories (Documents, Pictures, repos, Gemini configs) from the ephemeral home directory space into the secure backing repository path:

  ```bash
  priv-sync
  ```

- **`setwall`**: Instantly changes wallpapers globally or on a specified monitor, dynamically running theme scripts to update the active Quickshell theme:

  ```bash
  setwall ~/Pictures/my_wallpaper.png DP-1
  ```

### 4.3 Fish functions in `home/shell.nix`

- **`tablet`**: Run a Samsung s26 ultra as a Weyland tablet with spen support over USB (Weyland + adb reverse).
- **`colorhex`**: Displays colorblocks around hex color codes in the terminal (usage colorhex [file] or pipe output: colorhex | cat [file]).
- **`gpgkey`**: Generates high-strength 4096-bit RSA keys using GPG and automatically exports the armored public key to the working directory.
- **`extract`**: Universal archive extraction helper handling complex compressed profiles (.tar.zst, .tar.xz, .zip, etc.).
- **`ai`**: Run specific ai tools on the fly from [llm-agents.nix](https://github.com/numtide/llm-agents.nix).
- **`ai-shell`**: Run an ephemeral shell with one or more tools from [llm-agents.nix](https://github.com/numtide/llm-agents.nix).
- **`stbldiff-on` / `stbldiff-off`**: Starts or stops the containerized Fooocus stable diffusion environment.

### 4.4 Memd, Tether, and Agent-Scaffold

#### Memd

- **`Memd`**: Custom autonomous memory curator for AI agents within working directories. Headless ai model curates the .menmory directory in any given project/repo at specific times using sysemd timers and Session Hooks.

```bash
  .memory/
  ├── archive - pruned entries from all memory files
  │   └── 2026-06.md
  ├── decisions.md - decisions made about the project/repo
  ├── inbox - event staging, ai will add session details to the inbox for the memd agent to curate
  ├── mistakes.md - mistakes, bugs, issues, etc that have required attention
  ├── state.md - global truth and current state of the project/repo 
  └── todo.md - tasks, to-dos, plans, and reminders that have yet to be completed
```

```bash
 usage: memd [-h] {init,sync,sweep,status,install-hooks,brief,hook,exclude} ...

 memd — agent-driven project memory curator.

 positional arguments:
   {init,sync,sweep,status,install-hooks,brief,hook,exclude}
     init                scaffold .memory/ and register a project
     sync                distill new session content into memory
     sweep               timer entry: catch up all projects, prune, detect
     status              show registry, backlog, last distills
     install-hooks       wire memd into ~/.claude/settings.json
     brief               print session-start memory brief
     hook                claude-code hook entry (reads JSON on stdin)
     exclude             never auto-manage a path

 options:
   -h, --help            show this help message and exit
```

#### Tether

- **`Tether`**: Stand-alone cli capable of orchestrating interactions for cross platform/frontier AI Model collaboration with subagent delegation and support. Allow claude to manage and offload tasks, subagent spawning, and delegation to Gemini. Uses files found within the `.nix-config/.models/agent-tether/` directory for protocol and worker replies.

```bash
tether — delegate task briefs from Claude (orchestrator) to Gemini (worker) via agy

USAGE
  tether run  [-m TIER] [-d DIR] [-t TASK] [-y] [--timeout SECS] "BRIEF"
  tether continue TASK [-y] [--timeout SECS] "FOLLOW-UP"
  tether status [TASK]      list delegated task sessions (or one task's metadata)
  tether log [N]            tail last N delegation log lines (default 20)
  tether models             list available worker models

OPTIONS
  -m TIER        pro (default) | pro-low | flash | flash-high | flash-low
  -d DIR         working directory for the worker (default: $PWD; paths under
                 ~/.nix-config map to the non-hidden ~/volnix alias, and any
                 other hidden path falls back to ~/volnix)
  -t TASK        kebab-case task name; enables `tether continue TASK` later
  -y             pass --dangerously-skip-permissions (write-capable tasks; use deliberately)
  --timeout SECS hard wall-clock limit (default 600)

NOTES
  - BRIEF may be '-' to read from stdin.
  - Worker contract: ~/.nix-config/.model/agent-tether/PROTOCOL.md and ~/.gemini/GEMINI.md §XIII.
  - Worker replies in RESULT / EVIDENCE / BLOCKERS format; stdout is the report.00AAFF
```

#### Agent-Scaffold

- **`Agent-Scaffold`**: automatic scaffolding of `.memory/` and `.model/` directories for any project or repo. `.memory/` contains files for the memd automated AI agent memory curator, and `.model/` which contains all AI agent insttructions, configuration files for tether. Agent-scaffold can either be run from command line or is also automatically run by ai-cli as SessionStart hooks for both claude-code and antigravity-cli. Created to cut down on token usage and carpal tunnel when starting a new project. Creates AGENTS.md, CLAUDE.md, and GEMINI.md with template that is model specific.

> See section [Memd](#memd) for `.memory/` directory scaffolded files

```bash
 .model/
 ├── AGENTS.md
 ├── agent-tether
 │   ├── bin
 │   ├── log
 │   ├── PROTOCOL.md
 │   ├── README.md
 │   └── sessions
 ├── CLAUDE.md
 └── GEMINI.md
```

---

## 5. Limbo: Hardware-Independent & Clean Replicable Config

The **`limbo`** configuration profile provides a generic, non-opinionated, hardware-independent version of this NixOS system that is highly portable and runs cleanly out of the box on standard x86_64 systems (including physical machines and virtual machines).

It is completely decoupled from all proprietary features of `volnix`, meaning it excludes:

- Lanzaboote Secure Boot (reverts to standard **`systemd-boot`**)
- Impermanence and root on RAM (uses a standard, reliable persistent filesystem partition scheme)
- SOPS-Nix encrypted secrets (uses declarative initial passwords)
- Hybrid AMD/Nvidia GPU drivers and Ryzen parameters (runs on generic CPU and open display drivers)
- Specialized hardware services like ASUS daemons and cachyos kernel packages

### 5.1 Directory Layout

The Limbo configuration files are completely isolated under the [nixos/limbo](file:///home/lowcache/.nix-config/nixos/limbo) directory:

- **[nixos/limbo/configuration.nix](file:///home/lowcache/.nix-config/nixos/limbo/configuration.nix)**: Stripped-down base services, including desktop environment (Hyprland), clean Nix-LD unpatched libraries, Docker engine, Fish shell, and CPU-only services for Ollama and Open-WebUI.
- **[nixos/limbo/hardware-configuration.nix](file:///home/lowcache/.nix-config/nixos/limbo/hardware-configuration.nix)**: Standard physical disk maps for typical Linux installations.

### 5.2 Disk Partitioning & Labeling

To install and run Limbo successfully, partition your target drive using a standard layout and assign the exact labels listed below (e.g., using `parted` / `gparted` / `fdisk` / `mkfs`):

| Mount Point | File System | Target Partition Label | Description |
| :--- | :--- | :--- | :--- |
| `/boot` | `vfat` (FAT32) | `boot` | EFI System Partition |
| `/` | `ext4` | `nixos` | Root Partition |

### 5.3 Installation Walkthrough

1. **Boot from a NixOS Installer:** Insert a standard minimal or graphical NixOS Live ISO.
2. **Mount partitions:** Label your partitions and mount them onto `/mnt`:

   ```bash
   # Mount root partition
   mount -t ext4 /dev/disk/by-label/nixos /mnt
   
   # Mount boot partition
   mkdir -p /mnt/boot
   mount -t vfat /dev/disk/by-label/boot /mnt/boot
   ```

3. **Clone the Configuration:** Clone this repository directly to the target system:

   ```bash
   git clone https://github.com/lowcache/volnixos.git /mnt/home/inlimbo/.nix-config
   ```

4. **Run Installation:** Install the system specifying the `limbo` profile:

   ```bash
   nixos-install --flake /mnt/home/inlimbo/.nix-config#limbo
   ```

5. **Reboot and Login:**
   - **Root user initial password:** `root`
   - **Standard user (`inlimbo`) initial password:** `nixos`
   - *⚠️ Set custom passwords immediately after logging in using the `passwd` command.*

### 5.4 Rebuilding & Managing Limbo

To build or switch configurations on an active Limbo system, use standard Nix flake rebuild commands:

- **Switch system configuration:**

  ```fish
  sudo nixos-rebuild switch --flake ~/.nix-config#limbo
  ```

- **Dry-build system configuration:**

  ```fish
  nixos-rebuild build --flake ~/.nix-config#limbo
  ```

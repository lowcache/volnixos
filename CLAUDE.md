# Vol NixOS — Agent Guide

Project-scoped instructions for working in this repository.

Read this file and `.memory/{state,decisions,mistakes,todo}.md` before substantive work.

## Repository

Vol NixOS is a flake-based, impermanent NixOS workstation configuration.

* Host: `volnix`
* System: `x86_64-linux`
* Root: ephemeral `tmpfs`
* Persistent state: `/persist`
* Main configuration: `nixos/` Modules: `nixos/modules` Hardware: `nixos/hardware`
* Home Manager: `home/`
* Dotfiles: `dots/`
* Agent/tooling scripts: `scripts/`
* Wikifiles: any changes to the config that would affect the wiki get put into a markdown file in `docs/wikifixins`
* Documentation: All documentation has been moved to the wiki repo. See Wikifiles for future docs. 
* Operations interface: root `Makefile`
* Templates: `templates/` 
Wiki: `https://wiki.infernalcode.com`

## Nix

Never invent Nix options, attributes, packages, or dependency schemas. Verify them with the available `mcp-nixos` tools before modifying configuration.

All Nix work goes through the `nixtastic` skill (`/nixtastic`; installed at `~/.claude/skills/nixtastic` and `~/.gemini/skills/nixtastic` from the source repo `~/CodeRepo/allnix-skills` via `nix run .#install`; edit the repo, never the installed copies). It routes by task to domain references, carries the volnixos profile (`references/volnixos.md`), and ships the `scripts/nixops.py` helper (`gate`, `build`, `drv`, `recall`, …). `/nixtastic review [path]` runs a maintainability review. It is the only Nix skill; option/package lookups go through the gateway's mcp-nixos backend, and Nix LSP diagnostics come from the `nix-lsp` plugin (nixd).

Preserve the existing modular architecture. Keep changes declarative, hermetic, and flake-based. Avoid `nix-env` unless explicitly required.

After Nix changes, run appropriate checks and format with `nix fmt`.

Canonical repository checks:

* `make check` — flake, formatting, deadnix, statix, plus `checks.fish-syntax` (every HM-generated fish file) and `checks.anon-jail` (NixOS VM test of the anon-mode jail; needs KVM, so CI builds only the first three)
* `make fmt` — formatting/statix fixes
* `make build` — build without switching
* `make dry-activate` — inspect activation changes
* `make test` — temporary activation
* `make boot` — stage next-boot configuration

## Home Manager / Impermanence

`/` is volatile and wiped on reboot. Durable state belongs under `/persist`.

Home Manager dotfiles use out-of-store symlinks into the repository's `dots/` tree. Do not replace these with traditional generated files under `~/.config` unless explicitly required.

Preserve the existing persistence layout and its separation between `/persist` and `~/Storage`.

## MicroVMs

cloud-hypervisor guests via microvm.nix. The flake exposes runners for `net-gate` and `tailscale-vm`.

* `nixos/vms.nix` — MicroVM host, shared stop-timeout tuning, and the `tailscale` guest. Its addressing is `vol.tailscale-vm.*` (tap, subnet, host/guest address); `phone-agent` and `ai-stack` read it rather than repeating literals.
* `nixos/vm-guest-base.nix` — base module every guest imports.
* `nixos/modules/anonymous-mode/guests.nix` — `net-gate` and `anon-box` plus their host plumbing (`br-anon`, net-gate tap, scoped NAT, key minting). Gated by `vol.anon-mode.enable`; addressing comes from `vol.anon-mode.*`.

`microvm@net-gate` has `X-RestartIfChanged=false`: after changing its config run `make gate-restart`, or the old guest keeps running. Use the existing Makefile targets rather than introducing parallel runner mechanisms.

### Anonymity workstation (`vol.anon-mode`)

Invariant: an anonymous workload either traverses net-gate in a verified-ready state or has no network at all.

* Host side (`anonymous-mode/default.nix`): `anon-jail` gives the anon uid a per-uid routing table with a blackhole default (armed at boot, never auto-released); `anon-routing` points it at net-gate; `anon-check` runs the L0–L4 readiness ladder and only L4 writes the stamp that releases workloads; `anon-watch` (timer) re-verifies and seals on loss. `anonymous.target` is the arm/disarm handle.
* net-gate terminates Tor: nftables (`table ip anon-gateway`) redirects into TransPort/DNSPort per client source, forward policy drop, no forwarding. Two legs: host tap and `br-anon`.
* anon-box: workstation guest on `br-anon` only. The host holds no address on that bridge; entry is over vsock (`anon-shell`). Started by `anonymous.target` after the ladder passes. `/in` is a host-side read-only bind, `/out` is `~/Storage/anon/out` (unencrypted volume).
* Operate with `make anon-status | anon-arm | anon-selftest | anon-logs | anon-guest-logs | anon-box-rebuild`. User entry points: `anon-run`, `anon-shell`, `tor-curl`, `tor-brave`.

## NVIDIA / Ollama

Ollama uses `pkgs.ollama-cuda`.

Preserve:

`OLLAMA_KEEP_ALIVE=5m`

Do not introduce persistent processes that continuously poll or hold `/dev/nvidia*`; GPU idle power behavior and battery consumption depend on this architecture.

## Rebuild Safety

Do not casually switch the live system from an interactive graphical session.

Graphical/display-manager updates can terminate the session running the rebuild. Prefer:

`make switch-detached`

when a switch may disrupt the current session.

The repository's Makefile sets the rebuild `TMPDIR` to `~/Storage/tmp`; preserve that behavior for rebuilds that use the Makefile.

## volinit

Terminal banner, tracked from the `rewrite/go-cockpit` branch while it is overhauled into a cockpit-style TUI (local checkout: `/home/lowcache/CodeRepo/volinit`). Wired as the `volinit` flake input and `inputs.volinit.packages.${pkgs.stdenv.hostPlatform.system}.default` in `home/shell.nix`; the fish greeting guards on `command -v volinit`. If a WIP push breaks evaluation, drop both lines rather than pinning around it.

## Claude Code + tweakcc

`claude` is `claude-code-tweaked` (`pkgs/claude-code-tweaked/`): nixpkgs `claude-code` with tweakcc (`pkgs/tweakcc/`, pnpm build) applied in `postInstall`. tweakcc's LIEF parser segfaults on autoPatchelf'd ELFs, so the patch must stay before fixup. Both are added by the local overlay `pkgs/default.nix` (new names, nothing overridden) and exposed as `packages.x86_64-linux.{tweakcc,claude-code-tweaked}`.

* Config: `pkgs/claude-code-tweaked/tweakcc/` (`config.json` + only the `system-prompts/*.md` you edited, force-added; the rest are ignored and regenerated). Edit with `make tweakcc`, which runs the UI against a scratch unpatched binary, then rebuild.
* Prompt data comes from tweakcc's own source (`data/prompts/prompts-<cc version>.json`), so a `claude-code` bump that tweakcc doesn't cover yet fails the build: bump `pkgs/tweakcc` (`src` + `pnpmDeps` hashes) alongside it.
* `droid/` still uses plain `claude-code`.

## Phone agent

Host side of the Galaxy S26 Ultra MCP integration, `nixos/phone-agent/` (`phone-agent.*` options, set in `nixos/hosts/volnix.nix`). The MCP server itself runs in Termux on the phone and is reached over the tailnet through the `tailscale` guest (the host is not a tailnet node). Auth is the sops `phone_agent_token`.

* `phone-agent` CLI (system package) calls phone tools; Claude Code reaches the server via `.claude/.mcp.json` (`${PHONE_AGENT_TOKEN}`).
* User units, gated on `phone-agent.user`: ingest sync (timer) + watcher into `~/ingest`, proximity lock (lock only, no unlock), network-routing profile from modem state.
* Push server (`enablePush`): read-only, token-gated, bound to the tailscale tap; the guest forwards tailnet `:pushPort` to it, so laptop→phone transfer stays phone-initiated.
* adb TCP 5555 on the phone stays open deliberately (phone-agent + Automate/Shizuku); do not "clean it up".

## Google Drive (`gd`)

`gd` (`pkgs/gd/`, overlay name `gd`, in `termUi` in `home/pkgs.nix`) is a bash verb layer over rclone for Drive in the terminal: push/pull/pick/find/cat/put/mv/rm/link, guarded one-way `sync up|down`, `bisync`, FUSE `mount`. `gd help` lists it; `checks.gd` runs every verb but mount/setup against a local alias remote.

* `gd setup` creates the rclone remote `gdrive` (OAuth). `~/.config/rclone` (refresh token) and `~/.config/gd` are persisted to `/persist`; rclone's cache (bisync listings, VFS cache) follows `XDG_CACHE_HOME` into Storage.
* `GD_SYNC_LOCAL` (`~/Storage/Drive`) and `GD_BACKUP_DIR` (`~/Storage/gd-backup`) are session variables in `home/default.nix`.
* fuse is not bundled: `gd mount` relies on NixOS's setuid `fusermount3` wrapper.

## Memory — memd

`.memory/` is curated by `memd`.

Read:

* `.memory/state.md`
* `.memory/decisions.md`
* `.memory/mistakes.md`
* `.memory/todo.md`

Treat `.memory/archive/` as historical reference.

Write new memory only through `.memory/inbox/` using dated notes. Do not manually rewrite curated memory or frontmatter unless explicitly instructed.

`memd` owns memory commits.

## MCP Gateway

`mcp-gateway` is the project's primary MCP aggregation layer.

Prefer extending the gateway over creating standalone MCP servers when functionality belongs in the shared tool layer.

Current gateway integrations include NixOS, GitHub, MarkItDown, Playwright, context7, web search/fetch, and sequential thinking.

The Noctalia Claude MCP configuration is an explicit exception.

## Secrets

SOPS secrets are split by trust boundary:

* `nixos/host-secrets.yaml`
* `nixos/vm-secrets.yaml`

Do not create alternate secret files or casually move secrets between these files.

Secrets reach tools as files under `/run/secrets` (sops-nix). Environment exposure is declared once, in `envSecrets` in `nixos/modules/secrets.nix`: an entry without `wrap` is exported in every fish shell (keys several agent tools read: `GEMINI_API_KEY`, `OPENROUTER_API_KEY`, `PHONE_AGENT_TOKEN`); an entry with `wrap = pkgs.<tool>` is exported only into that tool by a same-named wrapper (`GH_TOKEN` → `gh`). Everything else is read from its file (`*_FILE` patterns, e.g. buttondown, twine). Add a key there, never as a hand-written `set -gx`. `mcp-gateway` is a declared user service (`home/mcp-gateway.nix`) that reads `gh_token` at start.

Use the Makefile's SOPS targets where applicable:

* `make sops-edit`
* `make sops-edit-vm`
* `make sops-rekey`
* `make sops-view`
* `make sops-view-vm`

## Nix-on-Droid

The repository contains a separate `aarch64-linux` Nix-on-Droid configuration.

The laptop can evaluate its configuration but does not emulate/build the phone target. Use:

* `make droid-check`
* `make droid-plan`

on the workstation, and `make droid-switch` on the device.

Do not substitute the workstation's `nixpkgs` for the dedicated Droid package inputs.

## Git

Do not create model/agent-branded commits.

Commit messages should be first-person and represent the user's changes.

`memd` owns memory commits.

For repository synchronization, use the project's Makefile Git workflow rather than inventing another SSH-agent procedure. Do not initiate a remote push unless the operation is explicitly authorized.

Relevant targets:

* `make comm`
* `make push`
* `make git`

## Dotfiles

`dots/` is a subtree-managed component.

Use the existing Makefile targets for subtree operations:

* `make dots-log`
* `make dots-split`
* `make dots-remote URL=...`
* `make dots-push`
* `make dots-pull`

Preserve the subtree structure rather than copying its contents into unrelated configuration modules.

## Claude Integration

Agent guides live at the repo root (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`). Claude Code configuration lives under `.claude/`: `.claude/.mcp.json` (Noctalia + phone-agent MCP, tracked) and `.claude/settings.local.json` (per-machine permissions, gitignored).

This project may participate in the Claude↔Gemini tether. When a `[TETHER]` delegation is active, follow the tether protocol and worker-mode requirements while retaining all project constraints above.

Whenever a major addition, subtraction, or modification is made to the VolnixOS repo/config make sure that those changes, and any necessary considerations, are reflected here to ensure that this document never becomes stale or drifts into a state of hindrance to future work. This document should always reflect the most current state of the configuration, the wiki, and any other subsystems. 


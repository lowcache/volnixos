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
* Wikifiles: any changes to the config that would affect the wiki get put into a markdown file in `docs/wikifixins`; `wiki-sync` applies and deploys them automatically (see below)
* Documentation: All documentation has been moved to the wiki repo. See Wikifiles for future docs. 
* Operations interface: root `Makefile`
* Templates: `templates/` 
Wiki: `https://wiki.infernalcode.com`

## Nix

Never invent Nix options, attributes, packages, or dependency schemas. Verify them with the available `mcp-nixos` tools before modifying configuration.

All Nix work goes through the `nixtastic` skill (`/nixtastic`; installed at `~/.claude/skills/nixtastic` and `~/.gemini/skills/nixtastic` from the source repo `~/Code/ORGs/cacheflow/lowcache/allnix-skills` via `nix run .#install`; edit the repo, never the installed copies). It routes by task to domain references, carries the volnixos profile (`references/volnixos.md`), and ships the `scripts/nixops.py` helper (`gate`, `build`, `drv`, `recall`, …). `/nixtastic review [path]` runs a maintainability review. It is the only Nix skill; option/package lookups go through the gateway's mcp-nixos backend, and Nix LSP diagnostics come from the `nix-lsp` plugin (nixd).

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

`~/Code` is the only persisted development tree: `lowcache/` (own repos and workspaces, e.g. `memd`, `tether`, `allnix-skills`, `noctalia-plugs`, `sites`), `infernalbits/` (org repos), `ORGs/` (other orgs), `stash/` (retired projects). pnpm's store sits at `~/Code/.pnpm-store` (mount root).

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
* anon-box: workstation guest on `br-anon` only. The host holds no address on that bridge; entry is over vsock (`anon-shell`). Started by `anonymous.target` after the ladder passes. `/in` is a host-side read-only bind, `/out` is `~/Storage/anon/out` (on the LUKS `/persist` pool since the 2026-10-31 merge).
* Operate with `make anon-status | anon-arm | anon-selftest | anon-logs | anon-guest-logs | anon-box-rebuild`. User entry points: `anon-run`, `anon-shell`, `tor-curl`, `tor-brave`.

## NVIDIA / Ollama

Ollama uses `pkgs.ollama-cuda`.

Preserve:

`OLLAMA_KEEP_ALIVE=5m`

Do not introduce persistent processes that continuously poll or hold `/dev/nvidia*`; GPU idle power behavior and battery consumption depend on this architecture.

`HDMI-A-1` is wired to the dGPU (`card1`). `cardwired` blocks that card on battery, and niri only discovers cards at startup or on udev `add`, so `cardwire-drm-replay` (`nixos/modules/services.nix`) replays `add` whenever cardwired unblocks a GPU.

## Rebuild Safety

Do not casually switch the live system from an interactive graphical session.

Graphical/display-manager updates can terminate the session running the rebuild. Prefer:

`make switch-detached`

when a switch may disrupt the current session.

The repository's Makefile sets the rebuild `TMPDIR` to `~/Storage/tmp`; preserve that behavior for rebuilds that use the Makefile.

`switch`/`build`/`test`/`boot` and `trash` run through `nh` (`nh os <verb> . -H $(HOST)`, `nh clean all`); `switch-detached` and `dry-activate` stay on `nixos-rebuild` (root unit; nh has no dry-activate).

## volinit

Terminal banner, tracked from the `rewrite/go-cockpit` branch while it is overhauled into a cockpit-style TUI (local checkout: `/home/lowcache/Code/ORGs/cacheflow/lowcache/volinit`). Wired as the `volinit` flake input and `inputs.volinit.packages.${pkgs.stdenv.hostPlatform.system}.default` in `home/shell.nix`; the fish greeting guards on `command -v volinit`. If a WIP push breaks evaluation, drop both lines rather than pinning around it.

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
* Phone display (`enableDisplay`, `display.nix`): user unit `phone-display` runs `scrcpy --new-display` (DeX on One UI 8+) while the phone is on USB and `HDMI-A-1` is connected; the niri window rule (title `phone-display`) in `dots/niri/config.kdl` puts it fullscreen there. Unplug ends it. `displayArgs` swaps the window manager (`--no-vd-system-decorations --start-app=<pkg>`).
* adb TCP 5555 on the phone stays open deliberately (phone-agent; Shizuku is the self-reinitialising Shevery fork, the Automate persistence script is retired); do not "clean it up".

## Google Drive (`gd`)

`gd` (`pkgs/gd/`, overlay name `gd-drive` because `gd` is libgd in nixpkgs, in `termUi` in `home/pkgs.nix`) is a bash verb layer over rclone for Drive in the terminal: push/pull/pick/find/cat/put/mv/rm/link, guarded one-way `sync up|down`, `bisync`, FUSE `mount`. `gd help` lists it; `checks.gd` runs every verb but mount/setup against a local alias remote.

* `gd setup` creates the rclone remote `gdrive` (OAuth). `~/.config/rclone` (refresh token) and `~/.config/gd` are persisted to `/persist`; rclone's cache (bisync listings, VFS cache) follows `XDG_CACHE_HOME` into Storage.
* `GD_SYNC_LOCAL` (`~/Storage/Drive`) and `GD_BACKUP_DIR` (`~/Storage/gd-backup`) are session variables in `home/default.nix`.
* fuse is not bundled: `gd mount` relies on NixOS's setuid `fusermount3` wrapper.

## Thunderbird (`tb`, `tb-bridge`, `tb-mcp`)

Agent access to Thunderbird mail through nixpkgs `thunderbird-cli` 1.1.0. The chain is `tb`/`tb-mcp` → `tb-bridge` (HTTP `127.0.0.1:7700`) → "Thunderbird AI Bridge" add-on (WebSocket `:7701`, installed from file, not ATN).

* `home/pkgs.nix` `thunderbird-cli-tools`: links only `bin/` of the three packages, whose `lib/node_modules/thunderbird-cli` trees conflict.
* `home/thunderbird-bridge.nix`: `tb-bridge.service`, bound to `graphical-session.target`.
* Auth is required: the sops `tb_auth_token` is read by the bridge, by `mcp-gateway-start`, and by the `tb` wrapper (`envSecrets`). Never run the bridge without it; the anon uid can reach loopback.
* MCP: `thunderbird` backend in `gateway.yaml`. The `thunderbird-cli` skill drives its `email_*` tools.

## Monitoring (Netdata)

`nixos/modules/monitoring.nix` runs Netdata as a real-time dashboard, reached from a travel-bubble client at `http://<bubble-ap-addr>:19999` or over `adb reverse tcp:19999` on the USB cable.

* The dashboard needs `package = pkgs.netdata.override { withCloudUi = true; }`: nixpkgs builds without it by default (unfree NCUL1), and then `:19999` serves only the API (every page 404s). Being unfree, it is built locally, not substituted.
* The same port serves Netdata's MCP at `/mcp`, used by the gateway's `netdata` backend. Sensitive functions (`systemd-journal`, `processes`, …) refuse without Netdata's MCP API key, so bubble clients get metrics and alerts but not the journal.

* Firewall opens `:19999` only from the bubble subnet (derived from `vol.travel-bubble.address`), not the `wlp4s0` interface — so it stays closed when the radio is a Wi-Fi client on an untrusted network. Loopback stays open for the cable path.
* The NVIDIA `go.d` collector is disabled via `configDir."go.d.conf"`: it polls `nvidia-smi` and would defeat RTD3 dGPU power-off. Everything else auto-detects.
* `/var/lib/netdata` and `/var/cache/netdata` are persisted to `/persist` (dbengine off the tmpfs root; history survives reboots).

## Wiki sync (`wiki-sync`)

`home/wiki-sync.nix` + `home/wiki-sync.sh`. A user path unit watches `docs/wikifixins`; on change, `wiki-sync.service` waits for 90 s of quiet, then for each pending fixin: snapshots it, runs `claude -p --model sonnet` in a fresh worktree of the wiki (`~/Code/ORGs/cacheflow/lowcache/hugo.web/wiki.infernalcode`, branch `wiki-sync/<ts>` under `~/Storage/tmp/wiki-sync`), gates on the wiki's `make build`, commits, `make deploy` (wrangler + sops `cloudflare_api_token` + verify), then fast-forwards the wiki's `main`. It never pushes; push the wiki yourself.

* Pending = `"<sha256>  <name>"` not in the wiki's committed `.wikifixins-applied` ledger, so editing an applied fixin re-queues it. The folder's `CLAUDE.md` is skipped.
* The agent may edit only `content/` (permission rules + a post-check) and reports `FIXIN <name> applied|already|deferred`; deferred notes (config not there yet) stay pending.
* On failure the worktree and branch are kept, a desktop notification names them, and the wiki's `main` is not advanced (a failed build never deploys).
* Manual: `wiki-sync status`, `wiki-sync --dry-run` (agent + build, no commit/deploy, keeps the worktree), `wiki-sync seed [fixin.md…]` (mark applied without running). Logs: `journalctl --user -u wiki-sync`.

## 2nd Brain (`brain`)

`home/2nd-brain.nix` + `home/2nd-brain.sh`. The Obsidian plugin is the `brain` flake input (`github:lowcache/2nd-brain`); its `main.js`, `manifest.json` and `styles.css` are linked one by one into the `programs.obsidian` vault's `.obsidian/plugins/2nd-brain/`, so `data.json` stays writable. Plugin changes ship as push → `nix flake update brain` → switch.

* `brain capture` (niri `Mod+B`) focuses Obsidian and opens the capture box, passing a copied link only if it is a single http(s) URL. `brain open` reveals the home view.
* `brain-check.timer` runs `brain check` every 5 min of uptime: a wall-clock gap over 30 min (login, resume) or 8 h since the last sign-off marks a sign-off due; while due and unsigned it nags every 20 min (detached `notify-send` with an Open action). Returning after 90 min idle runs `brain check idle` from `dots/noctalia/2nd-brain.toml`. State: `~/.local/state/2nd-brain` (deliberately not persisted; a reboot counts as login). Sign-off state comes from the vault's `.brain/gate.json`.
* This repo is public: personal collector settings live only in the vault's plugin `data.json`, never here.

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

Current gateway integrations include NixOS, GitHub, MarkItDown, Playwright, context7, web search/fetch, filesystem, ripwire (code navigation for non-Nix repos; must run as `ripwire --mcp`), netdata (the agent's own `/mcp` on `:19999`), and chrome-devtools (`chrome-devtools-mcp-nix` in `home/scripts.nix`: pinned npx + the nix chromium playwright-mcp-nix uses, Google usage stats and CrUX off). context-mode and codebase-memory-mcp were tried and dropped (2026-11-03): context-mode needs Claude Code hooks to be useful and its `ctx_execute` bypasses Bash permissions; codebase-memory duplicates ripwire, writes its index to tmpfs `~/.cache`, and serves a loopback UI.

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


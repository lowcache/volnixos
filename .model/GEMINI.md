# Vol NixOS — Agent Guide

Project-scoped instructions for working in this repository.

Read this file and `.memory/{state,decisions,mistakes,todo}.md` before substantive work.

## Repository

Vol NixOS is a flake-based, impermanent NixOS workstation configuration.

* Host: `volnix`
* System: `x86_64-linux`
* Root: ephemeral `tmpfs`
* Persistent state: `/persist`
* Main configuration: `nixos/`
* Home Manager: `home/`
* Dotfiles: `dots/`
* Agent/tooling scripts: `scripts/`
* Documentation: `docs/`
* Operations interface: root `Makefile`

Documentation: `https://volnixos-wiki.pgs.sh`

## Nix

Never invent Nix options, attributes, packages, or dependency schemas. Verify them with the available `mcp-nixos` tools before modifying configuration.

For large additions/removals, use the `nix-expert` swarm:

* `nix-expert` — orchestrator
* `nix-flake-expert`
* `nix-home-manager-expert`
* `nix-impermanence-expert`
* `nix-options-expert`
* `nix-virtualization-expert`

Preserve the existing modular architecture. Keep changes declarative, hermetic, and flake-based. Avoid `nix-env` unless explicitly required.

After Nix changes, run appropriate checks and format with `nix fmt`.

Canonical repository checks:

* `make check` — flake, formatting, deadnix, statix
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

The flake exposes MicroVM runners for:

* `net-gate` — Tor gateway
* `tailscale-vm` — Tailscale gateway

Use the existing MicroVM configuration and Makefile targets rather than introducing parallel runner mechanisms.

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

`volinit` is a flake input and provides the terminal initialization/banner application.

Local checkout:

`/home/lowcache/CodeRepo/volinit`

When modifying `volinit`:

1. commit the upstream `volinit` change;
2. update the input with `nix flake update volinit`;
3. rebuild/test Vol NixOS.

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

The Noctalia MCP configuration is an explicit exception.

## Secrets

SOPS secrets are split by trust boundary:

* `nixos/host-secrets.yaml`
* `nixos/vm-secrets.yaml`

Do not create alternate secret files or casually move secrets between these files.

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

## Gemini Integration

This project may participate in the Claude↔Gemini tether. When a `[TETHER]` delegation is active, follow `~/CodeRepo/tether/PROTOCOL.md` and the applicable Gemini worker-mode/reporting requirements while retaining all project constraints above.

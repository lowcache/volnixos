{ pkgs, ... }:
{
  # Agent / MCP tooling on the phone. Every entry here is fetched from
  # cache.nixos.org rather than compiled on-device, except `claude-code`, which
  # is one npm derivation and cheap. Re-check with `make droid-plan` after any
  # change: anything in the "will be built" list that is not fish-completions or
  # hm_* glue means the phone compiles it.
  #
  # Kept as its own module on purpose. When a nixpkgs bump drops the aarch64
  # build for one of these, the fix is to comment out a line here rather than
  # to untangle it from the shared layer.
  #
  # Deliberately absent:
  #   github-copilot-cli   — no aarch64 build (evaluation error at this rev).
  #   antigravity          — evaluates on aarch64, but it is a desktop Electron
  #                          IDE and Nix-on-Droid has no display server. It
  #                          would add ~3.2 GB of GTK/X11 closure for a binary
  #                          that cannot launch.
  #   memd / tether        — home/scripts.nix links these out of
  #                          /persist, which does not exist on Android. They
  #                          need a phone-local checkout before they can be
  #                          wired up.
  #
  # ── The whole `pkgs.llm-agents.*` set is absent, and this is the pin's cost ──
  #
  # droid/README.md explains why the phone is pinned to nixos-25.11 (glibc 2.42's
  # TCGETS2 isatty() is refused by Android SELinux). numtide publishes aarch64
  # builds of llm-agents to cache.numtide.com, but keyed to *their* nixpkgs. Feed
  # the overlay 25.11 instead and every store path hashes differently, so nothing
  # substitutes. Measured with `make droid-plan`:
  #
  #   nixpkgs agents only            88 derivations,   2 real packages
  #   + pkgs.llm-agents.*           131 derivations,  ~40 real packages
  #
  # Those ~40 are Rust vendor trees (cc-switch-cli, toon), pnpm dependency sets
  # (happy-coder) and prebuilt arm64 tarballs — compiled on a phone, under proot,
  # where `tar` cannot set modes. That is exactly how the first attempt died:
  #
  #   tar: python-bigquery-sqlalchemy-1.16.0/docs/README.rst:
  #        Cannot change mode to rwxr-xr-x: No such file or directory
  #
  # (from parallel-cli -> python3.13-sqlalchemy-bigquery.)
  #
  # So the following are dropped until one of these is true: llm-agents publishes
  # against a release channel, the glibc pin lifts, or the set gets built once on
  # a real aarch64 builder and pushed to a cache we trust:
  #   antigravity-cli, ccstatusline, claude-plugins, opencode, cc-switch-cli,
  #   toon, happy-coder, parallel-cli, zaly
  #
  # Also unstable-only at this lock, same reasoning:
  #   rtk, mcp-gateway, context7-mcp, mcp-server-fetch,
  #   mcp-server-sequential-thinking, llmfit
  #
  # Do NOT reach into `inputs.nixpkgs` for any of them. They would come back
  # linked against glibc 2.42 and land in the promptless/no-tty state the pin
  # exists to avoid.
  home.packages = with pkgs; [
    claude-code
    claude-code-router
    codex

    # Session-death fallback: what lowcache reaches for when a Claude session gets
    # cut off. In nixpkgs proper, so it needs neither llm-agents nor a backport
    # — but 25.11 carries 1.1.14 against unstable's 1.18.4. If that gap starts
    # to bite, it is a backport like rtk/mcp-gateway, not a re-nixification.
    opencode

    # MCP servers. The phone-agent server itself is NOT here — it stays in the
    # Termux app, which is the only package Termux:API will talk to. See
    # droid/README.md.
    mcp-nixos
    github-mcp-server

    # Backported from unstable against the pinned package set — see
    # droid/backports.nix. Both are Rust and BUILD ON-DEVICE (a few minutes
    # each, natively; no binfmt or remote builder needed). Verified 2026-08-03:
    # both link glibc-2.40-224, with no glibc-2.42 in the runtime closure.
    rtk
    mcp-gateway
  ];
}

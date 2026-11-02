# Lua template

Run these **in your project directory** -- this template is a mold you stamp
copies from, never a place to work:

    cd ~/Code/lowcache/my-project
    nix flake init -t ~/.nix-config#lua
    direnv allow

`nix flake init` copies `flake.nix`, `.envrc` and `.gitignore` into the current
directory. To try the template itself, stamp it into a scratch directory --
running `direnv allow` inside `templates/lua/` activates the mold in place
and leaves a `.direnv/` and a `flake.lock` behind in `.nix-config`.

For interpreted Lua plugin work -- noctalia community plugins, neovim plugins.
No `packages` output: the host loads the source, there is nothing to build.

**For `.luau`, this is the wrong template.** Luau is a different language with
a different toolchain (`luau-analyze`, `luau-lsp`); see
`claude-companion/noctalia-claude-plugin/flake.nix`, which already does it.

## Interpreter, measured not guessed

Against the `drive-health` harnesses (`make unit`, 17 invocations):

| interpreter | result |
|---|---|
| `lua5_4` | passes (the default here) |
| `luajit` | passes |
| `lua5_1` | **fails**, rc=1 |

Re-run the suite before changing `luaAttr`.

## Why shellcheck is in here

Plugin Makefiles tend to write the lint gate as
`if command -v shellcheck; then ... fi`. On a host without shellcheck that
step silently passes instead of running. Having it on PATH is what makes the
gate real.

## Gates (`nix flake check`)

`checkCommands` maps a gate name to a command. Each entry becomes its **own**
derivation, so a failure names the gate that broke instead of surfacing as one
opaque script:

    checkCommands = {
        unit = "make unit";
        lint = "luacheck .";
    };

    $ nix flake check
    error: builder for '...check-unit.drv' failed with exit code 2

Empty by default -- a template whose `nix flake check` fails on day one is
worse than no gate at all.

Gates run **hermetically**: no network, and only the toolchain above on PATH.
They also run against a writable copy of the source in `$TMPDIR`, not the
read-only store path, so a suite that writes a temp file works normally.

`make unit` is pure Lua and runs sandboxed -- verified against the
`drive-health` suite. A target needing host systemd or man pages never will.

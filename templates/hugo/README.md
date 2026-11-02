# Hugo site template

Run these **in your project directory** -- this template is a mold you stamp
copies from, never a place to work:

    cd ~/Code/lowcache/my-project
    nix flake init -t ~/.nix-config#hugo
    direnv allow

`nix flake init` copies `flake.nix`, `.envrc` and `.gitignore` into the current
directory. To try the template itself, stamp it into a scratch directory --
running `direnv allow` inside `templates/hugo/` activates the mold in place
and leaves a `.direnv/` and a `flake.lock` behind in `.nix-config`.

Extracted from the four sites already in `~/Code/lowcache/sites`, which had
independently converged on the same shell:

| site | shell |
|---|---|
| hotelevangelism | hugo go wrangler **jq** |
| volnixos-blog | hugo go wrangler **python3** |
| wiki | hugo go wrangler **pagefind** |
| seeksascha | hugo go wrangler |

Core is `hugo + go + wrangler`; the varying tail is the `extraTools` knob.

`go` is core, not an extra: Hugo Modules resolve themes through `go.mod`, so
hugo needs the go toolchain on PATH even when you write no Go.

## Build

`packages.default` runs `hugo --minify` into the store. If the theme is a
Hugo Module fetched at build time, the Nix sandbox will block that network
access -- commit the module cache, or keep using `make build` in the devShell
and treat the package output as CI-only.

## Gates (`nix flake check`)

`checkCommands` maps a gate name to a command. Each entry becomes its **own**
derivation, so a failure names the gate that broke instead of surfacing as one
opaque script:

    checkCommands = {
        build = "hugo --minify --destination $TMPDIR/out";
    };

    $ nix flake check
    error: builder for '...check-build.drv' failed with exit code 2

Empty by default -- a template whose `nix flake check` fails on day one is
worse than no gate at all.

Gates run **hermetically**: no network, and only the toolchain above on PATH.
They also run against a writable copy of the source in `$TMPDIR`, not the
read-only store path, so a suite that writes a temp file works normally.

A theme pulled as a Hugo Module is fetched over the network, which the
sandbox denies. Gate a site like that only once its modules are vendored.

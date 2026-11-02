# Go template

Run these **in your project directory** -- this template is a mold you stamp
copies from, never a place to work:

    cd ~/Code/lowcache/my-project
    nix flake init -t ~/.nix-config#go
    direnv allow

`nix flake init` copies `flake.nix`, `.envrc` and `.gitignore` into the current
directory. To try the template itself, stamp it into a scratch directory --
running `direnv allow` inside `templates/go/` activates the mold in place
and leaves a `.direnv/` and a `flake.lock` behind in `.nix-config`.

For Go programs. **Hugo sites want `#hugo` instead** -- that one carries hugo
and wrangler alongside the same toolchain.

`GOPATH` is redirected to `./.go` so the module cache stays in-tree and
`~/go` never accumulates state from projects you have since deleted.

## Build

`packages.default` activates once a `go.mod` exists -- the same `pathExists`
guard the ruby template uses -- so the devShell is usable from the first
minute of a project that has no module yet.

`vendorHash = null` is correct and complete for a module with no external
dependencies. Once you add deps, set it to `nixpkgs.lib.fakeHash`, run
`nix build .#default`, and paste back the hash the failure reports.

It is deliberately *not* the thing that gates the build: a dependency-free
module legitimately has a null hash, and gating on it would disable the build
for exactly the simplest case.

## Gates (`nix flake check`)

`checkCommands` maps a gate name to a command. Each entry becomes its **own**
derivation, so a failure names the gate that broke instead of surfacing as one
opaque script:

    checkCommands = {
        vet = "go vet ./...";
        test = "go test ./...";
    };

    $ nix flake check
    error: builder for '...check-vet.drv' failed with exit code 2

Empty by default -- a template whose `nix flake check` fails on day one is
worse than no gate at all.

Gates run **hermetically**: no network, and only the toolchain above on PATH.
They also run against a writable copy of the source in `$TMPDIR`, not the
read-only store path, so a suite that writes a temp file works normally.

The sandbox has no network, so gates need vendored deps (`go mod vendor`)
or dependency-free packages. `GOFLAGS=-mod=vendor` is set for you.

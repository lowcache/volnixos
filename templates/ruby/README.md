# Ruby project template

Two layers, one flake.

Run these **in your project directory** -- this template is a mold you stamp
copies from, never a place to work:

    cd ~/Code/ORGs/cacheflow/lowcache/my-project
    nix flake init -t ~/.nix-config#ruby
    direnv allow

`nix flake init` copies `flake.nix`, `.envrc` and `.gitignore` into the current
directory. To try the template itself, stamp it into a scratch directory --
running `direnv allow` inside `templates/ruby/` activates the mold in place
and leaves a `.direnv/` and a `flake.lock` behind in `.nix-config`.

## Layer 1 -- devShell (iteration)

Ruby, `bundix`, `pkg-config` and a C toolchain. Gems stay in-tree under
`vendor/bundle`, so `rm -rf vendor .gem` fully resets the project.

    bundle install
    bundle exec <anything>

Binaries come from `bundle exec` — the shell deliberately does not set `BUNDLE_BIN`,
which would let bundler shadow itself with a `vendor/bin/bundle` binstub.

Set `nativeLibs` in `flake.nix` for gems with C extensions -- e.g.
`[ "imagemagick" ]` for `rmagick`, `[ "postgresql" ]` for `pg`.

## Layer 2 -- bundlerEnv (reproducible)

Inert until a `gemset.nix` exists, because `bundlerEnv` needs that file at
evaluation time:

    bundle lock          # if there is no Gemfile.lock yet
    bundix               # Gemfile.lock -> gemset.nix
    nix build .#default

Re-run `bundix` after any `Gemfile` change, and commit `Gemfile.lock` and
`gemset.nix` together -- they are one unit.

## Knobs

Both live at the top of `flake.nix`:

- `rubyAttr` -- `"ruby"` (nixpkgs default, 3.4.x) or a pin: `"ruby_3_3"`, `"ruby_3_4"`, `"ruby_4_0"`
- `nativeLibs` -- nixpkgs attribute names, as strings

They are strings rather than a `pkgs:` lambda because `.nix-config`'s
`nix flake check` runs `deadnix --fail`, which rejects an unused lambda
argument -- exactly what an empty `nativeLibs = pkgs: [ ];` would be.

## Gates (`nix flake check`)

`checkCommands` maps a gate name to a command. Each entry becomes its **own**
derivation, so a failure names the gate that broke instead of surfacing as one
opaque script:

    checkCommands = {
        spec = "bundle exec rspec";
        lint = "rubocop";
    };

    $ nix flake check
    error: builder for '...check-spec.drv' failed with exit code 2

Empty by default -- a template whose `nix flake check` fails on day one is
worse than no gate at all.

Gates run **hermetically**: no network, and only the toolchain above on PATH.
They also run against a writable copy of the source in `$TMPDIR`, not the
read-only store path, so a suite that writes a temp file works normally.

Gems are not installed inside a gate. Add a `packages.default` build via
`bundix` first, or keep gates to things that need no gems.

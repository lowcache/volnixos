# Python template

Run these **in your project directory** -- this template is a mold you stamp
copies from, never a place to work:

    cd ~/Code/ORGs/cacheflow/lowcache/my-project
    nix flake init -t ~/.nix-config#python
    direnv allow

`nix flake init` copies `flake.nix`, `.envrc` and `.gitignore` into the current
directory. To try the template itself, stamp it into a scratch directory --
running `direnv allow` inside `templates/python/` activates the mold in place
and leaves a `.direnv/` and a `flake.lock` behind in `.nix-config`.

Shaped after `memd`, which uses `python3.withPackages (ps: [ ps.pytest ])`.

## Knobs

- `pythonAttr` -- `"python3"`, or pin: `"python312"`, `"python313"`
- `pythonPkgs` -- nixpkgs `pythonPackages` names; defaults to `pytest`, `ruff`
- `extraTools` -- non-Python tools; defaults to `git`

## Deps nixpkgs does not carry

`withPackages` only reaches packaged deps. For anything else, make a venv on
top of this interpreter -- do not fight nixpkgs for it:

    python -m venv .venv && . .venv/bin/activate && pip install -e .

The shell deliberately does not export `PYTHONPATH`; `withPackages` already
wires the interpreter, and exporting it leaks this environment into any other
Python launched from the shell.

## Gates (`nix flake check`)

`checkCommands` maps a gate name to a command. Each entry becomes its **own**
derivation, so a failure names the gate that broke instead of surfacing as one
opaque script:

    checkCommands = {
        tests = "pytest tests/ -q";
        lint = "ruff check .";
    };

    $ nix flake check
    error: builder for '...check-tests.drv' failed with exit code 2

Empty by default -- a template whose `nix flake check` fails on day one is
worse than no gate at all.

Gates run **hermetically**: no network, and only the toolchain above on PATH.
They also run against a writable copy of the source in `$TMPDIR`, not the
read-only store path, so a suite that writes a temp file works normally.

Only nixpkgs-provided packages are on PATH in a gate. A suite needing a
venv dep cannot run here; keep those out of `checkCommands`.

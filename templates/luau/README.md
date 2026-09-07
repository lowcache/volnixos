# Luau template

Run these **in your project directory** -- this template is a mold you stamp
copies from, never a place to work:

    cd ~/CodeRepo/my-plugin
    nix flake init -t ~/.nix-config#luau
    direnv allow

Generalised from `claude-companion/noctalia-claude-plugin/flake.nix` -- our own
flake, in our own repo, which had already solved this properly. This is
in-house prior art being promoted to a reusable template, not an outside
pattern being imported. Its toolchain, its offline-gate design, and its
reasoning are kept intact.

The one substantive change below (discovered entries) is worth backporting to
that plugin, since the hardcoded list there is still live.

**For `.lua`, use `#lua` instead.** Luau is a different language with a
different analyser; the two templates are not interchangeable.

## What carried over unchanged

- `luau` (the interpreter), `luau-lsp` (the analyser -- `luau-analyze` has no
  `--definitions` flag), `stylua`, `python3` -- the spec suites are Python
- `luau-lsp` in the shell but not in the gates
- one derivation per gate, so a failure names the gate that broke
- `stylua` deliberately **not** a gate: formatting is opt-in

## What changed, and why

**Entries are discovered, not listed.** The source flake carried
`luauFiles = "answer.luau ask.luau ..."` -- nine names in a string. Add a tenth
entry and it is silently never analysed while `nix flake check` stays green.
Here every `*.luau` in the project root is found at evaluation time, minus the
definitions file, which is input to the analyser rather than a target of it.

**Gates run on a writable copy.** The original does `cd ${./.}` and runs
against the read-only store path, which works only because its suites happen
not to write. Anything touching a temp file fails confusingly there.

## The analyser gate

`analyze` is automatic and needs no configuration. It stays inert until both
`noctalia.d.luau` and at least one entry exist, so a freshly stamped project
still evaluates:

    $ nix flake check
    error: builder for '...check-analyze.drv' failed with exit code 1

This is the gate whose absence let a call to a not-yet-declared local ship and
take a widget down on load.

## Everything else

`checkCommands` maps a gate name to a command, each becoming its own
derivation. The source project's other three gates express directly:

    checkCommands = {
      i18n = "python3 scripts/check-i18n.py";
      specs = "for s in tests/*_spec.py; do python3 \"$s\" || exit 1; done";
      widget-specs = "bash scripts/run-widget-specs.sh .";
    };

Gates are hermetic: no network, only the toolchain above on PATH.

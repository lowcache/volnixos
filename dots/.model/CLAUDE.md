# Agent Guide — Dotfiles Scope (`dots/.model/CLAUDE.md`)

This is the **dotfiles-scoped** agent guide. It applies when working anywhere under
`dots/`. It does **not** replace the repository-root guide at
[`../../.model/CLAUDE.md`](file:///home/lowcache/.nix-config/.model/CLAUDE.md) — read that
first for system-wide architecture (impermanence, flake layout, host config), then read
this for dotfile-specific rules. The two layers operate **in concert**: root = whole
system, this = the `dots/` subtree.

Before changing anything under `dots/`, read this file and the scoped memory in
[`../.memory/`](file:///home/lowcache/.nix-config/dots/.memory/).

---

## 1. The Symlink Leak Constraint (most important)

Every app directory under `dots/` is symlinked **as a whole directory** into `~/.config`
via `mkOutOfStoreSymlink` in
[`home/persist.nix`](file:///home/lowcache/.nix-config/home/persist.nix):

```nix
"illogical-impulse".source = mkOutOfStoreSymlink ".../dots/illogical-impulse";
"quickshell".source        = mkOutOfStoreSymlink ".../dots/quickshell/";
```

Consequence: **anything placed inside `dots/<app>/` appears live inside `~/.config/<app>/`.**
For quickshell that directory is scanned by the QML loader. Therefore:

* **Never** put `.memory/`, `.model/`, scratch files, or notes *inside* an individual app
  dir (`dots/quickshell/`, `dots/illogical-impulse/`, etc.).
* The scoped memory lives at `dots/.memory/` and `dots/.model/` — `dots/` itself is **not**
  a symlink target, so nothing leaks. Keep it that way.
* Per-app notes go in subdirs **under** `dots/.memory/` (e.g.
  `dots/.memory/illogical-impulse/`), never under the symlinked app dir.

## 2. Theming Pipeline

The source of truth for the colorscheme is a palette JSON in
`dots/illogical-impulse/themes/` (currently `amalgamation.json`). The generator is
[`scripts/apply_theme.py`](file:///home/lowcache/.nix-config/dots/illogical-impulse/scripts/apply_theme.py).

* It reads a palette JSON (path from `argv[1]`, else
  `config.json → appearance.wallpaperTheming.masterTheme.jsonPath`) and **patches** the
  derived files: `Appearance.qml`, Hyprland `colors.conf`, kitty `current.conf`,
  kitty `tab_bar.py`, `starship.toml`. Then it runs `hyprctl reload` and `killall -USR1 kitty`.
* **Edit the palette JSON, not the generated outputs.** Re-running the script overwrites the
  generated files, so a hand-edit to `Appearance.qml` is lost on next apply.
* Hex values must be valid `#RRGGBB` / `#AARRGGBB`. An invalid color in `Appearance.qml`
  makes Quickshell fail to load the entire `illogical-impulse` config
  ("family unavailable"). See [`../.memory/mistakes.md`](file:///home/lowcache/.nix-config/dots/.memory/mistakes.md).
* Run it with: `python3 scripts/apply_theme.py <path-to-palette.json> true` (the `true`
  enables verbose output).

## 3. Independent History via git subtree

`dots/` is tracked **in one repo** with the rest of nix-config but can be published with its
own filtered history — no submodule, no separate working repo. Day-to-day targets live in
the root [`Makefile`](file:///home/lowcache/.nix-config/Makefile):

| Command | Effect |
|---|---|
| `make dots-log` | history scoped to `dots/` (read-only, no remote) |
| `make dots-split` | (re)build the `dots-history` projection branch |
| `make dots-remote URL=<url>` | one-time: add the standalone `dotfiles` remote |
| `make dots-push` / `make dots-pull` | publish / merge-back with the standalone remote |

These never move files, so the `mkOutOfStoreSymlink` paths are unaffected. Normal work
stays on `main`; the projection branch is a derived export artifact, not a branch you commit
to by hand.

## 4. Workflow Rules

* Hot-reload first, rebuild only when needed: edits under `dots/` are live immediately
  through the out-of-store symlinks. Do **not** add static Home-Manager `text`/`source`
  outputs that would replace the symlinks.
* After a theme change, the user may need to restart kitty / reload quickshell to see it.
* Keep `dots/.memory/` current: log config mistakes in `mistakes.md`, record durable
  choices in `decisions.md`, update `state.md` when the dotfile inventory changes.

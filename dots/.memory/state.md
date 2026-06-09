---
type: state
project: Vol NixOS — Dots
last_updated: 2026-06-09
status: active
---

# Dotfiles State Inventory (`dots/.memory/state.md`)

Single source of truth for the live state of the `dots/` subtree: what is symlinked where,
the theming pipeline, and the subtree publishing setup. Scoped layer beneath the
repo-root [`state.md`](file:///home/lowcache/.nix-config/.memory/state.md).

## Symlink Map (`home/persist.nix`, `mkOutOfStoreSymlink`)

All are **whole-directory** out-of-store symlinks from `~/.config/<name>` →
`/persist${HOME}/.nix-config/dots/<name>` (so edits are live without rebuild):

| `~/.config/` target | Source under `dots/` |
|---|---|
| `quickshell` | `dots/quickshell/` (config at `quickshell/ii/`) |
| `hypr` | `dots/hypr` |
| `illogical-impulse` | `dots/illogical-impulse` |
| `kitty` | `dots/kitty` |
| `fastfetch` | `dots/fastfetch` |
| `cava` | `dots/cava` |
| `fuzzel` | `dots/fuzzel` |
| `wlogout` | `dots/wlogout` |
| `starship.toml` | `dots/starship/starship.toml` (single file) |
| `~/.gemini` | `dots/gemini` (in `home.file`, `force = true`) |

`dots/` itself is **not** symlinked — only its children are. This is why `dots/.memory/`
and `dots/.model/` are safe homes for scoped context (they never reach `~/.config`).

## Theming Pipeline

* Palette source of truth: `dots/illogical-impulse/themes/amalgamation.json`
  ("Muted Amalgamation (Detailed)").
* Generator: `dots/illogical-impulse/scripts/apply_theme.py`.
  - Reads palette path from `argv[1]`, else
    `~/.config/illogical-impulse/config.json → appearance.wallpaperTheming.masterTheme.jsonPath`.
  - Patches: `quickshell/ii/modules/common/Appearance.qml`, `hypr/hyprland/colors.conf`,
    `kitty/current.conf`, `kitty/tab_bar.py`, `starship.toml`.
  - Post-actions: `hyprctl reload`, `killall -USR1 kitty`.
* Invocation used: `python3 scripts/apply_theme.py <palette.json> true`.
* Generated files are overwritten on each apply — edit the palette, not the outputs.
* Theme generator: `scripts/make_theme.py` builds a new standards-compliant theme JSON
  from raw colors (CLI args / `--colors "<str>"`) or any file containing hex codes
  (`--from`). It derives the background ramp, accents, containers, dim variants and a
  16-color terminal set, fills in M3 error/success tones, and validates (hex via
  `apply_theme.validate_palette` + dangling-reference check) before writing — refuses to
  write on failure. `--apply` applies it live.
* Theme validator: `scripts/check_theme.py <theme.json>` — hard-fails on bad hex / dangling
  refs, warns on roles missing vs amalgamation (the [[decisions]] D5 canonical template).
* Makefile targets (run from repo root; cut out long paths). `THEME` = bare name:
  - `make theme-list` — list theme names.
  - `make theme-apply THEME=<name>` — apply + reload.
  - `make theme-check THEME=<name>` — validate.
  - `make theme-new NAME="X" [COLORS="#a #b"] [FROM=<file>] [APPLY=1] [FORCE=1]` — generate.
    COLORS must be one quoted string (bare `#` args are shell comments otherwise).
* Coverage (as of 2026-06-09 expansion): the script now also patches `Appearance.qml`
  `term0`–`term15` (kept in sync with the kitty terminal palette via a single shared
  `term_hex` list), plus `m3primaryContainer`, `m3surfaceVariant`, `m3inverseSurface`, and
  the `m3error*` / `m3success*` families — all driven by the theme's `accents`/`surfaces`/
  `states`/`terminal` mappings. Palette gained derived tokens: `pure_white` (fixes the
  previously-dropped kitty `color15`), `peach_dim`, `coral_dim`, `coral_container`, and the
  M3 `error*` / `success*` sets.

## Active Theme & Live Reload

* **Active theme (2026-06-09):** `radioactive_slime.json` — neon green/yellow/orange "toxic"
  scheme on a green-tinted near-black background ramp. The **volinit** colors (`~/CodeRepo/volinit`,
  `src/volinit.nim`) are woven in as the structural/dim tones: PCB green `#AAD71E` →
  `primary_dim`/`inverse_primary`, die-gold `#CDB964` → `secondary_dim`, die-silver `#C8CDC8`
  → `fg`, grey-green `#96AA96` → outline/subtle. Hand-authored (not the generator) for
  art-direction control; 77 roles, `make theme-check` clean.
* Canonical templates: `amalgamation.json` + `petrified_spittoon.json` carry the full role
  set; new themes clone their mappings (see [[decisions]] D5).
* **Kitty live color reload (no restart):** `kitty.conf` has `allow_remote_control` +
  `listen_on unix:@mykitty`. `apply_theme.py` pushes to running windows via
  `kitty @ --to unix:@mykitty set-colors --all --configured <args>` (module constant
  `KITTY_SOCKET`), so `make theme-apply` recolors live; it skips gracefully when nothing is
  listening, and the `USR1` reload still handles tab-bar colors. Caveats: `@mykitty` is a
  fixed abstract socket so only the first kitty instance binds it; and `listen_on` applies
  only at kitty start, so windows opened before the config change need one restart.

## Subtree / Independent History

* Tracked in the single `nix-config` repo; publishable with filtered history via `git subtree`.
* Make targets (root Makefile): `dots-log`, `dots-split`, `dots-remote URL=`, `dots-push`,
  `dots-pull`. Config vars: `DOTS_PREFIX=dots`, `DOTS_REMOTE=dotfiles`, `DOTS_BRANCH=main`,
  `DOTS_SPLIT_BRANCH=dots-history`.
* `git subtree` confirmed available in this environment (2026-06-09).
* Standalone `dotfiles` remote: **not yet configured** (no `make dots-remote` run yet).

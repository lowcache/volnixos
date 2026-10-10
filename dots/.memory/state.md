---
type: state
project: Vol NixOS — Dots
last_updated: 2026-10-10
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
|---|
| `quickshell` | `dots/quickshell/` (config at `quickshell/ii/`) |
| `hypr` | `dots/hypr` |
| `illogical-impulse` | `dots/illogical-impulse` |
| `kitty` | `dots/kitty` |
| `fastfetch` | `dots/fastfetch` |
| `cava` | `dots/cava` |
| `fuzzel` | `dots/fuzzel` |
| `wlogout` | `dots/wlogout` |
| `color-engine` | `dots/color-engine/` (**new 2026-06-17**; needs `make switch`) |
| `niri` | `dots/niri/` |
| `starship.toml` | `dots/starship/starship.toml` (single file) |
| `~/.gemini` | `dots/gemini` (in `home.file`, `force = true`) |

`dots/` itself is **not** symlinked — only its children are. `dots/.memory/` is the safe
home for scoped memory and state; it never reaches `~/.config`.

**`~/.config/color-engine` symlink requires `make switch`** — added to `home/persist.nix`
2026-06-17, no rebuild run yet. Until then scripts/themes exist only at `dots/color-engine/`
relative paths.

## Theming Pipeline

* Palette/theme location: `dots/color-engine/themes/` (moved from
  `dots/illogical-impulse/themes/` 2026-06-17).
* Active theme JSON: `dots/color-engine/themes/radioactive_slime.json`.
* Generator: `dots/color-engine/apply_theme.py` (was `dots/illogical-impulse/scripts/apply_theme.py`).
  - Reads palette path from `argv[1]`, else
    `~/.config/illogical-impulse/config.json → appearance.wallpaperTheming.masterTheme.jsonPath`.
  - `config.json` `masterTheme.jsonPath` corrected to
    `~/.config/color-engine/themes/radioactive_slime.json`.
  - Patches: `quickshell/ii/modules/common/Appearance.qml`, `hypr/hyprland/colors.conf`,
    `kitty/current.conf`, `kitty/tab_bar.py`, `starship.toml`.
  - Also emits `~/.config/noctalia/palettes/volnix.json` (M3 palette for niri/Noctalia).
  - Post-actions: `hyprctl reload`, `killall -USR1 kitty`.
* `dots/color-engine/make_theme.py`, `dots/color-engine/check_theme.py` — moved from ii/scripts/.
* Remaining nuitka artifacts (`apply_theme.bin`, `apply_theme.dist/`) left at
  `dots/illogical-impulse/scripts/` — regenerable, not relocated.
* `switchwall.sh` (`dots/quickshell/ii/scripts/colors/switchwall.sh`, 2 sites): updated
  to call `~/.config/color-engine/apply_theme.py` with **no arg** (defers to configured
  `masterTheme.jsonPath`). Callers outside `apply_theme.py` never name a theme — see D7.
* Generated files overwritten on each apply — edit the palette, not the outputs.
* Makefile targets (run from repo root; `THEME` = bare name):
  `make theme-list`, `make theme-apply THEME=<name>`, `make theme-check THEME=<name>`,
  `make theme-new NAME="X" [COLORS="#a #b"] [FROM=<file>] [APPLY=1] [FORCE=1]`.
* ii's in-shell theme picker (lists `~/.config/illogical-impulse/themes/`) no longer sees
  themes after relocation; theming via setwall/apply_theme is unaffected.

## Tab Bar Color Management (`dots/kitty/tab_bar.py`)

**As of 2026-07-05:** tab_bar.py refactored to be engine-agnostic and dynamically read
colors from kitty's live configuration instead of hardcoded hex values.

* **Previous behavior:** Hardcoded color constants at module level (ICON_FG, ICON_BG,
  ACTIVE_FG, etc.) set to fixed hex values. Required manual edits to tab_bar.py when
  themes changed; kitty colors and tab_bar colors could drift.
* **Current behavior:** All tab bar colors now read from `get_options()`, which pulls
  directly from kitty's current config (`current.conf`, `current-theme.conf`). No manual
  edits needed; tab_bar automatically follows the active theme applied to kitty.
* **How it works:** Functions `_draw_tab()`, `_get_battery_info()`, `_draw_title()` each
  call `opts = get_options()` locally and extract colors via `opts.color<N>`, `opts.background`,
  `opts.foreground`, etc. If noctalia is active and mapping colors to kitty config, those
  mapped values flow through automatically.
* **Fallback:** If a color is not defined in kitty config, `get_options()` uses kitty's
  built-in defaults (typically 256-color palette).
* **Regeneration on theme apply:** When `apply_theme.py` rewrites `current.conf`, kitty
  reloads live; tab_bar picks up new colors on next tab render (no restart needed).

## Active Theme & Live Reload

* **Active theme (2026-06-09):** `radioactive_slime.json` — neon green/yellow/orange "toxic"
  scheme on a green-tinted near-black background. Now at `dots/color-engine/themes/`.
* Canonical templates: `amalgamation.json` + `petrified_spittoon.json` (both in `color-engine/themes/`).
* **Kitty live color reload:** `kitty.conf` has `allow_remote_control` +
  `listen_on unix:@mykitty`. `apply_theme.py` pushes via
  `kitty @ --to unix:@mykitty set-colors --all --configured`. `@mykitty` is abstract,
  bound by first kitty instance; applies only at kitty start.

## Quake Drop-Down Terminal (niri/kitty)

Architecture: **niri spawns process only; kitty owns all window logic** via wlr-layer-shell
(`quick-access-terminal` kitten) + kitty remote control. Compositor never manages the
quake window. This supersedes the old workspace-shuffling approach (deleted 2026-06-18).

**Files (all live via existing out-of-store symlinks):**
- `dots/kitty/quick-access-terminal.conf` — kitten config: `edge`, `lines`, `columns`,
  opacity, `focus_policy exclusive`, `app_id quake`, `allow_remote_control yes`, `listen_on`.
  Live at `~/.config/kitty/quick-access-terminal.conf`.
- `dots/niri/scripts/quake.sh` — control helper; 4-field state in
  `$XDG_RUNTIME_DIR/kitty-quake.state` (`orient`/`pos_h`/`pos_v`/`size`).
  Tunables at top: `NORMAL_LINES=25`, `PORTRAIT_FRAC=50`.
- `dots/niri/config.kdl` — keybinds in Apps section.
- **Deleted:** `dots/niri/scripts/quake_toggle.sh` (git rm'd 2026-06-18).

**Keybinds (orientation-aware, Hyprland parity):**

| Key | Landscape | Portrait |
|---|---|---|
| `Mod+Return` | show / hide | show / hide |
| `Mod+Shift+Return` | top ↔ bottom | left ↔ right |
| `Mod+Alt+Return` | normal ↔ full height | normal ↔ full width |
| `Mod+Ctrl+Return` | → switch to vertical | → switch to horizontal |

Full size (`Mod+Alt+Return → full`) is fullscreen in any orientation/edge — all four
full states measured pixel-identical: 266×62 cells on 1920×1200 (verified live 2026-06-18).
Each axis remembers its own side independently (flipping orientation preserves both
last top/bottom and last left/right).

**kitty layer-shell axis rules (verified live, kitty 0.47.2):**
- top/bottom panels: always full width, size HEIGHT via `lines`, `columns` silently ignored.
- left/right panels: always full height, size WIDTH via `columns`, `lines` ignored.
- Portrait = true vertical-edge panel (`edge=left`/`right`), NOT a margin-narrowed top strip.
- Width on horizontal panels: `margin-left`/`margin-right` (dashes, not underscores).
- Toggle visibility preserving geometry: `resize-os-window --action=toggle-visibility`.
  Bare `kitten quick-access-terminal` re-invoke RESETS geometry to conf defaults.
- Quake RC socket: `$XDG_RUNTIME_DIR/kitty-quake-<pid>` (pid-suffixed, a file).
- Single-instance group socket: `@kitty-ipc-<uid>-panel-quick-access` (abstract, not a file).
- **kitty config has NO inline comments** — everything after an option value on its line is
  the value. Comments must be on their own lines. Silent exit = likely a comment-as-value.
- `allow_remote_control` + `listen_on` must be in the kitten conf (via `kitty_override`).
  kitty appends `-<pid>` to the listen socket path.

## Niri Config (`dots/niri/`)

`dots/niri/` symlinked to `~/.config/niri`. Active config: `config.kdl`.

- Numeric workspace refs = INDEX; named refs = NAME. Declared named workspace is always idx 1;
  dynamic workspaces = idx 2+. Mod+1..9 bound to focus-workspace 2..10.
- Touchpad toggle: `dots/niri/scripts/touchpad_toggle.sh` flips `// off // @tptoggle@` marker
  in `config.kdl` touchpad block + `niri msg action load-config-file`. Default/committed =
  enabled. Bound to F10 + XF86TouchpadToggle.
- Launch scripts reuse `~/.config/hypr/hyprland/scripts/launch_first_available.sh` (agnostic).
- Audio: BT headset (`hardware.bluetooth.enable = true`) auto-grabs default sink.
  Workaround: `wpctl set-default <analog-id>`. Consider WirePlumber rule to suppress auto-switch.
- `niri validate -c <config>` for pre-apply validation.

## memd Registration

As of 2026-06-18: `dots` is registered as a memd project
(`/home/lowcache/.nix-config/dots`). `scripts/memd/memd.py` (`transcript_files`) patched:
claude dirs owned by a longer-prefix registered project are excluded from the parent
project's sweep — mirrors `find_project`'s existing longest-prefix logic; backward-compatible.
Dots inbox notes now swept and attributed independently from root `.memory/`.

## Subtree / Independent History

* Make targets: `dots-log`, `dots-split`, `dots-remote URL=`, `dots-push`, `dots-pull`.
* Config: `DOTS_PREFIX=dots`, `DOTS_REMOTE=dotfiles`, `DOTS_BRANCH=main`,
  `DOTS_SPLIT_BRANCH=dots-history`.
* `git subtree` confirmed available (2026-06-09).
* Standalone `dotfiles` remote: **not yet configured**.

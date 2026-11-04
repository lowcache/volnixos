---
type: todo
project: Vol NixOS — Dots
last_updated: 2026-11-03
status: active
---

# Dotfiles Open Tasks (`dots/.memory/todo.md`)

Open loops and pending verification for the `dots/` subtree. Scoped layer beneath repo-root
[`todo.md`](file:///home/lowcache/.nix-config/.memory/todo.md). Move done items to
[`archive/`](file:///home/lowcache/.nix-config/dots/.memory/archive/).

## Strategic: Niri Desktop Completion (per [[decisions]] D10)

Complete verification and paradigm decoupling to declare niri 100% ready; then decide
Hyprland's fate (fallback or removal).

* [ ] **Niri verification checklist** — confirm each on live system:
  - [ ] Workspace navigation (Mod+1..9 focus; dynamic vs. named workspace behavior)
  - [ ] Krita performance under sustained drawing load (regression check)
  - [ ] Touchpad F10 enable/disable toggle; pointer inhibition during input
  - [ ] App launchers (Super+T, E, W, C, Space, Tab) all launch correctly
  - [ ] Audio subsystem (speaker default, BT headset auto-switch, volume/mute)

* [ ] **Decouple niri and Hyprland in `dots/`.** Several niri keybinds currently invoke
  `~/.config/hypr/hyprland/scripts/…` (shared launcher helpers). Make these
  compositor-agnostic or relocate out of `hypr/` before demoting Hyprland, or they will
  break niri.

* [ ] **Decide Hyprland's fate after niri verification 100% complete.** Options:
  (a) Fallback — keep functional but marked secondary; (b) Removal — delete `dots/hypr/`,
  clean up Home-Manager wiring and dependencies. Make the decision explicit, not implicit.

## Tab Bar & Theme Integration (per [[decisions]] D11)

* [ ] **Verify tab_bar.py dynamic color reads work end-to-end.** Test that colors update
  correctly when a new theme is applied via `make theme-apply THEME=<name>`. Confirm:
  - Tab bar colors match the active theme's `current.conf` values immediately after apply
  - No manual restart of kitty needed
  - Noctalia color mappings (if active) properly flow through to tab_bar
  - Fallback behavior when a color is undefined (uses kitty defaults gracefully)

## Open (pre-niri, ongoing)

* [ ] **`make switch` needed to activate `~/.config/color-engine` symlink.** Added to
  `home/persist.nix` 2026-06-17, no rebuild run yet. Until then, `apply_theme.py` /
  `make_theme.py` / `check_theme.py` / `themes/` are only at `dots/color-engine/` relative
  paths, not the live `~/.config/color-engine/` path that scripts expect post-switch.

* [ ] **Decide whether to publish the dotfiles subtree.** If yes: create standalone repo,
  then `make dots-remote URL=<git-url>` and `make dots-push`. If no: `make dots-log` /
  `make dots-split` sufficient for independent local history. (No remote configured yet
  as of 2026-06-09.)

* [ ] **First `make dots-split` run is untested** — it walks full history and builds the
  `dots-history` branch. Run once to confirm it succeeds on this repo's history size.

* [ ] **Optional: decouple `apply_theme.py` theme selector from ii config.** Currently reads
  `~/.config/illogical-impulse/config.json`. Could migrate to `~/.config/color-engine/active.json`
  for full compositor-agnosticism. Low urgency — works across both compositors as-is.

* [ ] **Optional: compositor-agnostic touchpad toggle via kernel `inhibited` sysfs.** A udev
  rule granting `users`/`input` group write to device's `inhibited` file would avoid the
  current niri workaround (config-marker flip + load-config-file). Needs rebuild + reboot.
  Current approach functional; cleanup option only.

## Done / Verified

* [x] `#90C722q` colorscheme typo fixed and theme re-applied (2026-06-09).
* [x] Palette validation added to `apply_theme.py` (2026-06-09).
* [x] Color engine relocated to `dots/color-engine/`; `switchwall.sh` and `config.json`
  references updated; `home/persist.nix` symlink added (2026-06-17).
* [x] `dots` registered as memd project; `memd.py transcript_files` patched for
  longest-prefix exclusion; dots sync pipeline verified (2026-06-18).
* [x] tab_bar.py refactored to read colors dynamically from kitty options instead of
  hardcoded values (2026-07-05). Now engine-agnostic and reflects active theme automatically.

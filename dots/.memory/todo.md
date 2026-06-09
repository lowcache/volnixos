---
type: todo
project: Vol NixOS — Dots
last_updated: 2026-06-09
status: active
---

# Dotfiles Open Tasks (`dots/.memory/todo.md`)

Open loops and pending verification for the `dots/` subtree. Scoped layer beneath repo-root
[`todo.md`](file:///home/lowcache/.nix-config/.memory/todo.md). Move done items to
[`archive/`](file:///home/lowcache/.nix-config/dots/.memory/archive/).

## Open

* [ ] **Decide whether to publish the dotfiles subtree.** If yes: create a standalone repo,
  then `make dots-remote URL=<git-url>` and `make dots-push`. If no: `make dots-log` /
  `make dots-split` are enough for an independent local history view. (No remote configured
  yet as of 2026-06-09.)
* [ ] **First `make dots-split` run is untested** — it walks full history and builds the
  `dots-history` branch. Run once to confirm it succeeds on this repo's history size.
## Verify

* [x] `#90C722q` colorscheme typo fixed and theme re-applied (2026-06-09). User to restart
  kitty / reload quickshell to confirm visually.
* [x] Palette validation added to `apply_theme.py` (2026-06-09): `validate_palette()`
  fails fast before any file write if a value isn't valid 3/4/6/8-digit hex. Verified it
  catches the M1 `#90C722q` case and that the real palette still applies. Prevents repeat
  of M1.

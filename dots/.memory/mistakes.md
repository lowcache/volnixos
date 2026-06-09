---
type: mistakes
project: Vol NixOS — Dots
last_updated: 2026-06-09
status: active
---

# Dotfiles Mistakes Log (`dots/.memory/mistakes.md`)

Append-only audit log of config mistakes in the `dots/` subtree, their cause, and the exact
prevention rule. Move resolved/obsolete entries to
[`archive/`](file:///home/lowcache/.nix-config/dots/.memory/archive/) to keep this concise.

---

## M1 — Invalid hex color broke the entire Quickshell config (2026-06-09)

* **Symptom:** Quickshell: *"failed to load configuration — illogical-impulse: family
  unavailable: illogical-impulse."* The whole illogical-impulse shell/rice failed to load.
* **Cause:** A typo in the palette `themes/amalgamation.json` — `"dark_teal": "#90C722q"`
  (stray `q`, 7 chars, non-hex). `apply_theme.py` propagated it into `Appearance.qml`
  (`m3primaryFixedDim: "#90C722q"`). QML cannot parse an invalid color literal, so the
  `Appearance` singleton — the root of the config — failed to construct, taking the whole
  shell down with it.
* **Fix:** Corrected the palette to `"#90C722"`, re-ran
  `python3 scripts/apply_theme.py <palette.json> true`. The generated `Appearance.qml`
  (symlinked from `dots/`) updated to a valid value; no other invalid hex present.
* **Prevention rule:** After editing any palette/theme JSON, validate every value is a
  valid `#RRGGBB` or `#AARRGGBB` literal (6/8 hex chars, no stray characters) **before**
  applying. A single bad color cascades into a total Quickshell load failure, not a
  localized glitch. Fix at the palette source, never by hand-editing generated outputs.

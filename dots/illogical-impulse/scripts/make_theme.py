#!/usr/bin/env python3
"""Quick-and-dirty theme generator for the illogical-impulse pipeline.

Takes a handful of colors (CLI args) or a file containing colors (any text/conf/JSON
with hex codes in it) and emits a theme JSON that meets the current standard: a full
`surfaces / accents / text / states / terminal` mapping set, the same role layout used
by themes/amalgamation.json and themes/petrified_spittoon.json (see dots/.memory D5).

It derives backgrounds, accents, containers, dim variants and a 16-color terminal set
from whatever you feed it, fills in M3 error/success tones, then validates the result
(hex validity via apply_theme.validate_palette + dangling-reference check) and refuses
to write anything that fails.

Usage:
  make_theme.py --name "My Theme" --out themes/my_theme.json "#1e1e2e" "#cba6f7" "#a6e3a1" ...
  make_theme.py --name "My Theme" --from ~/.config/some/colors.conf
  make_theme.py --name "My Theme" --from palette.json --apply     # also apply it live
"""
import argparse, json, os, re, sys, subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from apply_theme import validate_palette  # canonical validator, single source of truth
except Exception:
    # Fallback copy so the tool still works if apply_theme isn't importable.
    def validate_palette(palette):
        bad = []
        for name, value in palette.items():
            if not isinstance(value, str):
                bad.append((name, value, "not a string")); continue
            v = value.strip()
            if not re.fullmatch(r"#?[0-9A-Fa-f]+", v):
                bad.append((name, value, "contains non-hex characters")); continue
            if len(v.lstrip("#")) not in (3, 4, 6, 8):
                bad.append((name, value, f"{len(v.lstrip('#'))} hex digits (expected 3/4/6/8)"))
        return bad

HEX_RE = re.compile(r"#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{4}|[0-9a-fA-F]{3})(?![0-9a-fA-F])")

# ---- color math -----------------------------------------------------------

def _norm(hexv):
    h = hexv.lstrip("#")
    if len(h) in (3, 4): h = "".join(c * 2 for c in h)
    return "#" + h[:6].upper()

def to_rgb(hexv):
    h = _norm(hexv).lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def to_hex(rgb):
    return "#" + "".join(f"{max(0,min(255,round(c))):02X}" for c in rgb)

def luma(hexv):
    r, g, b = to_rgb(hexv)
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0

def mix(a, b, t):
    ra, ga, ba = to_rgb(a); rb, gb, bb = to_rgb(b)
    return to_hex((ra + (rb - ra) * t, ga + (gb - ga) * t, ba + (bb - ba) * t))

def lighten(c, t): return mix(c, "#FFFFFF", t)
def darken(c, t):  return mix(c, "#000000", t)

def rgb_to_hsl(rgb):
    r, g, b = (x / 255.0 for x in rgb)
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2; d = mx - mn
    if d == 0: return 0.0, 0.0, l
    s = d / (1 - abs(2 * l - 1)) if l not in (0, 1) else 0
    if mx == r:   h = ((g - b) / d) % 6
    elif mx == g: h = (b - r) / d + 2
    else:         h = (r - g) / d + 4
    return h * 60, s, l

def hsl_to_hex(h, s, l):
    c = (1 - abs(2 * l - 1)) * s
    x = c * (1 - abs((h / 60) % 2 - 1)); m = l - c / 2
    r, g, b = {0:(c,x,0),1:(x,c,0),2:(0,c,x),3:(0,x,c),4:(x,0,c),5:(c,0,x)}[int(h//60) % 6]
    return to_hex(((r+m)*255, (g+m)*255, (b+m)*255))

def chroma(hexv):
    r, g, b = to_rgb(hexv)
    return (max(r, g, b) - min(r, g, b)) / 255.0

def hue(hexv): return rgb_to_hsl(to_rgb(hexv))[0]

def hue_dist(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)

# ---- input ----------------------------------------------------------------

def gather_colors(args_colors, from_file, colors_str=None):
    raw = list(args_colors)
    if colors_str:
        raw += HEX_RE.findall(colors_str)
    if from_file:
        text = open(os.path.expanduser(from_file)).read()
        try:
            data = json.loads(text)
            vals = list(data.values()) if isinstance(data, dict) else (data if isinstance(data, list) else [])
            for v in vals:
                if isinstance(v, str): raw.append(v)
        except json.JSONDecodeError:
            pass
        raw += HEX_RE.findall(text)
    seen, out = set(), []
    for c in raw:
        m = HEX_RE.fullmatch(c.strip()) or (HEX_RE.search(c) if isinstance(c, str) else None)
        if not m: continue
        nh = _norm(m.group(0))
        if nh not in seen:
            seen.add(nh); out.append(nh)
    return out

# ---- derivation -----------------------------------------------------------

def pick_accents(colors):
    cand = sorted([c for c in colors if chroma(c) > 0.12], key=chroma, reverse=True)
    if not cand:
        # no saturated input: synthesize a default analogous trio
        base = "#AAD71E"
        return [base, hsl_to_hex((hue(base) + 150) % 360, 0.55, 0.65),
                hsl_to_hex((hue(base) - 110) % 360, 0.6, 0.6)]
    chosen = [cand[0]]
    for c in cand[1:]:
        if all(hue_dist(hue(c), hue(p)) > 40 for p in chosen):
            chosen.append(c)
        if len(chosen) == 3: break
    while len(chosen) < 3:  # rotate to fill missing accents
        chosen.append(hsl_to_hex((hue(chosen[0]) + 130 * len(chosen)) % 360, 0.55, 0.6))
    return chosen[:3]

def term_color(colors, target_hue, fallback_s=0.55, fallback_l=0.55):
    cand = [c for c in colors if chroma(c) > 0.15]
    near = min(cand, key=lambda c: hue_dist(hue(c), target_hue), default=None)
    if near and hue_dist(hue(near), target_hue) <= 25:
        return near
    return hsl_to_hex(target_hue, fallback_s, fallback_l)

def build_theme(name, colors):
    if not colors:
        raise SystemExit("Error: no usable colors found in input.")

    darks  = sorted([c for c in colors if luma(c) < 0.30], key=luma)
    lights = sorted([c for c in colors if luma(c) > 0.70], key=luma, reverse=True)

    base_dark = darks[0] if darks else darken(colors[0], 0.86)
    fg   = lights[0] if lights else "#C1C1C1"
    cream = lights[1] if len(lights) > 1 else lighten(fg, 0.12)

    primary, secondary, tertiary = pick_accents(colors)

    palette = {
        # neutral background ramp derived from the darkest input
        "bg_deep":     base_dark,
        "bg_dim":      lighten(base_dark, 0.04),
        "bg":          lighten(base_dark, 0.09),
        "bg_low":      lighten(base_dark, 0.14),
        "bg_mid":      lighten(base_dark, 0.20),
        "bg_high":     lighten(base_dark, 0.26),
        "bg_highest":  lighten(base_dark, 0.32),
        "gray":        lighten(base_dark, 0.20),
        "charcoal":    lighten(base_dark, 0.42),
        "fg":          fg,
        "cream":       cream,
        "pure_white":  lighten(cream, 0.25),
        # accents + derived dim / container tones
        "primary":              primary,
        "primary_dim":          darken(primary, 0.16),
        "primary_container":    mix(primary, base_dark, 0.82),
        "secondary":            secondary,
        "secondary_dim":        darken(secondary, 0.16),
        "secondary_container":  mix(secondary, base_dark, 0.82),
        "tertiary":             tertiary,
        "tertiary_dim":         darken(tertiary, 0.16),
        "tertiary_container":   mix(tertiary, base_dark, 0.82),
        # terminal hues (prefer input, else synthesized at standard hue)
        "term_red":     term_color(colors, 0),
        "term_green":   term_color(colors, 120),
        "term_yellow":  term_color(colors, 50, 0.6, 0.6),
        "term_blue":    term_color(colors, 220),
        "term_magenta": term_color(colors, 300),
        "term_cyan":    term_color(colors, 180),
        # M3 semantic states (standard dark-mode tones)
        "error": "#FFB4AB", "error_dark": "#690005",
        "error_container": "#93000A", "error_light": "#FFDAD6",
        "success": "#B5CCBA", "success_dark": "#213528",
        "success_container": "#374B3E", "success_light": "#D1E9D6",
    }

    mappings = {
        "surfaces": {
            "main_bg": "bg_deep", "background": "bg_deep", "surface": "bg_dim",
            "surface_dim": "bg_deep", "surface_bright": "bg_low",
            "surface_container_lowest": "bg_deep", "surface_container_low": "bg_dim",
            "surface_container": "bg", "surface_container_high": "bg_low",
            "surface_container_highest": "bg_mid", "surface_variant": "bg_low",
            "inverse_surface": "fg", "sidebar_bg": "bg_deep",
            "popup_bg": "bg_dim", "cards_bg": "bg_dim",
        },
        "accents": {
            "primary": "primary", "primary_active": "primary",
            "primary_container": "primary_container", "primary_fixed": "primary",
            "primary_fixed_dim": "primary_dim", "surface_tint": "primary",
            "inverse_primary": "primary_dim", "secondary": "secondary",
            "secondary_active": "secondary", "secondary_container": "secondary_container",
            "secondary_fixed": "secondary", "secondary_fixed_dim": "secondary_dim",
            "tertiary": "tertiary", "tertiary_active": "tertiary",
            "tertiary_container": "tertiary_container", "tertiary_fixed": "tertiary",
            "tertiary_fixed_dim": "tertiary_dim", "outline": "charcoal",
            "outline_variant": "bg_low", "borders": "charcoal", "links": "tertiary",
        },
        "text": {
            "normal": "cream", "on_background": "cream", "on_surface": "cream",
            "on_surface_variant": "fg", "on_primary": "bg_deep", "on_secondary": "bg_deep",
            "on_tertiary": "bg_deep", "on_primary_container": "primary",
            "on_secondary_container": "secondary", "on_tertiary_container": "tertiary",
            "on_primary_fixed": "bg_deep", "on_secondary_fixed": "bg_deep",
            "on_tertiary_fixed": "bg_deep", "on_primary_fixed_variant": "primary_container",
            "inverse_on_surface": "bg_deep", "subtle": "charcoal", "on_accent": "bg_deep",
        },
        "states": {
            "error": "error", "on_error": "error_dark",
            "error_container": "error_container", "on_error_container": "error_light",
            "success": "success", "on_success": "success_dark",
            "success_container": "success_container", "on_success_container": "success_light",
        },
        "terminal": {
            "black": "bg_dim", "red": "term_red", "green": "term_green",
            "yellow": "term_yellow", "blue": "term_blue", "magenta": "term_magenta",
            "cyan": "term_cyan", "white": "fg", "bright_black": "gray",
            "bright_red": "term_red", "bright_green": "term_green",
            "bright_yellow": "cream", "bright_blue": "term_blue",
            "bright_magenta": "term_magenta", "bright_cyan": "term_cyan",
            "bright_white": "pure_white",
        },
    }
    return {"name": name, "palette": palette, "mappings": mappings}

# ---- validation -----------------------------------------------------------

def validate_theme(theme):
    errors = []
    pal = theme["palette"]
    for n, v, reason in validate_palette(pal):
        errors.append(f"invalid color {n}: {v!r} ({reason})")
    for section, roles in theme["mappings"].items():
        for role, ref in roles.items():
            if isinstance(ref, str) and ref.startswith("#"): continue
            if ref not in pal:
                errors.append(f"dangling reference {section}.{role} -> {ref}")
    return errors

# ---- main -----------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Generate a standards-compliant theme JSON from colors.")
    ap.add_argument("colors", nargs="*", help="hex colors, e.g. '#1e1e2e' '#cba6f7'")
    ap.add_argument("--colors", dest="colors_str", help="hex colors as one string (handy from Make/shell)")
    ap.add_argument("--from", dest="from_file", help="read colors from a file (any text/JSON with hex codes)")
    ap.add_argument("--name", help="theme display name (default derived from --out)")
    ap.add_argument("--out", help="output path (default themes/<slug>.json)")
    ap.add_argument("--apply", action="store_true", help="apply the theme live after writing")
    ap.add_argument("--force", action="store_true", help="overwrite an existing output file")
    args = ap.parse_args()

    colors = gather_colors(args.colors, args.from_file, args.colors_str)
    here = os.path.dirname(os.path.abspath(__file__))
    themes_dir = os.path.join(os.path.dirname(here), "themes")

    name = args.name or (os.path.splitext(os.path.basename(args.out))[0].replace("_", " ").title()
                         if args.out else "Custom Theme")
    slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_") or "custom_theme"
    out = os.path.expanduser(args.out) if args.out else os.path.join(themes_dir, f"{slug}.json")

    print(f"Input colors ({len(colors)}): {', '.join(colors) if colors else '(none)'}")
    theme = build_theme(name, colors)

    errors = validate_theme(theme)
    if errors:
        print("VALIDATION FAILED — not writing:", file=sys.stderr)
        for e in errors: print(f"  - {e}", file=sys.stderr)
        sys.exit(1)
    print(f"Validation: PASS ({len(theme['palette'])} palette tokens, "
          f"{sum(len(v) for v in theme['mappings'].values())} mapped roles, no dangling refs)")

    if os.path.exists(out) and not args.force:
        sys.exit(f"Refusing to overwrite existing {out} (use --force).")
    with open(out, "w") as f:
        json.dump(theme, f, indent=2); f.write("\n")
    print(f"Wrote {out}")

    if args.apply:
        print("Applying...")
        subprocess.run([sys.executable, os.path.join(here, "apply_theme.py"), out, "true"])

if __name__ == "__main__":
    main()

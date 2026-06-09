#!/usr/bin/env python3
import json, os, subprocess, sys, re

# Paths
CONFIG_PATH = os.path.expanduser("~/.config/illogical-impulse/config.json")
APPEARANCE_QML = os.path.expanduser("~/.config/quickshell/ii/modules/common/Appearance.qml")
HYPR_COLORS = os.path.expanduser("~/.config/hypr/hyprland/colors.conf")
KITTY_COLORS = os.path.expanduser("~/.config/kitty/current.conf")
KITTY_TABBAR = os.path.expanduser("~/.config/kitty/tab_bar.py")
STARSHIP_TOML = os.path.expanduser("~/.config/starship.toml")

# Technical Mapping for Appearance.qml
TECHNICAL_MAP = {
    "surfaces.main_bg": [
        "m3background", "m3surface", "m3surfaceDim", "m3surfaceBright", 
        "m3surfaceContainerLowest", "m3surfaceContainerLow", 
        "m3surfaceContainer", "m3surfaceContainerHigh", 
        "m3surfaceContainerHighest"
    ],
    "accents.primary_active": [
        "m3primary", "m3surfaceTint", 
        "m3primaryFixed", "m3primaryFixedDim", "m3inversePrimary"
    ],
    "accents.secondary_active": [
        "m3secondary", "m3secondaryContainer", 
        "m3secondaryFixed", "m3secondaryFixedDim",
        "m3outline", "m3outlineVariant"
    ],
    "accents.tertiary_active": [
        "m3tertiary", "m3tertiaryContainer",
        "m3tertiaryFixed", "m3tertiaryFixedDim"
    ],
    "text.normal": [
        "m3onBackground", "m3onSurface", 
        "m3onSurfaceVariant", "m3inverseOnSurface"
    ],
    "text.on_accent": [
        "m3onPrimary", "m3onSecondary", "m3onTertiary",
        "m3onPrimaryContainer", "m3onSecondaryContainer", "m3onTertiaryContainer",
        "m3onPrimaryFixed", "m3onSecondaryFixed", "m3onTertiaryFixed"
    ]
}

def validate_palette(palette):
    """Return a list of (name, value, reason) for any palette entry that is not a
    valid hex color. QML accepts #RGB, #RGBA, #RRGGBB, #AARRGGBB (3/4/6/8 hex digits).
    A single bad literal (e.g. "#90C722q") makes Quickshell fail to load the entire
    config, so the apply is aborted before any files are written."""
    bad = []
    for name, value in palette.items():
        if not isinstance(value, str):
            bad.append((name, value, "not a string"))
            continue
        v = value.strip()
        if not re.fullmatch(r"#?[0-9A-Fa-f]+", v):
            bad.append((name, value, "contains non-hex characters"))
            continue
        digits = len(v.lstrip("#"))
        if digits not in (3, 4, 6, 8):
            bad.append((name, value, f"{digits} hex digits (expected 3, 4, 6, or 8)"))
    return bad


def apply_theme(theme_path, verbose=False):
    if not os.path.exists(theme_path):
        if verbose: print(f"Error: Theme file not found at {theme_path}")
        return False
    
    try:
        with open(theme_path, "r") as f:
            theme = json.load(f)
    except Exception as e:
        if verbose: print(f"Error parsing theme JSON: {e}")
        return False

    palette = theme.get("palette", {})
    mappings = theme.get("mappings", {})
    
    if not palette:
        if verbose: print("Error: No palette found in theme file.")
        return False

    # Fail fast on bad colors so nothing is written to the live (symlinked) configs.
    bad_colors = validate_palette(palette)
    if bad_colors:
        print(f"Error: invalid hex color(s) in palette '{theme_path}' — aborting, no files written:", file=sys.stderr)
        for name, value, reason in bad_colors:
            print(f"  - {name}: {value!r} ({reason})", file=sys.stderr)
        return False

    # Get standard colors
    bg = palette.get(mappings.get("surfaces", {}).get("main_bg"), "#1c1c1c")
    primary = palette.get(mappings.get("accents", {}).get("primary_active"), "#e78a53")
    secondary = palette.get(mappings.get("accents", {}).get("secondary_active"), "#fbcb97")
    fg = palette.get(mappings.get("text", {}).get("normal"), "#c1c1c1")

    # Helper for RGB (no #)
    def to_rgb(hex_val): return hex_val.lstrip("#")

    bg_rgb = to_rgb(bg)
    primary_rgb = to_rgb(primary)
    secondary_rgb = to_rgb(secondary)
    fg_rgb = to_rgb(fg)

    # 1. Patch Appearance.qml
    if os.path.exists(APPEARANCE_QML):
        try:
            full_map = {}
            for group_key, tech_names in TECHNICAL_MAP.items():
                section, group_name = group_key.split(".")
                for tech_name in tech_names:
                    # tech_name is like "m3surfaceContainerLow"
                    # we want to look up "surface_container_low" OR "main_bg"
                    role_name = tech_name
                    if role_name.startswith("m3"):
                        role_name = role_name[2:] # "surfaceContainerLow"
                        # Convert camelCase to underscores: "surface_container_low"
                        role_name = re.sub(r"([A-Z])", r"_\1", role_name).lower().lstrip("_")
                    
                    color_name = mappings.get(section, {}).get(role_name) or mappings.get(section, {}).get(group_name)
                    if color_name:
                        hv = palette.get(color_name) or (color_name if color_name.startswith("#") else None)
                        if hv:
                            if not hv.startswith("#"): hv = "#" + hv
                            full_map[tech_name] = hv

            with open(APPEARANCE_QML, "r") as f: lines = f.readlines()
            new_lines = []
            for line in lines:
                patched = False
                for role, hv in full_map.items():
                    if f"property color {role}:" in line:
                        line = f"        property color {role}: \"{hv}\"\n"
                        patched = True
                        break
                    elif role.startswith("m3"):
                        col_role = "col" + role[2:]
                        if f"property color {col_role}:" in line:
                            line = f"        property color {col_role}: \"{hv}\"\n"
                            patched = True
                            break
                new_lines.append(line)
            with open(APPEARANCE_QML, "w") as f: f.writelines(new_lines)
            if verbose: print("Patched Appearance.qml")
        except Exception as e:
            if verbose: print(f"Error patching QML: {e}")

    # 2. Hyprland colors
    try:
        hypr_content = f"""# Generated
general {{
    col.active_border = rgba({primary_rgb}77)
    col.inactive_border = rgba({secondary_rgb}55)
}}
misc {{ background_color = rgba({bg_rgb}FF) }}
plugin {{
    hyprbars {{
        bar_color = rgba({bg_rgb}FF)
        col.text = rgba({fg_rgb}FF)
    }}
}}
"""
        with open(HYPR_COLORS, "w") as f: f.write(hypr_content)
        if verbose: print("Updated Hyprland colors")
    except Exception as e:
        if verbose: print(f"Error updating Hyprland: {e}")

    # 3. Kitty current.conf
    try:
        kitty_content = f"# Generated\nbackground {bg}\nforeground {fg}\nselection_background {primary}\nselection_foreground {bg}\ncursor {primary}\n"
        kitty_content += f"active_tab_foreground {bg}\nactive_tab_background {primary}\ninactive_tab_foreground {secondary}\ninactive_tab_background {bg}\ntab_bar_background {bg}\n"
        
        term_map = mappings.get("terminal", {})
        term_names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
                      "bright_black", "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta", "bright_cyan", "bright_white"]
        for i, name in enumerate(term_names):
            cname = term_map.get(name)
            if cname and palette.get(cname): kitty_content += f"color{i} {palette[cname]}\n"
        
        with open(KITTY_COLORS, "w") as f: f.write(kitty_content)
        if verbose: print("Updated Kitty current.conf")
    except Exception as e:
        if verbose: print(f"Error updating Kitty: {e}")

    # 4. Kitty tab_bar.py
    if os.path.exists(KITTY_TABBAR):
        try:
            with open(KITTY_TABBAR, "r") as f: content = f.read()
            content = re.sub(r"ACTIVE_BG = as_rgb\(0x[0-9a-fA-F]+\)", f"ACTIVE_BG = as_rgb(0x{primary_rgb})", content)
            content = re.sub(r"ACTIVE_FG = as_rgb\(0x[0-9a-fA-F]+\)", f"ACTIVE_FG = as_rgb(0x{bg_rgb})", content)
            content = re.sub(r"ICON_BG = as_rgb\(0x[0-9a-fA-F]+\)", f"ICON_BG = as_rgb(0x{bg_rgb})", content)
            content = re.sub(r"INACTIVE_BG = as_rgb\(0x[0-9a-fA-F]+\)", f"INACTIVE_BG = as_rgb(0x{bg_rgb})", content)
            content = re.sub(r"INACTIVE_FG = as_rgb\(0x[0-9a-fA-F]+\)", f"INACTIVE_FG = as_rgb(0x{secondary_rgb})", content)
            with open(KITTY_TABBAR, "w") as f: f.write(content)
            if verbose: print("Updated Kitty tab_bar.py")
        except Exception as e:
            if verbose: print(f"Error updating tab_bar.py: {e}")

    # 5. Starship.toml
    if os.path.exists(STARSHIP_TOML):
        try:
            with open(STARSHIP_TOML, "r") as f: content = f.read()
            
            # Ensure palette = "current"
            content = re.sub(r'^palette = ".*"', 'palette = "current"', content, flags=re.MULTILINE)
            
            # Rebuild [palettes.current]
            palette_section = f'[palettes.current]\n'
            palette_section += f'black = "{bg}"\n'
            palette_section += f'red = "{palette.get(term_map.get("red"), primary)}"\n'
            palette_section += f'green = "{palette.get(term_map.get("green"), secondary)}"\n'
            palette_section += f'yellow = "{primary}"\n'
            palette_section += f'blue = "{secondary}"\n'
            palette_section += f'magenta = "{palette.get(term_map.get("magenta"), primary)}"\n'
            palette_section += f'cyan = "{palette.get(term_map.get("cyan"), secondary)}"\n'
            palette_section += f'white = "{fg}"\n'

            # Replace any existing palette section like [palettes.ps] or [palettes.current]
            content = re.sub(r'\[palettes\..*\](\n.*)*', palette_section, content)
            
            with open(STARSHIP_TOML, "w") as f: f.write(content)
            if verbose: print("Updated starship.toml")
        except Exception as e:
            if verbose: print(f"Error updating starship: {e}")

    return True

if __name__ == "__main__":
    try:
        theme_path = ""
        verbose = False
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH, "r") as f: config = json.load(f)
            themecfg = config.get("appearance", {}).get("wallpaperTheming", {}).get("masterTheme", {})
            verbose = themecfg.get("verboseOutput", False)
            theme_path = os.path.expanduser(themecfg.get("jsonPath", ""))
        if len(sys.argv) > 1: theme_path = os.path.expanduser(sys.argv[1])
        if len(sys.argv) > 2: verbose = sys.argv[2].lower() == "true"
        if apply_theme(theme_path, verbose):
            subprocess.run(["hyprctl", "reload"], capture_output=True)
            subprocess.run(["killall", "-USR1", "kitty"], capture_output=True)
            if verbose: print("Theme Applied Successfully.")
    except Exception as e:
        print(f"Critical Error: {e}")
        sys.exit(1)

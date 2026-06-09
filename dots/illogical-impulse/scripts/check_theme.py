#!/usr/bin/env python3
"""Validate a theme JSON against the current standard.

Hard-fails (exit 1) on invalid hex colors or dangling mapping references (a mapping
value that names a palette key which doesn't exist). Warns — but does not fail — if the
theme is missing roles that the canonical template (amalgamation.json) defines, since a
missing role silently falls back to a stale hardcoded value at apply time.

Usage: check_theme.py <theme.json>
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_theme import validate_theme  # reuses apply_theme.validate_palette under the hood

REFERENCE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                         "themes", "amalgamation.json")

def main():
    if len(sys.argv) < 2:
        sys.exit("Usage: check_theme.py <theme.json>")
    path = os.path.expanduser(sys.argv[1])
    try:
        theme = json.load(open(path))
    except FileNotFoundError:
        sys.exit(f"No such theme file: {path}")
    except json.JSONDecodeError as e:
        sys.exit(f"FAIL: {path} is not valid JSON ({e})")

    errors = validate_theme(theme)
    if errors:
        print(f"FAIL: {os.path.basename(path)}", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)

    # Completeness check against the canonical role set (warning only).
    missing = []
    if os.path.exists(REFERENCE) and os.path.abspath(path) != os.path.abspath(REFERENCE):
        ref = json.load(open(REFERENCE))["mappings"]
        gen = theme.get("mappings", {})
        for sec, roles in ref.items():
            for role in roles:
                if role not in gen.get(sec, {}):
                    missing.append(f"{sec}.{role}")

    roles = sum(len(v) for v in theme.get("mappings", {}).values())
    print(f"PASS: {os.path.basename(path)} "
          f"({len(theme.get('palette', {}))} tokens, {roles} roles, no dangling refs)")
    if missing:
        print(f"WARN: missing {len(missing)} role(s) vs amalgamation (will fall back to "
              f"hardcoded values): {', '.join(missing)}")

if __name__ == "__main__":
    main()

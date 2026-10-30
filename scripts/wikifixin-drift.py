#!/usr/bin/env python3
# PostToolUse(Write|Edit) stopgap for wiki drift. When a wikifixin lands under
# docs/wikifixins/, record its path to a pending-drift queue IN the wiki repo,
# so the fix is visible where wiki work happens and isn't stranded in nix-config.
#
# This is the detection half only. It does NOT edit the wiki, build, or deploy
# -- the deferred semantic pipeline that actually kills drift is specced in
# .memory/inbox (2026-10-29 wiki-drift-automation). Append-only, deduped, and
# it never fails the tool call (hooks must stay silent on error).
import json
import os
import sys

QUEUE = os.path.expanduser("~/CodeRepo/sites/blogs/wiki/.drift-pending")


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    path = (data.get("tool_input") or {}).get("file_path", "")
    if "/docs/wikifixins/" not in path or not path.endswith(".md"):
        return
    # The folder's own CLAUDE.md is meta (instructions), not a wiki fix.
    if os.path.basename(path) == "CLAUDE.md":
        return
    try:
        existing = open(QUEUE).read().splitlines() if os.path.exists(QUEUE) else []
        if path not in existing:
            with open(QUEUE, "a") as f:
                f.write(path + "\n")
    except Exception:
        pass


if __name__ == "__main__":
    main()

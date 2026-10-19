---
date: 2026-10-19
type: decision
---

# gd: Google Drive CLI over rclone

- Added `pkgs/gd/` (overlay `gd`, `termUi` in home/pkgs.nix, `checks.gd`). Verbs: push/pull/pick/find/cat/put/mv/rm/link, sync up|down (dry-run + confirm), bisync, mount.
- Persistence: `.config/rclone` (OAuth refresh token) and `.config/gd` → /persist. Synced folder `~/Storage/Drive` and sync-down backups `~/Storage/gd-backup` via session vars `GD_SYNC_LOCAL` / `GD_BACKUP_DIR`. rclone cache (bisync listings, VFS) follows XDG_CACHE_HOME into Storage.
- fuse deliberately not in runtimeInputs: a store fusermount3 would shadow the setuid wrapper.
- Not yet verified on volnix: `gd setup` OAuth, `gd mount`, and full-system eval (built/tested only standalone from a cloud session).
- Originally built inside thePanhandler by mistake; removed there.

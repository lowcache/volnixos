# Krita Troubleshooting Guide

Your Krita setup on NixOS (unstable/26.11) with Hyprland (Wayland) and a dual GPU configuration is experiencing crashes and canvas freezes when switching between multiple documents. 

Below is the diagnosis of the issues found and steps to verify and apply the fixes.

---

## 1. Issues Identified & Fixed

### 🔴 Path Mismatches (Fixed)
We inspected `/home/lowcache/Storage/krita-master/kritarc` (which is symlinked to `~/.config/kritarc` via Home Manager) and found multiple outdated paths from an old profile/restore (referencing `/home/nondeus` and `/home/ghost`).
* **ResourceDirectory** was pointing to `/home/nondeus/.local/share/krita`, preventing Krita from locating or correctly writing resources.
* **krita_resources** and **mask_set** pointed to `/home/ghost/`, which also does not exist on your system.

We have **successfully corrected these paths** inside your configuration file to reference `/home/lowcache/` instead.

### ⚠️ Qt6 / Wayland / Hyprland Canvas Conflicts
Krita `6.0.1` is a major upgrade running on **Qt6**. In a Wayland session (specifically Hyprland), Qt6 applications attempting to render canvas views natively on Wayland often experience drawing surface updates freezing or failing to switch (rendering the previous tab contents instead of the new one).

### ⚠️ Outdated Python Plugins
You have several third-party Python plugins in `~/.local/share/krita/pykrita/` (e.g., `quick_access_manager`, `krita-redesign`, `pigment_o`). These are Qt5-based and may hook into the canvas focus and tab events in ways that crash or hang the new Qt6-based Krita.

---

## 2. Recommended Diagnostics (Run in your terminal)

To verify the cause, please run the following test commands sequentially:

### Test A: Run Krita with a completely clean environment
Run this command to start Krita with clean settings and no loaded custom plugins or old configurations:
```bash
env XDG_CONFIG_HOME=/tmp/kritatest_config XDG_DATA_HOME=/tmp/kritatest_data krita
```
* **Steps:** Open two test images, try switching tabs, and check if it runs stably.
* **If this works:** The issue is specifically within your Krita configuration or the third-party Python plugins.

### Test B: Force Krita to run via XWayland (Highly Recommended)
Many Wayland-specific rendering bugs with Qt6 on Hyprland are bypassable by forcing Krita to use the X11 compatibility layer (XWayland) where rendering is more mature:
```bash
env QT_QPA_PLATFORM=xcb krita
```
* **Steps:** Open multiple files and switch tabs.
* **If this works:** Running under XWayland solves the Wayland canvas-refresh crash. You can make this permanent by editing your launcher/desktop entry (see below).

### Test C: Temporarily disable custom Python plugins
If Test A works but Test B still fails on your main profile, one of your custom plugins is likely breaking the Qt6 window cycle. You can temporarily disable them by renaming the plugins folder:
```bash
mv ~/Storage/krita-master/krita/pykrita ~/Storage/krita-master/krita/pykrita.bak
```
* Then start Krita normally (`krita`).
* If document switching works fine, you can restore them via `mv ~/Storage/krita-master/krita/pykrita.bak ~/Storage/krita-master/krita/pykrita` and enable/disable them one-by-one under Krita's **Settings > Configure Krita > Python Plugin Manager** to find the culprit.

---

## 3. How to Permanently Apply the XWayland Workaround

If **Test B** resolves the issue, you can configure NixOS / Home Manager to launch Krita with `QT_QPA_PLATFORM=xcb` automatically.

You can modify your desktop configuration or wrap Krita. Since you have a Home Manager setup, you can add a custom desktop entry or wrapper package in your Nix configuration, or copy the Krita desktop file to override it locally:

```bash
mkdir -p ~/.local/share/applications
cp /run/current-system/sw/share/applications/krita.desktop ~/.local/share/applications/
```
Then open `~/.local/share/applications/krita.desktop` and change the `Exec=` line to:
```ini
Exec=env QT_QPA_PLATFORM=xcb krita %f
```

---
type: state
project: Vol NixOS
last_updated: 2026-09-15
status: active
---

# System State Inventory (`memory/state.md`)

This file is the single source of truth for the active configuration, mapping, and hardware state of **Vol NixOS**.

---

## 1. System & Hardware Profile

* **Hostname:** `volnix` | **OS:** NixOS 26.11 (Zokor) | **Shell:** Fish (HM)
* **Current generation:** system-247 (`/nix/store/…-nixos-system-volnix-26.11.20260824.…`)
* **Desktop:** niri (Wayland, sole WM, default session) + Noctalia v5 (C++ shell)
* **Display:** Wayland native; XWayland via `xwayland-satellite` (`:0`, for xcb-only AppImages and Flatpak Qt5 apps; permanent startup pending).
* **GPU:** Hybrid AMD HawkPoint2 iGPU + NVIDIA RTX 4050 Mobile dGPU.
* **Audio (2026-08-25 — AUDIO MODULE BUILT, AWAITING SWITCH):** PipeWire 1.6.8 + WirePlumber 0.5.15 + ALSA/Pulse compat declared in `nixos/modules/audio.nix` (option-typed module following vol.* pattern). Module enables rtkit, configures Bluetooth codecs (LDAC, aptX-HD, aptX, AAC, SBC-XQ, SBC via libfdk-aac, libldacBT, libfreeaptx), and parks NVIDIA HDMI (`pci-0000_01_00.1`) and AMD HDMI (`pci-0000_66_00.1`) cards to `off` profile (keeps them off the main profile selection and out of default sink/source list). Auto-switch-to-headset-profile disabled (prevents browser tabs grabbing mic). Module verified in built closure: wireplumber-extra-config emits three drop-ins (50-bluez-codecs.conf, 51-bluez-policy.conf, 52-park-cards.conf) with correct properties. **Not yet live** — requires `make switch` + post-switch `systemctl --user restart wireplumber` to apply parked-card rules (removes stored pro-audio pins via `sed -i '/pci-0000_01_00.1/d; /pci-0000_66_00.1/d' ~/.local/state/wireplumber/default-profile`). Hardware fallbacks remain: Realtek ALC256 (card 2, `66:00.6`, analog stereo) as default sink; HDMI cards route via `pro-audio` for manual selection if needed.
* **Input Devices (2026-07-13):** Vial keyboard configured for unprivileged hidraw access via udev rule in `nixos/configuration.nix:services.udev.extraRules`. Rule matches serial `*vial:f64c2b3c*` with MODE=0660, GROUP=users, TAG+="uaccess". Pending rebuild application; activate via replug or `sudo udevadm control --reload && sudo udevadm trigger`.

---

## 2. Impermanence & Persistence Mappings

Ephemeral root (`tmpfs`, ~4 GB, wiped on boot). Permanent data on `/persist`.

**User dotfiles (`~/.nix-config/dots/`):** `niri`, `noctalia`, `quickshell`, `kitty`, `cava`, `fuzzel`, `wlogout`, `starship.toml`, `color-engine`.

**Persisted home directories (not repo-tracked):** `~/.codex`, `~/.gemini` (Gemini/Antigravity agent state; moved from `dots/gemini` to persisted real directory via home-manager impermanence 2026-07-24).

**Krita:** Native `~/.config/kritarc`, `~/.config/kritadisplayrc`, `~/.local/share/krita` → `~/Storage/krita-master/`. Pykrita plugins live at `~/Storage/krita-master/krita/pykrita/`. Swap location: `~/Storage/tmp/krita-swap` (persistent NVMe, 269 GB free; prevents SIGBUS crashes from mmap-based caching on impermanence tmpfs). Swap directory persistence LIVE in gen 247 via `home.activation.ensureScratchDirs` (see mistakes.md 2026-08-24, decisions.md #36).

**AI outputs:** `~/Pictures/fromAi/outputs` → `~/Storage/ai-generation/fooocus/outputs`.

**Imperative nix-env profiles (2026-07-27):** `~/.local/state/nix/profiles` persisted to `persist.nix` (canonical store where `nix-env -iA nixos.<pkg>` writes `profile-N-link` + `channels` generation + manifest). Compat symlink `~/.nix-profile → ~/.local/state/nix/profiles/profile` recreated declaratively via `home.file` with `force = true` at each activation. Caveat: `nix-env -iA nixos.*` requires the `nixos` channel; confirm `nix-channel --list` post-boot if installs can't resolve it. Rationale: decisions.md #30.

**Cache enforcement (active 2026-06-17):** `xdg.cacheHome = "$HOME/Storage/.cache"`; `TMPDIR`, `PIP_CACHE_DIR`, `CLAUDE_CODE_TMPDIR` → `~/Storage/tmp`. `.cache/llmfit`, `.cache/noctalia` persisted.

**Quarantined fonts (2026-06-21):** Corrupt font `NoracleNerdFont-Regular.otf` moved to `~/Storage/tmp/quarantined-fonts/`. `fc-cache -f` rebuilt.

**Flatpak data (persisted 2026-06-22):** `/var/lib/flatpak` and `~/.local/share/flatpak` persisted (`hardware-configuration.nix:91`, `persist.nix:110`). Flathub remote added; `org.gimp.GIMP` 3.2.4 installed. Host fonts (`~/.local/share/fonts`, 2772 files) mounted read-only into Flatpak sandboxes via `filesystems=host`.

**Phone-agent ingest (2026-08-06):** Staged files from phone arrive at `~/ingest/staged/` (managed by phone-ingest-sync.timer). Delivered files moved to `~/ingest/delivered/` after hash verification.

**Android tools (2026-08-21):** `~/Android` (Studio SDK, ~1.4 GB) and `~/.android` symlink to `~/Storage/`. `/var/lib/waydroid` bind-mounted from `/persist/var/lib/waydroid` (~2.4 GB). Both moved to avoid filling the 4 GB impermanence tmpfs root (mistakes.md #13).

**Waydroid userdata (2026-08-21):** `~/.local/share/waydroid` bind-mounted from `/persist/.local/share/waydroid` to persist app installs/data across reboots.

**Spotify config (2026-08-24 — LIVE, verified gen 247):** `~/.config/spotify` persistence via impermanence bind-mount (bounded 32 KB config, lives in `/persist`). Verified active via findmnt.

**Thunderbird profile (2026-08-25 — WIRED & VERIFIED, AWAITING FIRST LAUNCH):** Symlink target `~/Storage/thunderbird` wired via home-manager `home.file` mkOutOfStoreSymlink. Symlink chain verified: `~/.thunderbird → home-manager-files/.thunderbird → hm_thunderbird → /home/lowcache/Storage/thunderbird`. Target directory exists (4.0K, created 2026-08-24) but is empty — Thunderbird has not run since persistence was configured. First launch will populate `profiles.ini`, account setup, filters, and mail stores. Persistence correctly wired; email/profile data will persist across tmpfs-root wipe once initialized.

**Secrets (2026-06-09 rules, 2026-08-24 state):** Encrypted sops-nix credentials in `nixos/secrets.yaml`, persisted agent/tool state in `/persist`. `nixos/host-secrets.yaml` has uncommitted modifications (2026-08-24) tracking secret rotation state — commit before major branches.

---

## 3. MicroVM Guest Network (2026-08-06 — Confirmed Working)

* **net-gate (Tor relay, rebuilt 2026-09-12, bugs found 2026-09-15, rpfilter fix applied 2026-09-15):** Host `vm-netgate` → `192.168.100.1`; guest → `192.168.100.2`. Tor `9040`/DNS `5353`/SOCKS `9050`. Service was dead 2026-09-08 to 2026-09-12 (root cause: hand-rolled `settings.SOCKSPort` conflicted with auto-emitted `client.socksListenAddress` via list merge → tor died on second bind; netgate tap missing `IPMasquerade`, guest packets had no return route). Redesigned with fail-closed invariant and readiness ladder L0-L4 (decisions.md #42). **Status: LIVE in commit 665710c (activated 2026-09-12 16:11).** Bug sweep 2026-09-15 found 8 issues in the deployment; 7 fixed in-system with uncommitted changes (see mistakes.md 2026-09-15 entries). **New rpfilter finding (2026-09-15):** Enforced path was timing out despite SOCKS tests passing IsTor:true. Root cause: NixOS strict `networking.firewall.checkReversePath` (default) with `-m rpfilter --validmark` in mangle PREROUTING drops asymmetric enforced-path replies (source is public address; reverse route is WAN, not tap). Fix: declare `networking.firewall.checkReversePath = "loose"` inside `nixos/modules/anonymous-mode.nix` (now in working tree, not yet committed). Fix applied 2026-09-15 post-diagnosis; rpfilter strict/loose transition is independent of sysctl `net.ipv4.conf.*.rp_filter` (netfilter match is what bites, not sysctls). Full incident, redesign, 8-bug findings, and rpfilter root cause: mistakes.md 2026-09-08, 2026-09-15 entries, decisions.md #42 amendment. Testing not yet run (anon-check idle since 2026-09-12 05:15; L0-L4 ladder untested in live operation post-rpfilter fix). System rebooted 2026-09-15 14:26; cleared stale kernel state.

## 4. Active Workarounds

* **`make switch-detached` PATH Fix (2026-07-28 — FIXED):** Transient systemd units inherit minimal PATH (no `git`), breaking lix's flake fetcher. Fix: Makefile target passes `--setenv=PATH=/run/current-system/sw/bin:/run/wrappers/bin` to `systemd-run`. Verified 2026-07-28.

* **Krita G'MIC Plugin Crash — FIXED & VERIFIED (2026-07-14):** Patched via `overrides/gmic-qt-filtersview-nullptr-contextmenu.patch`; applied through `krita-plugin-gmic-patched` in `home/pkgs.nix`, bundled into `krita-wrapped`. Full root-cause narrative: decisions.md #21.

* **Ollama Pinned to 0.31.1 (2026-07-28):** `nixos/overlays/ollama.nix` pins `ollama-cuda` to pre-update nixpkgs rev `d407951`. Upstream 0.32.3 fails to build (CUDA Toolkit not found via setup-cuda-hook). Revert condition: retry 0.32.x+ on next flake update.

* **Flake-Update Overlays Active (2026-07-28):** `nixos/overlays/pandas-stubs.nix` (pytest 9.1.1 promotes a warning to a hard error under `filterwarnings=error`; overlay sets `PYTEST_ADDOPTS="-W ignore::pytest.PytestRemovedIn10Warning"`) and `nixos/overlays/niri.nix` (pins `libdisplay-info` to 0.3.0; niri 26.04's vendored `libdisplay-info-sys` caps at `<0.4.0`, nixpkgs bumped past it). Both cache-hit, no rebuild cost. Revert conditions documented in each overlay header; full incident detail archived (see archive_entries).

* **XWayland Satellite (2026-06-23):** `xwayland-satellite :0` running for Flatpak Qt5 apps and xcb-only AppImages (e.g. FireAlpaca). Manual-start only — permanent `spawn-at-startup` wiring still open (todo.md).

* **Portal AccessDenied — FIXED (2026-06-17):** `services.dbus.implementation = lib.mkForce "dbus";` (xdg-portal 1.20.4 pidfd bug). Full root cause: mistakes.md #10.

* **XDG FileChooser Portal Routing (2026-06-19):** Gnome backend advertises `FileChooser` but doesn't implement it; `xdg.configFile` routes `org.freedesktop.impl.portal.FileChooser=gtk` (durable, declarative).

* **Ollama VRAM/RTD3 (2026-06-17):** `OLLAMA_KEEP_ALIVE=5m`, `OLLAMA_KV_CACHE_TYPE=q8_0`, `OLLAMA_MAX_LOADED_MODELS=1`.

* **Playwright MCP (2026-06-15):** `scripts/playwright-mcp-nix` pins nix chromium.

* **TMPDIR split (2026-06-17):** User → `~/Storage/tmp`; daemon → `/nix/tmp`; Makefile `REBUILD_TMPDIR := $(HOME)/Storage/tmp`. Rationale: decisions.md #13.

* **Build fallback (2026-06-24):** Makefile `switch` carries `--option fallback true` — substituter `attic.xuyh0120.win/lantian` 307-redirects NAR fetches to a host with an expired TLS cert; fallback compiles from source instead of halting the build. Revert condition: once upstream cert is renewed, remove the flag (or migrate to permanent `nix.settings.fallback = true`).

* **statix lint failure (2026-08-24):** `nix flake check` fails at statix lint gate on `flake.nix:177-178` (assignment vs inherit). Trivial fixup (low priority). Host and droid targets evaluate clean; only the lint gate blocks `make check`.

---

## 5. Phone-Agent File Transfer (2026-08-06 — Confirmed Working, Pull-Only by Design)

**Mechanics:** Phone stages a file (Termux hooks or manual placement) → `phone-ingest-sync.timer` (every 2 min) → `phone-agent phone.ingest.fetch` pulls it → lands in `~/ingest/staged/`, sha256-verified, moved to `~/ingest/delivered/`.

**Manual triggers:** `systemctl --user start phone-ingest-sync.service` (immediate pull); `phone-agent phone.ingest.list '{"limit":50}'` / `phone-agent phone.ingest.fetch '{"name":"file.pdf","delete_after":true}'` (hand-invoke; caller must decode base64 + verify sha256 itself).

**Limitation:** All 34 phone-agent tools are phone→laptop only. Laptop→phone needs `phone.system.termux_exec`/`rish` to have the phone `curl` from the host — requires a DNAT entry (`nixos/vms.nix:225`) plus a host HTTP server. Not implemented. Tailscale Taildrop is likewise phone→laptop only; the web UI has no file-transfer surface.

---

## 6. Nix-on-Droid — Aarch64 Android Target (Generation 5 Live, Verified 2026-08-03)

**Architecture:** `nixOnDroidConfigurations.default` in the volnixos flake (one `flake.lock`); portable `home/common/` HM layer shared with desktop. `nixpkgs-droid`/`home-manager-droid` pinned to `nixos-25.11` (glibc 2.40) — desktop stays on unstable (glibc 2.42). Full root-cause narrative for the glibc 2.42 TCGETS2 regression and the proot `_defaultUnpack` chmod bug: decisions.md #31, #32.

**Live state (verified 2026-08-03):** rtk 0.44.0, mcp-gateway 3.3.2, opencode 1.1.14, claude 2.1.140, codex 0.92.0 — all glibc-2.40-224, zero glibc-2.42 in the runtime closure. `tty` returns `/dev/pts/0`; claude-code's full Ink/React TUI renders correctly on-device (the linchpin test). Phone is daily-usable.

**Nerd Font fix:** `droid/default.nix` sets `terminal.font` to JetBrainsMono Nerd Font, installed as `~/.termux/font.ttf` on activation.

**Host-specific layers:** volnix keeps `home/shell.nix` + `home/pkgs.nix` (nixos-unstable). droid has `droid/home.nix` + `droid/agents.nix` + `droid/backports.nix` (rtk, mcp-gateway, `prootUnpack` override; nixos-25.11).

**Makefile targets:** `make droid-check` / `droid-plan` / `droid-switch`.

**Still open:** android-integration wiring choice (disabledModules patched copy vs. minimal `xdg-open` shim); whether tether needs `antigravity-cli` or gemini-cli 0.25.2 suffices on droid. See todo.md.

---

## 7. Niri Compositor + Noctalia v5 — PRIMARY DESKTOP

**Status:** niri + Noctalia v5 are the sole desktop (Hyprland + ii/quickshell fully removed, commit ee2efb4). 191 keybinds, `center-focused-column "on-overflow"`, `#B4FF00` focus-ring, starship `force=true`, compositor-aware Krita.

**Noctalia v5 plugin API (locked, verified against source rev 623210223c):** `[[panel]]` entry kind + full `ui.*` control exposure (input/scroll/select/slider/toggle) shipped upstream 2026-06-25; our fork branch is superseded/archived (decisions.md #23). IPC: `noctalia msg plugin <id> all <event> [payload]`; bar widget table is `barWidget.*`; theme commands are `color-scheme-set <source> <name>`; `runInTerminal(cmd)` takes one string via `/bin/sh -c`.

**Workspace navigation (2026-06-20):** `Mod+Shift+Page_Up/Down` and `Ctrl+Mod+Shift+Left/Right` move focused column to adjacent workspaces.

**Quake terminal (2026-06-25, live):** `kitten quick-access-terminal` (wlr-layer-shell singleton) — niri only spawns the script, kitty owns window/geometry via remote control on `unix:/run/user/1001/kitty-quake`. Keybinds: `Mod+Return` toggle, `Mod+Shift+Return` position, `Mod+Alt+Return` height, `Mod+Ctrl+Return` aspect (`dots/niri/config.kdl:136-139`). Focus policy `on-demand` (not `exclusive`, which blocked compositor keybinds). Cold-start socket bug fixed (`sock()` helper now ends `|| true` under `set -euo pipefail`). Architecture rationale: decisions.md #16. Gotchas: kitty conf has no trailing `#` comments; orphaned `.kitty-wrapped` processes hold the abstract socket (kill by pid). Full narrative archived (see archive_entries).

**Bar — dual wrap-around L-frame (2026-06-22, live, NOT yet committed to git — user-deferred):** Top bar (full width) + left bar (full height) join at top-left corner via `reserve_space = true` on both, squared seam corners, rounded outer corners. Ayu Green palette (`#AAD94C` lime primary, `#E6B450` gold secondary) unified across bar/kitty/starship via `dots/color-engine/apply_theme.py`. Backup: `~/.local/state/noctalia/settings.toml.bak.20260622-112626`. Next: capture to `dots/noctalia/config.toml` and commit (deferred, see todo.md). Full technical-constraints narrative archived (see archive_entries).

**Claude Code Companion Plugin (2026-06-26, V1 live):** `~/.local/share/noctalia/plugins/claude` → `~/CodeRepo/claude-companion/noctalia-claude-plugin/` (own repo, `github.com/lowcache/noctalia-claude-plugin`). Pulse widget (`bell-ringing` glyph, top bar center) driven by Claude session hooks (SessionStart/UserPromptSubmit/PreToolUse/PostToolUse/Notification/Stop, merged into `~/.claude/settings.json`). MCP shim registered at `~/.nix-config/.mcp.json` (stdio): `get_window`, `get_workspace`, `get_media`, `get_shell_state`, `notify`, `set_theme_mode`, `set_color_scheme`, `remember`. Launcher `/cc` runs one-shot `claude` invocations via `runInTerminal`. Design philosophy (shell as senses/actuators, not a chat-UI port): decisions.md #24. Full verification narrative archived (see archive_entries).

**Plugin token optimization (2026-06-25):** 14 of 18 installed Claude Code plugins disabled to cut per-turn system-prompt overhead; 4 enabled (`nix-dev`, `devenv`, `feature-dev`, `impeccable`). Reversible via `claude plugin enable <name>@<marketplace>`.

**Scratchpad plugin (2026-06-24, active):** Note-taking widget + launcher provider at `~/.local/share/noctalia/plugins/scratchpad/`, shares state via `noctalia.state` + `notes.json`.

**Shell Prompt Theming — Starship M3 Roles (2026-09-05 — LIVE, Verified):** Starship prompt uses Noctalia M3 color role names (`primary`, `secondary`, `tertiary`, `on_primary`, `on_surface`, `surface_container`, `error`, `outline`) instead of terminal ANSI ramp (color0-color15). M3 supplies 36 role-based definitions; ANSI ramp covers only 16, discarding 20 role definitions and limiting prompt fidelity to terminal color capabilities. Implementation: community template at `~/.local/state/noctalia/community-templates/starship-m3/template.toml` (symlinked via `home.file` on activation). Template renders M3 palette to `$XDG_CACHE_HOME/noctalia/noctalia-palette.toml`, post-hook (`apply.sh`) injects it into `dots/starship/starship.toml` between `# >>> NOCTALIA M3 PALETTE >>>` markers. `dots/starship/starship.toml` uses `palette = "m3"` and M3 role names only; zero terminal indices remain. **Verified (2026-09-05):** Round-tripped scheme changes (Rosewater → Sapphire → Rosewater) confirms prompt accent matches M3 primary (RGB exact). Benefits: terminal-agnostic (works over SSH, restricted shells, any emulator). **Cleanup:** Deleted `dots/noctalia/palettes/volnix.json` (custom-palette layer redundant; Noctalia owns M3 emission). Corrected `home/shell.nix:137` comment. **Outstanding:** `dots/color-engine/apply_theme.py` is dormant; potentially destructive if run (line 145 greedy regex consumes M3 palette block). Decision pending (decisions.md #38, todo.md).

## 8. Documentation Platform — Hugo + E25DX (2026-08-15, Live; SEO fix 2026-08-23)

* **Status:** Wiki migrated from MkDocs to Hugo (0.164.0) + E25DX theme (Hugo Module).
* **Repository:** Independent repo at `~/CodeRepo/blogs/wiki` (main pushed), published as `lowcache/volnixos-wiki`. No longer symlinked into `.nix-config`.
* **Build:** `build.sh` (shared by `make build` and Workers Builds); pagefind post-build (`npx -y pagefind@1` fallback for Workers image).
* **Deployment:** Workers Builds integration pending (dashboard: set Build command `./build.sh`, build var `HUGO_VERSION=0.164.0`). Current deploys via `make deploy` (direct wrangler).
* **Theme gotchas (load-bearing — do not omit):**
  1. `[[module.imports]]` requires `ignoreConfig = true` (theme's `hugo.yaml` defines `theme: E25DX`; Hugo merges and fails without the ignore flag).
  2. Section pages need `layout: single` in front matter (no section template; omitting renders nothing).
  3. Sidebar navigation driven by presence flag `data/en/<section>/sidebar.yaml` (contents ignored; removal omits sidebar).
  4. Mermaid requires custom renderer at `layouts/_markup/render-codeblock-mermaid.html` (theme ships no third-party JS).
  5. Goldmark does not render markdown inside `<div markdown>` — rewrite as HTML.
  6. **`layouts/robots.txt` blocks non-Google crawlers by default (found 2026-08-23).** Theme template emits `Allow: /` for Googlebot/YandexBot/baiduspider/Applebot only, then a `User-agent: *` group with a per-page `Disallow:` for every page plus a trailing `Disallow: /`. bingbot and DuckDuckBot fell into the `*` group and were fully blocked. Fixed via a local `layouts/robots.txt` override (flat `Allow: /` for `*`, explicit `Sitemap:` line); committed, deployed, verified live (`Disallow` count for the `*` group: 31 → 0). Source: `$GOMODCACHE/github.com/dumindu/E25DX@.../layouts/robots.txt`. Mistake logged: see mistakes.md.
* **GSC deindexing incident (2026-08-16/17 → monitoring through ~2026-08-30):** `infernalcode.com` (Domain property, covers `wiki.infernalcode.com`) showed a spike from ~5 to 40 pages in "Crawled – currently not indexed" beginning ~2026-08-17, within 48h of the MkDocs→Hugo port. Google's own URL Inspection reported crawl allowed, fetch successful, indexing allowed, canonical clean — no technical fault found; content grew ~39% in the port and exactly one URL moved. [UNVERIFIED] causal mechanism — correlation with the port is the only evidence. Wiki sitemap had **never been submitted** in GSC — submitted 2026-08-23, 30/30 discovered same day. Blog sitemap (stale since 2026-08-02 at 39 URLs) refreshed to 50. GSC account note: the property lives under `lowcache.dev@gmail.com` (GSC user `/u/5/`), not the Chrome default-active `drawpdeadredd@gmail.com` — check the active account first if GSC appears empty.
* **Outstanding:** Workers Builds CI wiring, home page data-driven conversion, visual overhaul (palette port + centring), GSC Page Indexing recovery check (~2026-08-30, see todo.md).

---

## 9. Application Status

**Krita 6.0.2.1 + Font Gallery pykrita Plugin (SVG Text Engine, Native Shapes, 2026-08-24):** Native Krita (Nix build; Flatpak uninstalled 2026-06-22) with Font Gallery pykrita plugin providing a 3966-font browser UI. Krita 6.0.1 crashed on SVG text insertion (FreeType glyph rendering bug, upstream fix 2026-05-27); 6.0.2.1 (current nixpkgs version) fixed this — SVG `<text>` shapes now render correctly and are fully editable vectors. Full technical narrative: decisions.md #21. Font Gallery plugin refactored (2026-08-24) to insert native editable SVG text shapes via `createVectorLayer() + addShapesFromSvg()`, replacing the rasterize-to-paint-layer workaround (obsolete post-6.0.2). Plugin tested end-to-end in isolated harness; XML escaping and multi-line layout verified correct. Caveat: `Shape.remove()` in the Python API SEGVs on 6.0.2.1 (separate defect); avoid in plugins. Swap file location: `~/Storage/tmp/krita-swap` (persistent NVMe, 269 GB free; prevents SIGBUS crashes from mmap-based caching on impermanence tmpfs). Swap directory persistence LIVE in gen 247 via `home.activation.ensureScratchDirs` (see mistakes.md 2026-08-24, decisions.md #36). Testing harness at `<scratchpad>/ktest/` available for headless verification. G'MIC plugin patched and bundled (`overrides/gmic-qt-filtersview-nullptr-contextmenu.patch`). Fallback: GIMP 3.2.4 (Flatpak) or 3.0.8 native. Interactive on-canvas text tool (GUI) remains unverified.

**Color Scheme — Ayu Green:** Live and synced across Noctalia bar, kitty, starship. Theme file `dots/color-engine/themes/ayu_green.json` (35 tokens, 77 roles). Palette: lime `#AAD94C`, gold `#E6B450`, cyan `#39BAE6`, navy base `#1F2430`.

**Cargo-installed tools:** `lonkero` 3.5.0 (2026-07-31) via `cargo install`, linked against `/run/current-system/sw/share/nix-ld/lib` (openssl) per `programs.nix-ld.libraries`; required clearing a stale fish universal var `OPENSSL_DIR` (mistakes.md #12).

**J-Space skill (2026-08-19, trial active):** Claude Code skill for workspace reasoning; locally patched for CLAUDE.md precedence + configurable `LEDGER_DIR`. Backups: `SKILL.md.bak.pre-houserules`, `scripts/jspace.py.bak.pre-houserules` in `~/.claude/skills/j-space/`. Discontinue if problems arise (user: trial run).

**Waydroid — Android container (2026-08-21, fully operational, GAPPS):** Session + container RUNNING, DHCP lease obtained, GAPPS images (system 2462.4M, vendor 535.5M). Persistence: `/var/lib/waydroid` and `~/.local/share/waydroid` both bind-mounted from `/persist`; `~/.Android`/`~/.android` symlinked to `~/Storage/`. tmpfs root stable at 3% (down from 100% before persistence — mistakes.md #13). Device registered for Play Store certification at google.com/android/uncertified; propagation in progress. Plain `waydroid` package in use, not `waydroid-nftables` (removed 2026-08-21 — was shadowing the system package on PATH, mistakes.md 2026-08-21 entry). **Structural ceiling:** hardware-backed (STRONG-tier) attestation apps (payment, banking, anti-cheat) cannot run under Waydroid — no TEE in a Linux container; not fixable (decisions.md #34). Full setup narrative archived (see archive_entries).

---

## 10. MCP Gateway Backends and Remote Services (2026-08-24)

* **Status:** 11 backends live, 109 tools total. Gateway auto-loads backend configs from `~/.config/mcp-gateway/gateway.yaml` at startup; backends are read once per gateway launch.
* **Backend list (2026-08-24):**
  - **Cloudflare:** cloudflare-builds (6 tools, OAuth to your Builds dashboard), cloudflare-docs (2 tools, static)
  - **External APIs:** gsc (Google Search Console, 8 tools, service-account auth verified 2026-08-24), github (44 tools, PAT auth), context7 (2 tools)
  - **Content tools:** markitdown (1 tool, local), open-websearch (6 tools, free Brave API)
  - **Utilities:** filesystem (14 tools, local), noctalia MCP shim (8 tools, stdio, not via gateway)
  - **Playwright:** browser automation (23 tools via managed service, requires auth)
  
* **GSC Integration (2026-08-24 — Live and Verified):**
  - Service account: `cache-poor-blogs@dogwood-envoy-506516-e3.iam.gserviceaccount.com`
  - Properties connected: `sc-domain:infernalcode.com` (siteFullUser), `sc-domain:hotelevangelism.blog` (siteFullUser)
  - Tools available: `list_sites`, `search_analytics`, `index_inspect`, `list_sitemaps`, `get_sitemaps_report`, `list_crawl_issues`, `get_crawl_issue_report`, `detect_quick_wins`
  - Verification complete: `list_sites` returns both properties, `search_analytics` queries return real data, `index_inspect` confirms pages indexed and crawled
  - **Important:** Search analytics data in memory is NOT maintained — it stales rapidly. Use `gsc/search_analytics` at query time for fresh data. Refresh as needed; do not restate cached measurements. Benchmark: infernalcode.com 868 impressions / 5 clicks (2026-07-25 to 2026-08-21, all from wiki), hotelevangelism.blog 5 impressions / 0 clicks (indexed 2026-08-19, page 2 position 2).
  - **Opportunity identified:** infernalcode.com `/desktop/noctalia/` has 701 impressions at position 9.29 with 0.43% CTR (should be ~1.5-2.5% at that position). Title/meta-description rewrite could yield 3-4× more clicks without ranking change.

* **Hot-reload behavior:** Gateway does not hot-reload backend configs (SIGHUP has no effect; confirmed via prior Sentry dashboard offline during config test). Restart required: `systemctl --user restart mcp-gateway`.

* **Outstanding security item:** GitHub PAT in `~/.config/systemd/user/mcp-gateway.service` is plaintext (should move to sops secrets once gateway supports `sops-nix` credential injection — currently not implemented).
## 11. Flake Templates — Five Language Scaffolds

* **Location:** `.nix-config/templates/{ruby,hugo,python,go,lua,luau}`. Each is a complete project mold.
* **Contents per template:** flake.nix (with `checks` attrset for named gates), .envrc (direnv flake integration), .gitignore (project-scoped, not copied), README.md (template-specific guidance).
* **Usage:** `nix flake init -t ~/.nix-config#<language>` (must specify language; no `templates.default` by design, prevents silent mismatches).
* **Verification status (all live-tested on real consumers):** lua → drive-health `make unit` rc=0 (lua5.4 + LuaJIT tested); luau → claude-companion noctalia plugin (type-check verified, discovery-driven gates prevent false negatives); python → memd 255 pytest tests pass; hugo → wiki builds rc=0; go → produces working binary; ruby → bundlerEnv build succeeds.
* **Lua vs Luau (2026-09-06):** Separate templates for two Lua variants. `lua` (Lua 5.4/LuaJIT) = drive-health (33 `.lua` harnesses). `luau` (strict Lua) = community-plugins + plugin projects (337+ `.luau` files). Luau template uses discovery-driven gates to prevent undeclared-reference false negatives (decisions.md #40). Lua template uses list-based gates. Gotcha: `pkgs.luarocks` defaults to lua5.2; use `pkgs.${luaAttr}.pkgs.luarocks` to match your version.
* **Known gap:** luau-lsp for nvim/wezterm integration (user does not use these; discovery mechanism suffices for current consumers). Deferred, low priority.
* **Implementation constraint:** All template `.nix` files sit inside `${self}` and must pass this flake's nixfmt/statix/deadnix gates. Rules out lambda-based option lists (deadnix flags unused arguments); use attrset of strings instead.

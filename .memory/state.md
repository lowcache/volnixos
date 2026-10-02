---
type: state
project: Vol NixOS
last_updated: 2026-10-01
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
* **Audio (2026-09-24 — MODULE ACTIVATED, SPEAKER REGRESSION FIXED, HEADPHONE JACK-SENSE FAILING):** PipeWire 1.6.8 + WirePlumber 0.5.15 + ALSA/Pulse compat module `nixos/modules/audio.nix` activated via `make switch` (gen 247+). Codec mute bits were set at bootstrap (speaker pin 0x14 and headphone pin 0x21 both `Amp-Out vals: [0x80 0x80]`), causing all audio to be muted despite software volume controls at 100+%. Speaker mute bit cleared manually (`pactl set-sink-mute alsa_output.pci-0000_66_00.6.analog-stereo false`), sound restored. **Headphones detected by codec (hp_outs=1, node 0x21) but jack-sense reports "not available" — physical headphone insertion does not trigger detection.** Root cause under investigation (kernel driver, BIOS ACPI DSDT, or missing jack-detect kcontrol configuration). Audio module verified in closure; parked-card rules not yet applied (pending post-switch WirePlumber restart). Workaround: speaker output working; headphones troubleshooting deferred (todo.md).

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

## 3. MicroVMs — net-gate (Tor Relay) and anon-box (Workstation) (2026-08-06+)

### net-gate (Tor relay, rebuilt 2026-09-12, refined 2026-09-15, BOOT FAILURE 2026-09-16)

**net-gate (Tor relay, rebuilt 2026-09-12, refined 2026-09-15, RECOVERY 2026-09-16):** Host `vm-netgate` → `192.168.100.1`; guest → `192.168.100.2`. Tor `9040`/DNS `5353`/SOCKS `9050`. Service was dead 2026-09-08 to 2026-09-12 (root cause: hand-rolled `settings.SOCKSPort` conflicted with auto-emitted `client.socksListenAddress` via list merge → tor died on second bind; netgate tap missing `IPMasquerade`, guest packets had no return route). Redesigned with fail-closed invariant and readiness ladder L0-L4 (decisions.md #42). Built and checked 2026-09-12 16:11; seven implementation refinements + rpfilter fix applied 2026-09-15. System rebooted 2026-09-15 14:26. **TRANSIENT BOOT FAILURE 2026-09-16 04:49 resolved by 2026-09-16 15:29.** anon-selftest L4 ladder passed: enforced path verified with Tor exit 185.100.85.25, loopback resolver unreachable, IPv6 egress blocked. **Status: RECOVERY VERIFIED.** Full L0-L4 ladder confirmed functional in live operation.

### anon-box (Anonymity Workstation Microvm, Verified 2026-09-16)

* **Status:** Working end-to-end. Guest has no direct routing; all traffic flows through net-gate to Tor. **L4 selftest passed 2026-09-16 15:29 UTC:** enforced path verified through Tor (exit node 185.100.85.25 detected), loopback resolver confirmed unreachable, IPv6 egress blocked. Verified from inside guest: `uid=1000(anon)`, `IsTor:true` with exit distinct from host, `/in` read-only, `/out` writable, single default route only.
* **Design:** Cloud-hypervisor microvm with read-only `/in` (host filesystem bind), writable `/out`, single default route via tap to net-gate gateway. Accessed from host via `anon-shell` command over vsock. Firewall + routing isolation intact.
* **Platform constraints (load-bearing, discovered 2026-09-16):**
  - cloud-hypervisor rejects `type = "bridge"` interfaces; bridges formed host-side (networkd enslaves plain taps into `br-anon`, host holds NO address on bridge).
  - Vsock is hybrid protocol (Unix socket + CONNECT/OK handshake), not kernel AF_VSOCK. `socat VSOCK-CONNECT` and `systemd-ssh-proxy` incompatible. Socket is 0700 microvm (requires root access from host).
  - iptables REDIRECT targets arriving interface primary address; dual-leg gateway must have listeners bound to both legs (silent blackhole if secondary listener missing).
  - `microvm.storeOnDisk = true` by default unless guest shares host `/nix/store`; guest closures curated, guest learns nothing of host packages.
  - Microvm share mounts have no `readOnly` option; read-only inputs require host-side `bind,ro` mounts that are then shared into guest.
  - Unit deps on `microvm@anon-box` re-emit `restartIfChanged`, overriding template `X-RestartIfChanged=false`. Unlike net-gate, anon-box restarts on `make switch`.
* **Guest network:** Guest 192.168.102.2, gateway 192.168.102.1 (tap created by microvm). Single default route `0.0.0.0/0` via gateway. No loopback resolver (uses host's if configured).

## 4. Active Workarounds

* **XWayland Satellite (2026-06-23):** `xwayland-satellite :0` running for Flatpak Qt5 apps and xcb-only AppImages (e.g. FireAlpaca). Manual-start only — permanent `spawn-at-startup` wiring still open (todo.md).

* **Ollama Pinned to 0.31.1 (2026-07-28):** `nixos/overlays/ollama.nix` pins `ollama-cuda` to pre-update nixpkgs rev `d407951`. Upstream 0.32.3 fails to build (CUDA Toolkit not found via setup-cuda-hook). Revert condition: retry 0.32.x+ on next flake update.

* **Flake-Update Overlays Active (2026-07-28):** `nixos/overlays/pandas-stubs.nix` (pytest 9.1.1 promotes a warning to a hard error under `filterwarnings=error`; overlay sets `PYTEST_ADDOPTS="-W ignore::pytest.PytestRemovedIn10Warning"`) and `nixos/overlays/niri.nix` (pins `libdisplay-info` to 0.3.0; niri 26.04's vendored `libdisplay-info-sys` caps at `<0.4.0`, nixpkgs bumped past it). Both cache-hit, no rebuild cost. Revert conditions documented in each overlay header.

* **TMPDIR split (2026-06-17):** User → `~/Storage/tmp`; daemon → `/nix/tmp`; Makefile `REBUILD_TMPDIR := $(HOME)/Storage/tmp`. Rationale: decisions.md #13.

* **Build fallback (2026-06-24):** Makefile `switch` carries `--option fallback true` — substituter redirect fallback. Revert condition: once upstream cert renewed.

* **statix lint failure (2026-08-24):** `nix flake check` fails at statix lint gate on `flake.nix:177-178` (assignment vs inherit). Trivial fixup (low priority). Host and droid targets evaluate clean.

* **Nixpkgs lock pin (2026-09-18, temporary):** flake.lock pinned to f4a6f271 (2026-09-17, nixos-unstable-small) ahead of flake.nix ref. Reason: playwright 1.63.0 at channel rev b1b8759 requires libmanette-0.2.so.0; upstream fix (commit 67bf9043) postdates channel by 47 minutes. auto-patchelf fails without it, blocking playwright-mcp → home-manager-path → toplevel. Workaround duration: ~2 days until nixos-unstable advances. Rollback: `nix flake update nixpkgs` once 67bf9043 lands (see todo.md).

* **Noctalia × PipeWire Reconnect (2026-09-19):** After `make switch` restarts wireplumber/pipewire, Noctalia (v5.0.1) does not reconnect to the new PipeWire daemon. Audio widgets show stale state (muted/wrong volume, visualizer flat, new sinks invisible). Workaround: `kill $(pgrep -f noctalia-wrapped); niri msg action spawn -- noctalia` (Noctalia is a niri spawn-at-startup scope, not a systemd unit). Root cause: upstream noctalia-dev/noctalia#3396 (no reconnect code in `pipewire_service.cpp`; open). User plans pipewire-tethered auto-restart later (see todo.md).

## 7. Niri Compositor + Noctalia v5 — PRIMARY DESKTOP

**Status:** niri + Noctalia v5 are the sole desktop (Hyprland + ii/quickshell fully removed, commit ee2efb4). 191 keybinds, `center-focused-column "on-overflow"`, `#B4FF00` focus-ring, starship `force=true`, compositor-aware Krita.

**Noctalia v5 plugin API (locked, verified against source rev 623210223c):** `[[panel]]` entry kind + full `ui.*` control exposure (input/scroll/select/slider/toggle) shipped upstream 2026-06-25; our fork branch is superseded/archived (decisions.md #23). IPC: `noctalia msg plugin <id> all <event> [payload]`; bar widget table is `barWidget.*`; theme commands are `color-scheme-set <source> <name>`; `runInTerminal(cmd)` takes one string via `/bin/sh -c`.

**Workspace navigation (2026-06-20):** `Mod+Shift+Page_Up/Down` and `Ctrl+Mod+Shift+Left/Right` move focused column to adjacent workspaces.

**Quake terminal (2026-06-25, live):** `kitten quick-access-terminal` (wlr-layer-shell singleton) — niri only spawns the script, kitty owns window/geometry via remote control on `unix:/run/user/1001/kitty-quake`. Keybinds: `Mod+Return` toggle, `Mod+Shift+Return` position, `Mod+Alt+Return` height, `Mod+Ctrl+Return` aspect (`dots/niri/config.kdl:136-139`). Focus policy `on-demand` (not `exclusive`, which blocked compositor keybinds). Cold-start socket bug fixed (`sock()` helper now ends `|| true` under `set -euo pipefail`). Architecture rationale: decisions.md #16. Gotchas: kitty conf has no trailing `#` comments; orphaned `.kitty-wrapped` processes hold the abstract socket (kill by pid). Full narrative archived (see archive_entries).

**Bar — dual wrap-around L-frame (2026-06-22, live, NOT yet committed to git — user-deferred):** Top bar (full width) + left bar (full height) join at top-left corner via `reserve_space = true` on both, squared seam corners, rounded outer corners. Ayu Green palette (`#AAD94C` lime primary, `#E6B450` gold secondary) unified across bar/kitty/starship via `dots/color-engine/apply_theme.py`. Backup: `~/.local/state/noctalia/settings.toml.bak.20260622-112626`. Next: capture to `dots/noctalia/config.toml` and commit (deferred, see todo.md). Full technical-constraints narrative archived (see archive_entries).

**Claude Code Companion Plugin (2026-06-26, V1 live; path corrected 2026-10-02):** `~/.local/share/noctalia/plugins/claude` → `~/CodeRepo/noctalia-plugs/noctalia-claude-plugin/` (own repo, `github.com/lowcache/noctalia-claude-plugin`; confirmed 2026-10-02 — the previously recorded `~/CodeRepo/claude-companion/` path no longer exists on disk). Pulse widget (`bell-ringing` glyph, top bar center) driven by Claude session hooks (SessionStart/UserPromptSubmit/PreToolUse/PostToolUse/Notification/Stop, merged into `~/.claude/settings.json`). MCP shim registered at `~/.nix-config/.mcp.json` (stdio): `get_window`, `get_workspace`, `get_media`, `get_shell_state`, `notify`, `set_theme_mode`, `set_color_scheme`, `remember`. Launcher `/cc` runs one-shot `claude` invocations via `runInTerminal`. Design philosophy (shell as senses/actuators, not a chat-UI port): decisions.md #24. Full verification narrative archived (see archive_entries).

**Plugin token optimization (2026-06-25):** 14 of 18 installed Claude Code plugins disabled to cut per-turn system-prompt overhead; 4 enabled (`nix-dev`, `devenv`, `feature-dev`, `impeccable`). Reversible via `claude plugin enable <name>@<marketplace>`.

**Scratchpad plugin (2026-06-24, active):** Note-taking widget + launcher provider at `~/.local/share/noctalia/plugins/scratchpad/`, shares state via `noctalia.state` + `notes.json`.

**Shell Prompt Theming — Starship M3 Roles (2026-09-05 — LIVE, Verified):** Starship prompt uses Noctalia M3 color role names (`primary`, `secondary`, `tertiary`, `on_primary`, `on_surface`, `surface_container`, `error`, `outline`) instead of terminal ANSI ramp (color0-color15). M3 supplies 36 role-based definitions; ANSI ramp covers only 16, discarding 20 role definitions and limiting prompt fidelity to terminal color capabilities. Implementation: community template at `~/.local/state/noctalia/community-templates/starship-m3/template.toml` (symlinked via `home.file` on activation). Template renders M3 palette to `$XDG_CACHE_HOME/noctalia/noctalia-palette.toml`, post-hook (`apply.sh`) injects it into `dots/starship/starship.toml` between `# >>> NOCTALIA M3 PALETTE >>>` markers. `dots/starship/starship.toml` uses `palette = "m3"` and M3 role names only; zero terminal indices remain. **Verified (2026-09-05):** Round-tripped scheme changes (Rosewater → Sapphire → Rosewater) confirms prompt accent matches M3 primary (RGB exact). Benefits: terminal-agnostic (works over SSH, restricted shells, any emulator). **Cleanup:** Deleted `dots/noctalia/palettes/volnix.json` (custom-palette layer redundant; Noctalia owns M3 emission). Corrected `home/shell.nix:137` comment. **Outstanding:** `dots/color-engine/apply_theme.py` is dormant; potentially destructive if run (line 145 greedy regex consumes M3 palette block). Decision pending (decisions.md #38, todo.md).

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
## 12. Backup Hardware Status (External USB Drives)

**Seagate 2TB Backup Drive (`sda`, VID 0bc2, PID ac19):**
- **Capacity:** 2.00 TB (3907029167 × 512B)
- **Partitions:** sda1, sda2 (ext4 0dc8bbe7-…), sda3 (ext4 965cca42-…)
- **Mount point:** `/mnt/models/…` (restic repo + model mirrors)
- **Status:** Unrecovered read error on sector 3574956888 logged 2026-09-24 during `vol-backup.service` run. `restic check` passed (all 516 packs verified). Error near end of device; not attributed to specific file.
- **Diagnostics pending:** smartmontools not installed; SMART history unavailable.
- **Device quirks:** USB Mass Storage with `usb-storage.quirks=0bc2:ac19:u` in kernel cmdline.

**Health monitoring strategy:**
1. Install smartmontools to enable `smartctl` diagnostics.
2. On next device attach: `sudo smartctl -a -d sat /dev/sda` (read Reallocated_Sector_Ct, Current_Pending_Sector, Offline_Uncorrectable).
3. Run long self-test and trend SMART history across backup runs.
4. If pending/reallocated counts are non-zero and climbing, replace drive and re-seed restic repo.
5. Do NOT rely on `restic check` alone as a health indicator — it passed while medium was failing.

**Implications:** This is the backup target. Unreadable sectors on the medium holding the restic repo + model mirrors is a silent-restore-failure risk. One error is a candidate for reallocation, not necessarily dying drive, but must be monitored.
## 13. CI/Deployment Infrastructure

**Cachix CI Token (2026-09-28 Rotated):** GitHub Actions credential for pushing to public `volnixos` cache. Prior token (cache-scoped, created 2026-08-26) carried Cachix default 30-day expiry and expired 2026-09-25T10:11Z, causing CI build failures 2026-09-25/26 (runs 36094076894, 36231008195 failed with auth error at cachix-action step; 1m45s in). Token was cache-scoped (correct, safer than account-scoped), but 30-day expiry was unnecessarily aggressive. Replaced with new cache-scoped read/write token, 1-year expiry (expires ~2027-09-28). Token stored via GitHub secret `CACHIX_AUTH_TOKEN` using interactive `gh secret set` prompt (avoids trailing newline gotcha from piped echo). Documentation in `.github/workflows/build.yml:8` corrected to reflect cache-scoped nature (commit 3f2e952). Also fixed in same commit: stray double blank line in flake.nix that failed formatting gate after 1h39m CI burn (cost of discovering lint error late in build cycle). Gotcha: `cachix-action` accepts only `authToken` and `signingKey` — no OIDC/tokenless auth path available. Public cache `volnixos` requires write token for CI push; read-only substituter access is unrestricted.
## 14. Pending Activation — Audit Pass 2026-09-30

**Status:** Audit pass completed and built successfully (exit 0 from `nix build --no-link`), uncommitted in working tree, NOT yet activated via `make switch`.

**⚠️ PRE-SWITCH REQUIREMENT:** `.omo` directory persistence added to `home/persist.nix`. Before running `make switch`, manually run: `cp -r ~/.omo /persist/home/lowcache/` (creates bind-mount target). Omitting this step will leave ~/.omo on tmpfs and lose state across reboot.

**Fixes included (pending activation):**
- decapitate-fuse-mounts unit: moved from [Service] to proper script unit, wanted by shutdown.target, uid corrected (1000 → 1001)
- phone-proximity-daemon: moved from default.target to graphical-session.target (NIRI_SOCKET dependency)
- fish shell: removed extraneous spaces in command definitions
- sops gpg-key: corrected directive flag (was `-S`, now `-s`)
- phone-ingest-sync: validates filenames (rejects paths containing "/"), uses jq for ACK/fetch/delete JSON payloads
- phone-mcp-call.sh: constructs JSON payloads with jq (jq added to client PATH)
- anon-jail: seal check now covers IPv6 rules and return path validation
- anon-selftest: fixed printf statement formatting

**Hardening measures:**
- `users.mutableUsers = false`: immutable user database, prevents imperative user/group changes at runtime
- `/boot` umask 0077: owner-only, denies group/other read/write
- `~/Storage` mount: nosuid, nodev flags (prevents setuid binaries and device nodes on external storage)
- CI workflows: all external actions pinned by exact SHA (ci/cli, cachix-action, etc.)
- Container images: fooocus pinned by digest (reproducible pulls)
- Plugin repos: micro plugin repo pinned to specific commit

**Flake structural changes:**
- Removed unused NUR input and overlay (no current consumers)
- Consolidated nixpkgs inputs: nixos-hardware, impermanence, home-manager now follow primary nixpkgs (5 inputs → 4)
- nix-cachyos-kernel deliberately retains independent nixpkgs input (cachyos-specific revision)
- nix-ld: now uses `config.hardware.nvidia.package` instead of generic `linuxPackages.nvidia_x11` (respects nvidia module configuration)

**Configuration validation:** Username sweep across all host definitions (volnix.nix, vms.nix, windows-vm.nix, backup.nix, phone-agent) verified neutral by toplevel derivation hash comparison (all identical, confirming no functional config changes).

**Rejected changes:** Attempted removal of `nvidia-drm.modeset=1` from kernelParams failed — nvidia module does not add this parameter, so it cannot be removed. Reverted to keep present.

**Activation:** Run `make switch` to apply all changes to live system.

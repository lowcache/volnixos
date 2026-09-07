---
type: decisions
project: Vol NixOS
last_updated: 2026-09-07
status: active
---

# Architectural Decisions (`memory/decisions.md`)

This file catalogs the active, canonical design decisions and system configurations of **Vol NixOS**. AI agents must refer to this document before making any changes.

---

## 4. Krita Qt6 / Wayland Compatibility (Amended 2026-06-28)

* **Original decision (2026-06-06):** Force Krita to run under XWayland via `symlinkJoin` + `makeWrapper` injecting `QT_QPA_PLATFORM=xcb`. Reason: Krita 6 (Qt6) native Wayland causes canvas freezes on Hyprland with hybrid GPU.
* **Amendment (2026-06-17):** Testing showed native-Wayland Krita runs cleanly on niri — the crash is Hyprland-specific. Changed wrapper to compositor-aware (checks `$NIRI_SOCKET`): if set, `QT_QPA_PLATFORM=wayland` (niri); else `xcb`.
* **Final decision (2026-06-28):** Hyprland is removed; niri is the sole desktop. **Krita now unconditionally uses `QT_QPA_PLATFORM=wayland`** (native Wayland on niri). XWayland fallback wrapper is gone.

---

## 5. Secrets Location — sops or `/persist`, NEVER `dots/`

* **Decision (2026-06-09):** Secrets live in exactly two places: **sops-encrypted** (`nixos/secrets.yaml`, committable because encrypted) or **`/persist`** (never git-tracked). Never under `dots/`.
* **Reason:** `dots/` is symlinked into the **public** repo (`github.com/lowcache/volnixos`). Blanket-tracking `.gemini` leaked live OAuth tokens (see mistakes.md #8).
* **Pattern:** add to `nixos/secrets.yaml` → declare `sops.secrets.<name>` in `configuration.nix` → export in `home/shell.nix` `shellInit`.
* **Adding agent/tool dirs to `dots/`:** track only declarative config; gitignore runtime/state/credential files with dir-relative patterns; never rely on git to keep a secret out.

---

## 6. Autonomous Project Memory Curation (memd)

* **Decision (2026-06-10, updated 2026-06-12):** Adopt memd for autonomous distillation of project memory files. Deployed via `home/memd.nix`; integrated into Claude Code hooks and `agy` wrapper.
* **Model & Cost Trade-off:** Haiku by default (24/7 background); Sonnet for digests >15k chars. SessionStart injection is text-only.
* **Claude-agnostic hardening (2026-06-12):** `curator_cmd` config key makes the distill backend pluggable. Cursors advance only after successful apply — backlog survives backend swap.
* **Persistence:** `.config/memd/` and `.local/state/memd/` are persisted in `home/persist.nix`.
* **Scope & Constraints:** Manages only `.memory/`. Input: AI transcript backlog + inbox notes. Output: updated memory files + git commits (`.memory/` pathspec only).

---

## 7. Git Subtree for Independent Dotfiles History

* **Decision (2026-06-10):** Use `git subtree` to maintain independent, publishable history for `dots/` without a separate repository or breaking `mkOutOfStoreSymlink` mappings.
* **How it works:** Day-to-day work on main; `git subtree split --prefix=dots -b dots-history` generates a derived branch with `dots/` as repo root. `git subtree pull` merges from a published dotfiles remote.
* **Trade-off:** First split on large history is slow (caches with `--rejoin`); if publishing never needed, `git log -- dots/` suffices.

---

## 8. Scoped Memory for Dotfiles (per-app and directory-wide)

* **Decision (2026-06-10):** Place dotfiles-specific memory in `dots/.memory/` (not individual app folders), with optional per-app subdirectories.
* **Structure:** `dots/.memory/{state,decisions}.md`; optional `dots/.memory/quickshell/state.md`, etc.
* **Rationale:** `dots/` itself is not symlinked (only its children); placing `.memory/` there prevents leakage into `~/.config/`, avoids home-manager rebuilds, and keeps dotfile config from mixing with app runtime state.
* **Interaction with main `.memory/`:** Both apply when working in the dotfiles tree; repo-root `.memory/` is the global source of truth.

---

## 9. Agentic Delegation — Claude Code Delegates Scoped Tasks to Gemini Pro

* **Decision (2026-06-10, updated 2026-06-12):** Enable Claude Code to decompose work into scoped task briefs and delegate to Gemini Pro via `agy`. Gemini operates in worker mode (read-only on `.memory/`, no git operations, no system rebuilds); Claude remains orchestrator and final decision-maker.
* **Implementation:** `~/.local/bin/tether` → `~/CodeRepo/tether/` + protocol. Default workdir: `$PWD` when non-hidden; `~/.nix-config` paths auto-map to `~/volnix`.
* **Auto-Initiation Criteria:** Delegate on exploratory research, parallelizable fact-gathering, second opinions before expensive actions, bulk-mechanical work (e.g., docs drafting, cross-reference audits).
* **Rules Out:** Delegating architecture decisions, memory curation, system rebuilds, final user-facing answers, git pushes.

---

## 10. Global Agent Tooling — memd, tether, agent-scaffold Available in Every Project

* **Decision (2026-06-12):** Deploy `memd`, `tether`, and `agent-scaffold` as globally available tools, not scoped to this repo.
* **Implementation:** Declarative out-of-store symlinks in `~/.local/bin` via `home/scripts.nix` (`force = true`). Sweep timer keeps hermetic Nix-store copy of memd.
* **agent-scaffold:** `scripts/agent-scaffold/agent-scaffold` (fish) + `scripts/agent-scaffold/templates/MODEL.md`. At any git root: renders `.model/{CLAUDE,AGENTS,GEMINI}.md` (idempotent); calls `memd init` when `.memory/` missing. Trigger: Claude Code `SessionStart`; `agy` wrapper in `home/shell.nix`.
* **Rules Out:** Hand-creating `.memory/` scaffolding; editing generated `.model/` files to improve boilerplate (edit template instead); using a cd-hook for scaffold triggering.

---

## 11. Documentation Platform — PGS (Pico Pages) SSH-Native Static Hosting

* **Decision (2026-06-15):** Deploy documentation to PGS (pico.sh) using SSH-native static site hosting (`rsync` / `scp` deployment).
* **Why PGS:** Vendor-neutral; zero build-server dependency; deployment from any SSH-capable machine; version-controlled. MkDocs Material used for authoring. Final target is PGS.
* **SSH Registration:** Username `volnix` pre-registered on pico.sh with user SSH public key.
* **Deployment:** `mkdocs build` → `docs/site/`. Deploy via `rsync -avz docs/site/ volnix@pgs.sh:/docs/`.
* **Design:** Neutral charcoal canvas (`#101311`) + distinct green bands (header `#0b3019→#114a23`, tabs `#0e2716`).

---

## 12. Browser Package Recovery from Git History

* **Decision (2026-06-15):** Recover `brave` and `floorp` packages from git history following repo transfer. Both verified available (`brave` 1.88.138, `floorp-bin` 12.12.0). Integrated into `home/shell.nix` and `home/pkgs.nix`. Installed 2026-06-17.

---

## 13. TMPDIR Split — User vs. Daemon (2026-06-15)

* **Decision (2026-06-15):** Split temporary directory across two physically separate disks.
  * **User-side:** `TMPDIR=$HOME/Storage/tmp` in `home/shell.nix` (persistent NVMe, 469 GB).
  * **Daemon-side:** `/nix/tmp` (on the `/nix` partition, 195 GB, root-owned, nixbld-accessible).
  * **Makefile:** `REBUILD_TMPDIR := $(HOME)/Storage/tmp` in all privileged rebuild targets.
* **Why:** `make switch` failures with "broken pipe" were caused by 4 GB tmpfs `/` at 99% capacity (nix staged temp work on `/tmp` on the RAM tmpfs). Two-disk parallelism yields ~20% rebuild speedup.

---

## 15. Migrate to niri Compositor + Noctalia v5 — PRIMARY DESKTOP (2026-06-16, Completed 2026-06-28)

* **Original decision (2026-06-16):** Adopt niri as the primary compositor and Noctalia v5 (C++/Native Shell) as the desktop shell, replacing Hyprland + quickshell (ii). Implementation via secondary NixOS session (non-breaking; fallbacks remain live).
* **Status update (2026-06-28):** Hyprland + ii/quickshell **completely removed** (commits ee2efb4, 650fbde). **niri + Noctalia v5 are the sole desktop.** The "secondary session" framing is obsolete; niri is primary.
* **Why:** Noctalia v5 is compositor-agnostic and nix-integrated with M3 palette support. Gains: (1) C++ native escapes ~300 MB RAM/monitor QML tax; (2) niri (Rust, conservative) vs. Hyprland 0.55.3 (2 regressions); (3) static typing + compile-time feedback.
* **Fallback:** v4.7.7 pinned (unused; v5 is stable).

---

## 16. Quake Terminal Architecture for niri — kitten QAT + Remote Control

* **Decision (2026-06-18):** Use `kitten quick-access-terminal` (wlr-layer-shell singleton) for the quake terminal on niri. niri only spawns the shell script; kitty owns all window and geometry logic.
* **Mechanism:** Toggle via `kitten @ --to unix:<listen_sock> resize-os-window --action=toggle-visibility` (preserves geometry across cycles). Live geometry via `--action=os-panel --incremental edge=<edge> lines=<N>` (no toggle side-effect). State file `/run/user/1001/kitty-quake.state` tracks three orthogonal knobs: `pos` (top/bottom), `height` (normal/full), `aspect` (landscape/portrait). Config: `dots/kitty/quick-access-terminal.conf`. Script: `dots/niri/scripts/quake.sh`.
* **Keybind layout:** `Mod+Return` = toggle | `Mod+Shift+Return` = position (top↔bottom) | `Mod+Alt+Return` = height (normal↔full) | `Mod+Ctrl+Return` = aspect (landscape↔portrait).
* **Rules out:** niri workspace-based scratchpad (spawned multiple windows, index instability); re-invoking `kitten quick-access-terminal` for geometry changes (resets panel to conf defaults on re-show); `pkill -f quick-access-terminal` for cleanup (matches calling shell process, causes exit 144).
* **Rationale:** The wlr-layer-shell singleton + `kitten @` remote control is the only approach that (1) keeps niri as a pure launcher with no window-management role, (2) preserves geometry across toggle cycles, and (3) supports live geometry reconfiguration without a toggle side-effect.

---

## 17. Work-Routing Rule for Scoped Memory — Path-Prefix Based (Amended 2026-06-18)

* **Original decision (2026-06-18):** Attribute session work to scoped memory using a pure **filesystem path-prefix check** (no interpretation of file nature or purpose):
  * `<repo>/dots/**` → `dots/.memory/`
  * All else (nix code, location-locked root infra, root-level tools) → root `.memory/`
  * **Abstain on `<repo>/scripts/`** and meta-infrastructure (memd, tether, agent-scaffold) — these are transient workshop helpers whose final destination is unknown; route via explicit inbox notes only, decided case-by-case.

* **Amendment (2026-06-18):** Resolved the open question about memd's long-term destination: it graduates to its own repo in `~/CodeRepo` (Decision #18), making it a self-contained tool, not a root-scoped piece of machinery. This answers the "where does memd live?" question and unblocks Decision #19 (scripts/ ephemeralness).

* **Rationale:** `scripts/` is structurally transient (task-scoped helpers that graduate or die); root and dots are stable and auto-classifiable. Meta-tools (memd, tether, scaffold) are now *permanent* and require their own repos — at that point, the "transient scripts" category cleanly contains only helpers, and the routing rule becomes deterministic without guessing.

* **Implementation:** SessionEnd hook will perform path-prefix check for dots/root; explicit inbox for `scripts/` and graduating tools (decided case-by-case, but now the tools have a clear destination, so the decision is sharpened).

* **Blocked by:** Decision #18 (tool graduation must complete before scripts/ can be symlinked).

---

## 18. Tool Graduation — memd, tether, agent-scaffold → ~/CodeRepo (2026-06-18 — MEMD & TETHER COMPLETE, SCAFFOLD PENDING; MEMD PHASE 3 COMPLETE 2026-07-09)

## 18. Tool Graduation — memd, tether, agent-scaffold → ~/CodeRepo (2026-06-18 — ALL COMPLETE; MEMD PHASE 3 & SCAFFOLD COMPLETED 2026-09-06)

* **Decision:** Relocate `memd`, `tether`, and `agent-scaffold` from `.nix-config/scripts/` to independent git repositories under `~/CodeRepo/`, giving them logical independence and permanent organizational homes.

* **Why:** These tools are permanent, not transient workshops. They serve all projects, not just `.nix-config`. Keeping them in `scripts/` conflates them with task-scoped cruft and creates coupling in deployment (`home/scripts.nix` hardcodes their paths). Separate repos enable independent versioning, documentation, flake packaging, and removal from `.nix-config`'s concerns.

* **Keystone for:** Decision #19 (scripts/ symlink to ephemeral storage) and the work-routing hook (once tools have permanent homes, the routing rule is complete).

* **Status (2026-09-06 — ALL COMPLETE):**
  * **memd Phase 3 COMPLETE (2026-07-09):** Home-manager module integration live. Binary accessible via `which memd` → HM profile wrapper. Sweep timer active, `memd --version 0.2.0`. Verified: status, sync, hook integration working.
  * **tether COMPLETE (2026-06-27):** Graduated to `~/CodeRepo/tether` (standalone repo, `lowcache/clemini` remote). 2 commits pushed; symlinks retargeted. Live-tested.
  * **agent-scaffold COMPLETE (2026-09-06):** Rewritten and moved to `~/CodeRepo/agent-scaffold` (independent repo, `lowcache/agent-scaffold` remote). Independently versioned. Migration checklist applied: source copied, git history established, `.nix-config` references removed, standalone flake.nix in place.

* **Migration checklist (completed for all three):**
  1. ✓ Create new git repo in `~/CodeRepo/{memd,tether,agent-scaffold}` with README, flake.nix skeleton, tool self-registration.
  2. ✓ Copy source from `.nix-config/scripts/` → new repo; establish git history (initial commit).
  3. ✓ Rewrite `home/scripts.nix` or use HM modules: out-of-store symlinks point at `~/CodeRepo/` (Phase 2) or HM module integration (Phase 3).
  4. ✓ Update docs: replace hardcoded `scripts/` paths with `~/CodeRepo/` or HM module paths.
  5. ✓ Verify self-curation in new repos; verify tools work from new location.

* **Enabler:** This completes the prerequisite for Decision #19 (making scripts/ ephemeral via symlink to persistent scratch storage).

## 19. Make scripts/ Ephemeral — Symlink to ~/Storage/tmp/scripts (2026-06-18 — DEFERRED)

* **Decision:** Convert `.nix-config/scripts/` to a symlink pointing to `~/Storage/tmp/scripts` (persistent scratch storage, not tmpfs; lives outside git). Pair with `.gitignore scripts/` (no committed symlink, avoids dangling links on other checkouts).

* **Why:** `scripts/` is a structural workshop — task-scoped helpers that either graduate into the logic they serve (and vanish from the repo) or die as cruft. Making this *structurally* ephemeral (outside git, on external scratch) enforces the convention and prevents accumulation of dead helpers.

* **Routing rule payoff:** Enables the work-routing hook to ignore root-level symlinks (`result`, `scripts/`, etc.) without special-casing. The rule becomes: path-prefix classifies files; symlinks are transparently ignored.

* **Prerequisites:** Decision #18 must be complete (memd ✓, tether ✓; scaffold pending).

* **Implementation:**
  1. Create directory: `mkdir -p ~/Storage/tmp/scripts`.
  2. Symlink: `ln -s ~/Storage/tmp/scripts ~/.nix-config/scripts` (or, when current `scripts/` exists, `rm -rf scripts && ln -s`).
  3. Add to `.gitignore`: `scripts/` (ensure no dangling symlink is committed).
  4. Verify: `git status` shows only the ignore change; no `scripts/` entry.
  5. Test: Create a helper in `~/Storage/tmp/scripts/test.sh`; verify it's accessible as `./scripts/test.sh` and not git-tracked.

* **Blocked by:** Decision #18 (memd ✓ + tether ✓; scaffold pending).

---

## 20. Noctalia v5 Palette Emission Strategy — Neutral Foundation, Neon Accents (2026-06-18)

* **Decision:** Emit M3 palettes with true-neutral surfaces/outlines (grays/near-black) and chroma **only** in `mPrimary`, `mSecondary`, `mTertiary`, `mError` roles.

* **Why:** Noctalia v5 renders accents more aggressively than v4 (solid fills, gradients). A contaminated foundation (green-tinted neutral roles) stacks with this rendering to produce visual horror (green bloom, neon text, muddy panels). Noctalia's documented schema prescribes neutral roles for "secondary background," "hover highlights," "borders" — chroma-tainted neutrals break legibility and aesthetic.

* **Implementation:** `dots/color-engine/apply_theme.py` lines 286–292 desaturate `mSurface`, `mOnSurface`, `mSurfaceVariant`, `mOutline`, `mHover` toward true gray during emission from master theme. Keep reference palettes (Oxocarbon, etc.) as validation.

* **Rationale:** Matches known-good v5 palettes and enables the master theme's green neon to live only in the accents (mPrimary), not the foundation.

---

## 21. Native Krita 6.0.2.1 + Font Gallery pykrita Plugin (Amended 2026-08-24 — SVG Text Engine Fixed, Swap Hazard, Plugin Refactoring)

* **Original decision (2026-06-21):** Keep native Krita 6.0.1 with Font Gallery pykrita plugin as the text-tool font browser workaround.

* **Amendment 1 (2026-06-22):** SVG `<text>` shape insertion crashed Krita 6.0.1's glyph rasterizer (FreeType err=84 RenderGlyph). Workaround: rewrote `_insert_sample` to bypass Krita's text engine, using Qt `QPainter.drawText()` to render text onto a raster paint layer instead. Plugin adds user-text input + insert-size spinbox. Verified working.

* **Amendment 2 (2026-07-14):** G'MIC plugin crash fixed via `overrides/gmic-qt-filtersview-nullptr-contextmenu.patch` (null guards around `deleteLater()` calls). Bundled into `krita-wrapped`.

* **Amendment 3 (2026-08-24 — SVG Text Engine FIXED):** Testing confirms Krita 6.0.2.1 (current nixpkgs version, since 2026-08-16) does NOT exhibit the err=84 glyph crash. FreeType 0x54 = `FT_Err_Invalid_Stream_Read` — Krita 6.0.1 had a text-processing bug that triggered this; 6.0.2+ ships the fix (upstream 2026-05-27). **The rasterize-to-paint-layer workaround is now obsolete.** SVG `<text>` shapes render correctly and are genuinely editable vectors. Empirical verification: 5 font families, zero render errors, no crashes, PNGs visually confirmed.

* **Amendment 4 (2026-08-24 — Swap Hazard, Plugin Refactoring, Testing Harness):** `kritarc:291` `swaplocation=/tmp` with `maxSwapSize=10240` (10 GB mmap into 4 GB tmpfs root) caused SIGBUS crashes. Root cause: impermanence tmpfs cannot back 10 GB mmap page faults. Moved to `~/Storage/tmp/krita-swap` (NVMe, 269 GB free). Font Gallery plugin refactored (2026-08-24) to insert native SVG text shapes via `createVectorLayer() + addShapesFromSvg()`, replacing rasterize-to-paint-layer workaround (no longer necessary post-6.0.2 glyph fix). Plugin tested end-to-end; XML escaping and multi-line layout verified correct. Testing harness at `<scratchpad>/ktest/` (isolated XDG, Xvfb, reusable for future verification). Prevention: on impermanence hosts, configure any mmap-based caching to use persistent backing storage; do NOT rely on `$TMPDIR` mitigation for apps with custom temp paths (Krita ignores it).

* **Separate defect (2026-08-24):** `Shape.remove()` in the Python API SEGVs on 6.0.2.1 (crashes in `Document::document()`, not text-specific). Avoid in pykrita plugins. Unrelated to text rendering.

* **Why keep Krita 6:** Canvas superior for stylus/tablet (Weylus, native Wayland). G'MIC patch keeps filters usable.

* **Next step (user deferred):** Refactor Font Gallery plugin to use native SVG shapes (`doc.createVectorLayer() + addShapesFromSvg()`) instead of rasterize workaround (no longer necessary, but not yet implemented). Keep the 3966-font browser UI — that is the plugin's real value.

* **Installation (2026-08-24):** Only **Nix** `pkgs.krita` (6.0.2.1) with patched G'MIC plugin (Flatpak uninstalled 2026-06-22). SVG text now works; avoid `Shape.remove()` calls.

* **Fallback options (if ever needed):** GIMP 3.2.4 (Flatpak) or 3.0.8 native (Pango/fontconfig, proven at 2000+ fonts).

---

## 22. XWayland Satellite — Permanent niri X11 Bridge (2026-06-23)

* **Decision:** Make `xwayland-satellite :0` a permanent niri startup service to support (1) Flatpak Qt5 xcb-only apps and (2) xcb-only AppImages (e.g., FireAlpaca).
* **Why:** niri is pure Wayland with no built-in X11 support. AppImages often bundle only Qt's `xcb` plugin, and Flatpak Qt5 apps are similar. Without an X server, these apps fail to initialize the Qt platform plugin. xwayland-satellite provides X11 for these legacy apps without requiring a full-featured X session.
* **Implementation:** Add `spawn-at-startup "xwayland-satellite" ":0"` to `dots/niri/config.kdl`; then xcb-only apps can run with environment `DISPLAY=:0 QT_QPA_PLATFORM=xcb` (or by default if DISPLAY is set and no QT var conflicts).
* **Trade-off:** Small permanent overhead of one xwayland-satellite process; eliminates per-app workarounds and enables broad legacy-app support on niri.
* **Root cause (2026-06-23):** FireAlpaca 2.16.0 AppImage bundles only Qt's `xcb` plugin; global `QT_QPA_PLATFORM=wayland` tried to use the missing wayland plugin → "Could not find the Qt platform plugin". Manual test with `xwayland-satellite :0` + `DISPLAY=:0 QT_QPA_PLATFORM=xcb` succeeded; Qt initialized cleanly, app proceeded past plugin init.

---

## 23. Noctalia v5 Plugin Model — Upstream Shipped, Fork Superseded (2026-06-24)

* **Original decision (2026-06-23):** Expose `ui.input` and `ui.scroll` to plugins via a fork branch to enable text-input + scrollable controls in plugins.

* **Status update (2026-06-24, upstream shipped):** Upstream `noctalia-dev/noctalia` shipped `[[panel]]` entry kind + full `ui.*` control exposure (`ui.input`, `ui.scroll`, `ui.select`, `ui.slider`, `ui.toggle`) today (commit `918add87c` + follow-ups). Panels inherit `keyboardMode = OnDemand`, making text-input immediately typeable (solves keyboard interactivity problem entirely by using the correct surface).

* **Our fork work (superseded):** Fork branch `lowcache/noctalia:plugin-ui-input` exposed controls on `desktop_widget`. Architecturally inferior (not typeable without the keyboard routing work). Now redundant. No PR opened (correct — moot now).

* **Decision update:** Upstream resolved this completely and better. Pivot to designing NEW v5 plugins inspired by v4 (not ports) that leverage native panel + controls + bidirectional MCP integration. See decisions.md #24-26.

---

## 24. Claude Code × Noctalia v5 Plugin Philosophy — Native Design, Not Port (2026-06-24)

* **Decision:** Do NOT port the v4 claude-code-panel (ACP/QML). Instead, design NEW v5 plugins inspired by v4's functionality that take native advantage of v5's capabilities and architecture.

* **Why:** The v4 plugin reimplemented Claude's chat UI inside the shell (100+ KB of QML/JS) over ACP (bidirectional JSON-RPC). Porting it means fighting v5's medium (no stdin to processes → no true ACP), rebuilding a degraded copy (limited interactivity, mid-turn permission loss), and high effort for lower fidelity than the original.

* **The thesis:** Shell as Claude's **desktop senses and actuators**, not a chat client reimplementation. The shell is persistent, environment-aware, and can (via MCP) translate Claude's tool calls into environment actions (theme, wallpaper, notifications, app launch). The terminal remains the home for full-power agentic work (permissions, tools, mid-turn control).

* **Three-nerve foundation (IPC verified 2026-06-24):**
  - **Perceive:** MCP shim queries system directly (`niri msg`, `playerctl`, `/sys`); noctalia IPC used only for noctalia-internal state.
  - **Act:** `noctalia msg <target> <action>` request/response (verified working; action path proven).
  - **Pulse:** claude Stop-hook → `noctalia msg <plugin> attention` → plugin animates via `onFrameTick`. Animation confirmed working.

* **No C++ fork required:** The three nerves are fully served by Luau plugins + MCP shim + hooks. Frame-tick capability confirmed; plugin IPC is request/response (stdout reply). A future engine change (plugin `onIpc` *return* flows back as reply) would unlock queryable plugin services (nice-to-have, not v1), justified by real need.

* **Downstream plugin designs** (deferred to v1.1 or as expansion):
  - **Launcher `/cc <task>`:** `runInTerminal("claude --append-system-prompt '…' '<task>'"` — real TUI with full fidelity.
  - **Quick-ask panel:** One-shot `claude -p … --output-format stream-json` for read-only questions (no terminal).
  - **Status widget/bar:** Show session state, token burn, model, workspace info.
  - **Bidirectional MCP:** Teach Claude `noctalia msg` + shell controls via `--append-system-prompt`; Claude invokes shell tools mid-session (theme switch, notifications, focus windows).

* **Constraints honored:**
  - No stdin to processes (v5 API limit) — accounted for in design.
  - Plugins are isolated + time-budgeted — designs respect this.
  - Shell is ambient, not transactional — leverage for standing context, not chat emulation.

* **Rationale:** Matches v5's architecture (native capabilities, no fighting the medium). Adds value that v4 couldn't (bidirectional environment integration). Scales cleanly (MCP is standardized, Claude integrations are proven). Honest about limitations (terminal is the home for heavy work; shell degrades gracefully).

---

## 25. Three-Layer Memory Model — CLAUDE.md / Global memd / Project memd (2026-06-24)

* **Decision:** Maintain three distinct scopes of memory, each serving a different purpose and lifespan.
  - **`~/.claude/CLAUDE.md`** = hand-authored *policy* (how I behave). Static, authored once, kept durable. Governs Claude's operation across all projects.
  - **Global memd** (`~/.memory/`, system-scoped instance) = curator-maintained *learned facts* (what's true about the system, environment, user preferences). Dynamic, agent-fed. This is the missing middle that compounds over time.
  - **Project `.memory/`** = per-repo facts and context. Dynamic, curator-maintained, project-specific.

* **Why keep the file model (not database):**
  - Git history, diffability, human-readable form, curator ownership, inbox-protocol invariants, append-only `mistakes.md`, flock safety, and redaction filters all depend on markdown files.
  - Global memd is **low-volume** durable facts (not telemetry). Markdown handles low-volume perfectly; databases earn their keep at scale/query-complexity you'll never hit.
  - The **membrane holds**: ephemeral senses (focused window, dark mode, media playing) → `noctalia.state` (never memd); durable learnings → global memd. Conflating them is the failure mode.

* **Global memd implementation (memd enhancements):**
  - Add non-repo "global root" concept in `~/.config/memd/config.json` (memd currently auto-detects git repos; extend for system-scoped root).
  - Routing rule: project-specific facts → project `.memory/`; cross-project/system/user facts → global memd. Path-prefix check in the work-routing hook.
  - Minimal global schema to seed: `environment.md` (system state, hardware, network, services), `preferences.md` (user-established conventions, learned behaviors), existing `mistakes.md` + `todo.md`. Let the curator grow sectioning rather than over-designing now.

* **Sources for global truth:** Desktop agent's durable learnings written as inbox notes (user observations, system discoveries, preference deltas). The curator folds these into global memd over time, building a compounding system-understanding.

---

## 26. Backend Normalization & V1 Claude-Only with Open Seam for Future Models (2026-06-24)

* **Decision:** Ship v1 with claude as the sole backend, but normalize all agent invocation at a single choicepoint with an event vocabulary that enables future backend swaps (ollama, claude-router, other models) with zero call-site changes.

* **The choicepoint:** All agent work → `backend.invoke(prompt, opts)` / `backend.parse(line)` seam. v1 has one implementation (claude-code), but nothing calls `claude` directly — hardcoding the claude *parser* is fine; leaking `claude`-isms past the choicepoint breaks extensibility.

* **The load-bearing seam: event vocabulary.** Parser converts whatever the backend emits into a small internal vocabulary: `{ turn_start, text_delta, tool_start, tool_end, usage, needs_attention, turn_end, error }`. The **pulse state-language and transcript consume ONLY that vocabulary, never raw stream-json.** This is the key decision that makes future backends swap-transparent.

* **Config shape (not a registry):** `default_backend = "claude"` + one `backends.claude` block with trivial capability flags `{ agentic, tools, streaming, local }`. Don't build a registry, plugin-loader, or selector UI now — YAGNI. Adding ollama later = one config block + one parser function that emits the vocabulary. Zero call-site changes.

* **Privacy ceiling couples to model locality:** Remote/frontier backend → low/medium perception tier (workspace, dark mode, window class). Local backend (ollama) → high tier allowed (screen/clipboard/file context) because data never leaves the machine. The `local` flag gates it — wired in advance.

* **Rationale:** Leaves a cheap seam at an obvious extension point without building speculative machinery. Matches "necessity over redundancy" — build for current requirements, leave the door where we'll obviously walk through.

---

## 27. Debt Tracking via Ceiling-Markers — Code Annotation + Harvest Skill (2026-06-24)

* **Decision:** Mark intentional shortcuts/technical debt in code with a one-line `CEILING:` comment naming the limit and upgrade path. Harvest these markers periodically into durable memory (memd inbox notes) to prevent accumulation of invisible debt.

* **Code-side (always-on instruction):** Any `TODO`, `FIXME`, `HACK`, or acknowledged limitation gets a one-line `CEILING: <limit condition> | upgrade via <path>` annotation. Cost: one line per decision point. Constraint: must name the ceiling (what breaks if you don't upgrade) and the upgrade path (how to fix it). Motivates the decision-making, not just the deferral.

* **Harvest-side (on-demand skill):** A small skill (~15 LOC) runs `grep 'CEILING:'` across the repo, collects findings into a dated inbox note, writes to `.memory/inbox/`. The curator folds these into `todo.md` (or grows a `debt.md` section if volume warrants). No new store, no new machinery — memd already does the work.

* **When to harvest:** Manually via skill on demand (`/debt` or similar), or periodically (e.g., monthly sweep timer). Starting small, scale if needed.

* **Why this shape:** Prevents debt accumulation (the known failure mode of "we'll refactor later" that never happens). Keeps the record durable and durable in git history. Ties each debt to a specific condition (not vague), making future decisions about "is this worth fixing" concrete. Couples to memd, so debt becomes part of the system's learned facts, not floating in code comments.

* **Rationale:** Inspired by Mimocode-ponytail's debt ledger (`/debt`). Lightweight, integrated into existing memory discipline, grepable.

---

## 28. Vol NixOS as Portfolio, Not Distro (2026-06-28 — Decision Enacted)

* **Decision:** The config + wiki are published for **public ingestion as proof of concept, labor, ability, skill, and experience**—NOT as a turnkey install for others to use.

* **Why:** limbo (a "generic, portable" secondary profile) was an attempt to maintain both opinionated richness and reproducibility. These goals conflict: removing the exemplary parts to make it generic gutted its value. The config's true value is as a working exemplar, not a reusable abstraction.

* **Implication:** Removed `nixosConfigurations.limbo` entirely (commit 650fbde). volnix is the sole configuration. The repo is now unambiguously a personal system description, not a buildable template.

* **Documentation framing:** Updated README and docs/index from "reference — use limbo for reproducible builds" to **"portfolio — read it and borrow patterns"**. The wiki documents decisions, architectures, and solutions; readers consume it as exemplars, not build instructions.

* **What this clarifies:** Every custom decision (niri over i3, Noctalia over stock bar, aggressive impermanence, aggressive caching, cost trade-offs) is now published honestly as "this is what works for this machine and this person" — not as "the correct way to do things." The portfolio stance is more useful and more true.

---

## 29. Claude Code Status Line — Oxide Palette + Rate Limits Display (2026-07-07)

* **Decision:** Implement custom Claude Code status line that displays system context (time, model, branch, directory), Claude session state (context%, rate limits), and token burn, using `│` dividers and Oxide palette colors.

* **Why:** Provides at-a-glance visibility into (1) code repository state (branch + dirty), (2) Claude session constraints (context remaining, rate limit usage), (3) cost awareness (tokens burned this session). Dividers (`│`) are cleaner than powerline arrows on a uniformly-colored surface. Oxide palette maintains visual coherence with the broader system theme.

* **Design details:** Rendered as a single uniform bar on Oxide's `#2E2623` surface with muted dividers. Conditional coloring: context/rate/tokens use traffic-light (green/amber/red) to surface constraints approaching limits. Graceful degradation: missing `rate_limits` field omits those segments rather than rendering empty or erroring.

* **Rules out:** Powerline-style arrows (too visual hierarchy for status line); bright/saturated colors on surface (reduces signal); multi-line status (incompatible with status-line UI).

* **Version caveat:** Rate limit percentages require Claude Code version that emits `rate_limits` in the statusline JSON payload. Earlier versions show only time/model/branch/dir/tokens.

---

## 30. Imperative nix-env Profile Persistence — Persist Generation Store, Not Compat Symlink (2026-07-27)

* **Decision (2026-07-27):** When persisting imperative `nix-env -iA` installs across tmpfs-root wipe, persist the canonical **generation store** `~/.local/state/nix/profiles/`, not the non-canonical compat symlink `~/.nix-profile`.

* **Why:** `~/.nix-profile` is a symlink (`~/.nix-profile → ~/.local/state/nix/profiles/profile`) created and owned by nix. It is not canonical. Listing it under home-manager impermanence `directories` (a) treats the symlink as a directory and (b) tries to own a resource already owned by nix, causing activation conflicts. The real data (the `profile-N-link` generations, `channels` generation, manifest) live in `~/.local/state/nix/profiles/`, which existed on tmpfs and was wiped on boot.

* **Implementation:**
  - Remove `.nix-profile` from impermanence `directories` — you don't persist the symlink.
  - Add `.local/state/nix/profiles` to impermanence `local` directories — the canonical store where `nix-env -iA` writes generations and channels.
  - Recreate the compat symlink `~/.nix-profile → ~/.local/state/nix/profiles/profile` declaratively via `home.file` with `force = true` at each activation. This ensures `~/.nix-profile/bin` hits PATH immediately after boot without needing a prior nix command.
  - **Pre-switch:** Seed `/persist/…/.local/state/nix/profiles` with current generations (via `cp -a` preserving symlinks) so the first activation doesn't orphan existing profile.

* **Caveat:** `nix-env -iA nixos.*` requires the `nixos` channel to be present. Since the `channels` generation is now persisted alongside profiles, it should carry over post-boot — but verify `nix-channel --list` after reboot if an install ever can't resolve the channel.

* **Prevention rule (mistakes.md #11 analog):** Non-canonical symlinks cannot be persisted by impermanence as directories. Identify the canonical data (where the tool writes the actual state), persist that. Recreate compat symlinks declaratively if needed.

---

## 31. Nix-on-Droid Architecture — One Flake, Portable Home Manager Layer, Phone Agent MCP Unchanged (2026-08-02, Amended With glibc 2.42 Pin & proot Unpack Fix, Generation 5 Activated 2026-08-03)

* **Original decision:** Ship `nixOnDroidConfigurations.default` as a new output in the existing volnixos flake (not a separate flake). Extract a portable Home Manager layer (`home/common/`) shared by both volnix and droid; host-specific layers on top.

* **Amendment 1 (2026-08-02 — glibc 2.42 Root Cause & Fix):** The apparent "login-path hang" was caused by glibc 2.42's reimplementation of `isatty()`/`tcgetattr()` to use the `TCGETS2` ioctl (termios2 for arbitrary baud rates). Android's SELinux allowlist for `untrusted_app` permits `TCGETS` but not `TCGETS2`, so every glibc-2.42 binary on the phone receives `EACCES` and reports "not a terminal". Interactive shells then start in non-interactive mode with no prompt. **Fix: pin nix-on-droid's package set to `nixos-25.11` (glibc 2.40, pre-regression).** This avoids rebuilding the graph on the phone. Commit `5270d12` + `871c6d9`.

* **Amendment 2 (2026-08-03 — proot Unpack Bug & Backports):** Directory-source derivations failed with `cp: setting permissions for 'source': No such file or directory` during unpack. Root cause: nixpkgs' `_defaultUnpack` uses `cp -pr`; cp creates the destination then chmods it. Under proot (ptrace-based sandbox), chmod returns `ENOENT` even though the directory exists — proot denies ownership/mode operations on directories it creates. **Fix:** `droid/backports.nix` provides `prootUnpack` override: pre-create destination, copy *contents* with `cp -r --no-preserve=mode,ownership $src/. $dest/`, then `chmod -R u+w $dest`. Also fixes cargo's vendor hook by placing vendor tree in `postUnpack` and setting `cargoVendorDir = "vendor"` (required pairing — takes the no-copy branch). Verified: rtk 0.44.0, mcp-gateway 3.3.2, termux-am all build natively on phone; all link glibc-2.40-224 (zero glibc-2.42 in runtime closure). Commit `d4f2968`.

* **Amendment 3 (2026-08-03 — Generation 5 Verified Live):** claude-code's full Ink/React TUI verified rendering on phone terminal (critical test passed). opencode 1.1.14 added from nixos-25.11 (no backport needed). Phone now daily-usable; strategic decision to backport only essentials (rtk, mcp-gateway) rather than re-package llm-agents overlay (cache-key mismatch). Android-integration investigated; termux-am now builds but wiring decision deferred.

* **Why one flake, not separate:** One `flake.lock` means both systems evaluate against identical nixpkgs (lazy evaluation skips non-droid outputs, so volnix-only inputs like lanzaboote don't affect the phone). Simpler to understand, easier to maintain, avoids duplicate `flake.nix` boilerplate. nix-on-droid's own `nixpkgs` and `home-manager` inputs follow the primary ones via `follows = "nixpkgs"` and `follows = "home-manager"`. **Amended:** `nixpkgs-droid` pinned to `nixos-25.11` (glibc 2.40); `home-manager-droid` follows release-25.11.

* **Portable layer design (`home/common/`):** Platform-agnostic — fish shell (aliases, abbrs, functions, PATH assembly), git config, micro (syntax/tools), direnv, common CLI packages (ripgrep, fd, fzf, eza, jq, yq, coreutils, etc.). Extracted from prior volnix `home/shell.nix` and `home/pkgs.nix`; both hosts import it via `imports = [ ../home/common ]`. Works because `programs.fish.{shellInit,interactiveShellInit}` are `types.lines` (mergeable) and aliases/functions/packages are merging options (no host redefines a shared value). **Verified behavior-preserving refactor (2026-08-02):** Desktop package list (224 entries), aliases, functions, git settings, micro settings identical before/after. Same layer deployed to phone in generation 3 with zero changes.

* **Host-specific layers:**
  - **volnix** keeps `home/shell.nix` (niri/Noctalia integration, systemd units, sops-nix secrets), `home/pkgs.nix` (build toolchains node/go/pandoc, dev runners, ripgrep-all) — evaluates against nixos-unstable (glibc 2.42).
  - **droid** has `droid/home.nix` (nix-on-droid module configuration) + `droid/agents.nix` (claude-code/codex/opencode; 25.11-compatible) + `droid/backports.nix` (rtk, mcp-gateway, prootUnpack override) — evaluates against nixos-25.11 (glibc 2.40).

* **Phone-agent MCP unchanged:** nix-on-droid is not Termux. It is a separate Android package (`com.termux.nix`) with its own sandbox — not an authorized caller of Termux:API. Phone-agent MCP server stays in Termux and is accessed over the network (Tailscale loopback or local network) exactly as before. nix-on-droid provides the declarative dev environment **alongside** Termux, not replacing it.

* **Makefile targets:** `make droid-check` (evaluate HM layer), `make droid-plan` (dry-run closure size), `make droid-switch` (build and activate on phone via adb).

---

## 32. proot Unpack Override — Pre-Create Destination, Copy Contents, chmod (2026-08-03)

* **Decision:** When building derivations with directory sources on proot (nix-on-droid sandbox), override `_defaultUnpack` to sidestep proot's structural chmod denial.

* **Why:** nixpkgs' `_defaultUnpack` uses `cp -pr --reflink=auto` which creates the destination directory, then chmods it to preserve source mode. Under proot, the chmod call returns `ENOENT` even though the directory exists — proot denies ownership/mode operations on directories it creates, a **structural sandbox isolation rule**, not a permissions issue. The failure is **not** about `--preserve` flags; `cp -r --no-preserve=mode,ownership` fails identically because cp still applies a default mode to directories it creates, and proot still denies chmod.

* **Solution:** Pre-create the destination with `mkdir -p`, copy *contents* into it with `cp -r --no-preserve=mode,ownership $src/. $dest/`, then `chmod -R u+w $dest` to enable subsequent phases. This avoids letting cp create the destination and sidesteps proot's chmod restriction entirely.

* **Cargo pairing:** cargo's `cargoSetupPostUnpackHook` has a no-copy branch when `cargoVendorDir` is set. Place the vendor tree in `postUnpack` (which fires *before* `postUnpackHooks`) so cargo skips its broken `cp -Lr` entirely. Setting `cargoVendorDir = "vendor"` is **required**; the two mechanisms form a pair.

* **Implementation:** `droid/backports.nix` provides `prootUnpack` override implementing this logic. Apply to any directory-source derivation that would otherwise fail under proot with the `cp: setting permissions` error.

* **Prevention rule (for mistakes.md):** Do not retry `cp -pr` with `--no-preserve=*` flags; that treats the symptom. The root cause is proot's denial of chmod on directories it creates. The solution is structural: pre-create, copy contents, then chmod.

* **Verified on (2026-08-03):** rtk 0.44.0, mcp-gateway 3.3.2, termux-am — all build natively on phone.

---

## 33. Documentation Platform — Hugo + E25DX Theme (2026-08-15, Activated)

* **Decision:** Migrate wiki from MkDocs to Hugo (0.164.0) + E25DX theme. Host in separate independent repo (`lowcache/volnixos-wiki`) rather than symlinked into `.nix-config`.
* **Why:** Hugo + Module-based themes decouple docs toolchain from system config; E25DX provides modern Material-inspired design out-of-box. Separate repo allows independent versioning and cleaner build process.
* **Build shape:** `build.sh` is single source of truth; used by both `make build` and Workers Builds CI. Pagefind post-build for search.
* **Load-bearing gotchas (E25DX):** Five traps discovered during migration (see state.md §8); all cost real time but produce no build error. Documented to prevent future regressions.
* **Process note:** Conversion was scripted (27 pages, 47 admonitions→alerts, 3 tab blocks→shortcodes, .md links→pretty URLs); delegation would have been slower for deterministic text transformation.

---

## 34. Waydroid Hardware-Backed Attestation Ceiling — Payment Apps Unsupported (2026-08-21)

* **Decision:** Waydroid structurally cannot run apps requiring hardware-backed attestation (STRONG integrity tier). This is an unfixable architectural limit, not a configuration defect.

* **Why:** Payment apps (Cash App, Venmo, banking) and competitive-game anti-cheat use Android's TEE (Trusted Execution Environment) — a hardware cryptographic chip on the phone's SoC — to sign device-authenticity proofs that cannot be forged. Waydroid is a Linux container on a laptop with no TEE. Hardware attestation requires real cryptographic hardware; it cannot be spoofed or bypassed via software (unlike BASIC/DEVICE tier, which Magisk + PlayIntegrityFix defeat). The ceiling is structural.

* **Technical detail:** Android's Play Integrity API has tiers:
  - **BASIC / DEVICE integrity:** Software-level checks (artifact presence, qemu markers, root binaries). Defeatable via Magisk + PlayIntegrityFix modules.
  - **STRONG integrity:** Hardware-backed cryptographic attestation. Not defeatable. Requires a physical phone with a real TEE.

* **Scope of unsupported apps:** Payment processors, corporate security policies, competitive game anti-cheat. All require STRONG tier.

* **Realistic alternatives:**
  1. Physical Android phone for payment-app access.
  2. Web interfaces (cash.app browser version) for partial functionality.
  3. Waydroid remains useful for dev/test, ARM apps with libhoudini, and apps doing only software-level checks.

* **Why this decision matters:** Prevents future agents from attempting impossible workarounds (wasting time on increasingly-sophisticated Magisk modules). Couples to Decision #27 (ceiling markers) — this is a *structural* ceiling, not deferred debt. Honest scoping of what waydroid solves.

---

## 35. Phone-Agent — Standalone MCP Server, Not Fronted by mcp-gateway (2026-08-24)

* **Decision:** phone-agent is a standalone MCP server and is NOT fronted by the `mcp-gateway`. The `nixos/phone-agent/mcp-gateway.nix` module was removed (2026-08-24); it contained only invalid examples and unconditional warnings.

* **Why:** Two independent reasons: (1) **Incompatible.** The module's `gateway-peer.example.yaml` used outdated mcp-gateway 3.3.2 schema; auth test failed. (2) **Architectural.** phone-agent serves a dedicated purpose (phone-specific file transfer + system calls) and does not benefit from gateway multiplexing. Consistent with established exceptions: the **Noctalia MCP shim at `.model/.claude/.mcp.json` also bypasses the gateway**, proving not every MCP server goes through it.

* **Implementation:** phone-agent runs as standalone stdio server registered in `.model/.claude/.mcp.json` with `type: stdio`. No gateway intermediary.

---

## 36. Persistence Strategy — Impermanence Bind-Mount vs. Storage Symlink Split (2026-08-24)

* **Decision:** When persisting application state across tmpfs-root wipe, use a split strategy based on growth and lifecycle:
  - **Small, bounded config (<100 MB, well-defined):** impermanence bind-mount into `/persist` (Spotify `~/.config/spotify`, 32 KB).
  - **Large/unbounded data:** Storage symlink via `home.file` + `home.activation` pre-create (Thunderbird `~/.thunderbird`, mail stores + caches).
  - **Never mix both for the same path:** impermanence refuses symlink targets (causes shadowing/collision).

* **Why:** Bind-mounts are atomic, ideal for durable config. Symlinks are cheap, flexible for variable-size stores. Conflating them causes activation failures.

* **Prevention rule:** Estimate growth curve. Stable config → impermanence. Growing data → symlink. Pre-seed impermanence targets from live tmpfs before switch. Pre-create symlink targets via `home.activation.ensureScratchDirs`.

---

## 37. Audio Stack — Option-Typed Module, vol.audio Namespace (2026-08-25 — Built, Awaiting Activation)

* **Decision:** Implement the audio stack (PipeWire, ALSA, Pulse compat, WirePlumber, rtkit, Bluetooth codecs, parked-card rules) as a declarative option-typed module in `nixos/modules/audio.nix`, following the `vol.*` namespace pattern established by `ai-stack.nix`.

* **Module structure:** Options namespace `vol.audio` with switches for: (1) enable the full stack, (2) enable pulse client tools (pactl/pacmd), (3) list of ALSA device names to park as "off", (4) Bluetooth codec support (enable/disable), (5) codec priority list, (6) auto-switch-to-headset-profile policy.

* **Rationale:** Bluetooth codec and headset-switching policies are non-obvious and machine-specific. Declarative options allow future machines (or this one, when audio changes) to reconfigure codec priority or auto-switch behavior without code duplication or git-history churn. Parked-card rules solve the "HDMI audio buries two real outputs on the main profile" UX problem by explicitly silencing cards whose outputs are not in use.

* **Host-side configuration (nixos/hosts/volnix.nix):** `vol.audio = { enable = true; parkedCards = [ "alsa_card.pci-0000_01_00.1" "alsa_card.pci-0000_66_00.1" ]; }` (parked devices are NVIDIA HDMI and AMD HDMI; default Realtek ALC256 is not parked).

* **Implementation details:** Module uses `mkMerge` of four guarded blocks: the stack itself (services.pipewire, services.wireplumber, security.rtkit, hardware.pulseaudio), pulse client tools (environment.systemPackages), parked-card rules (wireplumber extraConfig), Bluetooth codec policy (wireplumber extraConfig). WirePlumber drop-ins are generated via `mapConfigToFiles` and collected into `wireplumber-extra-config` package.

* **Verified in closure (2026-08-25):** Built system contains all three drop-in configs (50-bluez-codecs.conf: codec list with libfdk-aac, libldacBT, libfreeaptx verified in closure; 51-bluez-policy.conf: `"bluetooth.autoswitch-to-headset-profile": false`; 52-park-cards.conf: monitor.alsa.rules entries for both devices). pactl and rtkit-daemon.service both present. Bluetooth main.conf includes `Enable=Source,Sink,Media,Socket` and `Experimental=true`.

* **Status:** Built in `/nix/store/zqlbavrgxnz93w8ahx8rxjg9rjiyw9mq-nixos-system-volnix-26.11.20260823.56c02bc`. **Not yet live** — requires `make switch` to activate, then post-switch WirePlumber restart to apply parked-card rules: `sed -i '/pci-0000_01_00.1/d; /pci-0000_66_00.1/d' ~/.local/state/wireplumber/default-profile && systemctl --user restart wireplumber`.

* **Why this design:** Mirrors the pattern of `vol.ai-stack` (options describe the feature, config block activates it). Keeps audio configuration in one place (`nixos/modules/audio.nix`) rather than scattered across `services.pipewire`, `services.wireplumber`, `security.rtkit`, `hardware.pulseaudio`, and `hardware.bluetooth` (which it synthesizes). Enables future re-configuration by tweaking `nixos/hosts/` without touching the module logic.
## 38. Noctalia as Single Source of Truth for Theming — Starship/Shell/UI Driven from M3 Roles (2026-09-05)

* **Decision:** Noctalia is the sole, authoritative source of theming. Shell (starship) and UI (niri, kitty, fuzzel) all consume Noctalia's published M3 roles and palette; no hand-authored color config outside Noctalia exists.

* **Implementation:** Starship uses a community M3 template (`starship-m3`, live at `~/.local/state/noctalia/community-templates/starship-m3/`). Template `post_hook` (`apply.sh`) splices Noctalia's rendered role set into `dots/starship/starship.toml` between markers. `~/.config/starship.toml` is symlinked to the repo via `mkOutOfStoreSymlink`; survives reboots.

* **What this kills:** Dormant `dots/color-engine/apply_theme.py` and custom palette layer (`dots/noctalia/palettes/volnix.json`). Both are superseded; Noctalia owns palette selection and emission. apply_theme.py contains a hazardous greedy regex (line 145) that would destroy the file if invoked.

* **Consequence:** Single control surface (Noctalia's theme command `color-scheme-set <source> <name>`) drives the entire desktop. Changes propagate to niri, kitty, starship, fuzzel in one operation. Starship now uses M3 role names only (`primary`, `on_primary`, `tertiary`, `surface_container`, etc.), no terminal ANSI ramp fallback.

* **Verified:** Round-trip scheme Rosewater → Sapphire → Rosewater. Prompt accent now equals niri `active-color` exactly (`#f4dbd6`, `#7dc4e4`, `#f4dbd6` confirmed).

* **Why this design:** Prevents config drift and color misalignment. Terminal ramp (8 colors + shades) is a lossy subset; M3 roles are the full semantic set. Hand-authored layers invite inconsistency. Noctalia's community template system makes this possible without forking upstream.
## 39. Flake Templates — Five Languages, No Default Enforced (2026-09-05)

* **Decision:** Provide five language templates (`templates/{ruby,hugo,python,go,lua}`) for rapid project scaffolding. Each template is a complete mold with flake.nix, .envrc, .gitignore, and README.md. Intentionally no `templates.default`.

* **Why no default:** With five templates, a bare `nix flake init -t ~/.nix-config` would scaffold into a random language, often wrong. Requiring the language name (`nix flake init -t ~/.nix-config#python`) forces explicit choice and prevents silent mismatches.

* **Gitignore placement:** `.gitignore` sits at `templates/.gitignore` (one level above individual templates), so `nix flake init` never copies it into stamped projects. This prevents each new project from inheriting a stale `flake.lock` (templates must not commit locks; projects must). Testing pattern: stamp templates into scratch directories, not `direnv allow` in-place (which leaves artifacts in the config repo).

* **Checks pattern (all five templates):** Each template includes a `checks` attrset mapping gate names to `runCommand` derivations (e.g., `check-unit`, `check-fmt`). Enables granular failure reporting in `nix flake check` (failures name the gate, not an opaque script). Each gate runs against a writable `$TMPDIR` copy to allow temp file writes without spurious failures. Empty by default.

* **Lua template specificity:** Single live consumer: drive-health (33 `.lua` harnesses). Lua 5.4 and LuaJIT pass the test suite; Lua 5.1 fails. Gotcha: `pkgs.luarocks` is built against lua5.2 by default; use `pkgs.${luaAttr}.pkgs.luarocks` to match your Lua version. Known gap: lua template should be `luau` (community-plugins has 337 `.luau` files against 33 `.lua`), but user does not use nvim/wezterm. Deferred, low priority.

* **Implementation constraint:** All template `.nix` files sit inside `${self}` and must pass this flake's nixfmt/statix/deadnix gates. Rules out lambda-based option lists (deadnix flags unused arguments); use attrset of strings instead.

* **Verification (measurement-based, real consumers):** lua → drive-health `make unit` rc=0 (lua5.4, luajit); python → memd 255 pytest tests; hugo → site builds rc=0; go → produces running binary; ruby → bundlerEnv build succeeds.

* **Usage:** `nix flake init -t ~/.nix-config#<language>` to scaffold new project. Do not work inside template directory itself (stamp into a new directory for each project).
## 40. Luau Template — Discovery-Driven Gate Strategy (2026-09-06)

* **Decision:** The luau template (`templates/luau/`) uses runtime discovery of `*.luau` files in the project root rather than hardcoding a file list in the flake. This prevents the silent-ship-of-broken-code failure mode where undeclared local functions pass type-check gates (because the gate ran on a fixed list of files that happened to include the definition).
* **Why:** Controlled regression testing showed: (1) hardcoded nine-file list (current state of claude-companion/noctalia-claude-plugin/flake.nix) misses a tenth entry that calls an undeclared local — gate passes (false negative). (2) Discovery mechanism over `builtins.readDir` catches the undeclared reference — gate fails as intended (true positive). The hardcoded approach silently ships a broken plugin.
* **Implementation:** `builtins.readDir .` returns all files; filter to `*.luau` via `lib.filterAttrs (n: t: lib.hasSuffix ".luau" n && t == "regular")`. Exclude `definitionsFile` (input to the analyser, not a target). Advantages: scales with project growth, catches missing declarations, no sync burden.
* **Toolchain (same as source plugin):** Luau compiler, stylua (formatter, opt-in gate), luau-lsp (analyzer, required gate). Python 3 for cross-file analysis helpers. Comments preserved from source plugin flake.nix.
* **Known gap (load-bearing):** The source plugin flake.nix (`claude-companion/noctalia-claude-plugin/flake.nix`) still uses the hardcoded nine-file list. This gap is load-bearing — new plugin functions could be added with silently missing declarations (gate passes, plugin breaks at runtime). Backport required before any further plugin development (see todo.md).
* **Rationale:** Discovery is superior to hardcoding for any sufficiently-large project. Catches a class of errors that list-based gates miss. Load-bearing to prevent regression into the same silent-failure mode.
## 41. Gradient Design — Warm Gold Ramp with Differential Stepping (2026-09-07)

* **Decision:** Use a warm gold gradient ramp for role-based color scales (primary_1 through primary_13 in Noctalia M3 schema). The gradient walks from light (`#fddeaf` L*90) to dark (`#1a0f00` L*5) following a warm color path (R>G>B cast on every step). Luminance stepping is differential: larger steps (10 units) in the light half (L*90→L*50, better separation where text contrast matters), smaller steps (5 units) in the dark half (L*50→L*5, reduces false granularity where contrast is naturally high).

* **Gradient verified:** 13 role-based steps with accessible text contrast at key points (L*90: 16.2:1, L*60: 6.6:1, L*35: 7.8:1, L*20: 13.2:1). All intermediate roles fall into high-signal regions where semantic distinctions are perceptually clear.

* **Why warm gold:** Coherent with existing Ayu Green theme family. Warm cast provides visual warmth without competing with the primary (lime) accent.

* **Why differential stepping:** Prevents wasted granularity in the dark half. Ensures accessible text contrast at semantically-important role boundaries (e.g., `surface_container` at L*60 meets 6.6:1 requirement). Smaller steps in dark half avoid the false-emphasis problem (where too many dark variants suggest importance hierarchy that doesn't exist).

* **Implementation:** Noctalia community template + starship will consume this gradient. Each role-based variant (primary_1-13) is independently selectable for UI zones (buttons, backgrounds, accents, disabled states) while maintaining visual coherence.

* **Stability across color schemes:** The hex values shown here (`#fddeaf` through `#1a0f00`) are specific to the Ayu Green palette. When you change color schemes via `color-scheme-set source name`, Noctalia regenerates the primary gradient using the same *strategy* (warm cast, differential luminance stepping) applied to the new palette's dominant hue. The role-based architecture (primary_1-13) and step magnitudes remain constant; only the actual hex values change. Verified in decision #38: scheme change Rosewater → Sapphire produced hex updates (`#f4dbd6` → `#7dc4e4`) while maintaining M3 role semantics.

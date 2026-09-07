---
type: todo
project: Vol NixOS
last_updated: 2026-09-07
status: active
---

# Open Tasks and Enhancement Roadmap (`memory/todo.md`)

---

## COMPLETE

### Nix-on-Droid — Generation 5 Activated (2026-08-03)

✓ proot unpack bug fixed (2026-08-03, commit d4f2968)
✓ rtk 0.44.0, mcp-gateway 3.3.2, termux-am built natively on phone
✓ glibc-2.40-224 only in entire profile closure (zero glibc-2.42)
✓ Phone daily-usable; blog series unblocked

### Waydroid Setup — Move Images to Persistent Storage (2026-08-21)

✓ Ran move-waydroid.sh script; `/persist/var/lib/waydroid` contains system images
✓ Ran `make switch` to activate system persistence binds and home-manager symlinks
✓ tmpfs root decreased from 100% → 3% (99 M / 4.0 G); `/persist` usage at 46% (140 G free)
✓ `~/Android` and `~/.android` symlinks on Storage remain accessible and working
✓ GAPPS images downloaded and initialized (system.img 2462.4 M, vendor.img 535.5 M)
✓ Android session RUNNING, container RUNNING, DHCP lease obtained (IP 192.168.240.112)
✓ Device registered for Play Store certification (Android ID retrieved and registered at google.com/android/uncertified)
✓ Certification propagation in progress; awaiting Play Store sign-in verification

### Krita SVG Text Engine — Verified Fixed on 6.0.2.1 (2026-08-24)

✓ Verified (2026-08-24): SVG text engine works on Krita 6.0.2.1; FreeType glyph crash from 6.0.1 is fixed
✓ 5 font families tested; zero render errors, no crashes, empirical evidence captured
✓ Rasterize-to-paint-layer workaround now obsolete

### Krita Font Gallery Plugin — Refactor to Native SVG Shapes (2026-08-24)

✓ Refactored `_insert_sample` to insert native editable SVG text shapes via `createVectorLayer() + addShapesFromSvg()`
✓ Replaced QPainter/QImage/`setPixelData` rasterize path with pure `build_text_svg()` function (independently testable)
✓ XML escaping verified (metacharacters render literally; space entities used for whitespace)
✓ Multi-line text verified (one `<tspan>` per line; vertical advance correct)
✓ End-to-end tested in isolated harness (`<scratchpad>/ktest/`, Xvfb-driven Krita 6.0.2.1); 4/4 cases pass
✓ Krita swap file moved from `/tmp` (4 GB tmpfs) to `~/Storage/tmp/krita-swap` (269 GB NVMe, 2026-08-24) to prevent SIGBUS crashes
- [ ] Interactive on-canvas text tool (GUI, not engine) — human verification pending (~10 min)

### Wiki Documentation — Krita Page Published (2026-08-24)

✓ Published `content/en/desktop/krita.md` (weight 40) to volnixos-wiki
✓ Updated desktop section index to link the new page
✓ Covered: swap hazard + fix, text engine timeline, plugin refactoring, G'MIC patch, testing harness
✓ Build clean: 31 pages, 47 internal links validated

### Phone-Agent MCP Activation (2026-08-07 — Complete, Verified 2026-08-24)

✓ Run `make switch` to activate phone-agent MCP in Claude Code (completed 2026-08-21)
✓ Claude Code session restarted (happened between 2026-08-21 and 2026-08-24)
✓ phone-agent tools verified accessible: gateway lists phone-agent tools, GSC invocations successful in same session, all 11 backends respond

### GSC MCP Backend Wiring (2026-08-24 — Complete, Verified Live)

✓ Service account JSON added to sops secrets (`gsc_service_account`, 2395 bytes, type service_account, valid JSON)
✓ Service account email added as user to both Search Console properties (infernalcode.com, hotelevangelism.blog) with siteFullUser permissions
✓ Gateway backend enabled and verified: `gsc` returns 8 tools, `list_sites` returns both properties, queries return real data, index_inspect confirms indexing

### Krita Swap Directory Persistence (2026-08-24 — LIVE in gen 247)

✓ Swap directory persistence declared via activation script: `$HOME/Storage/tmp/krita-swap` in `home.activation.ensureScratchDirs`
✓ Activated in gen 247; verified LIVE via findmnt and frame cache presence
✓ Prevents SIGBUS crashes from mmap-based caching on impermanence tmpfs

### Thunderbird + Spotify Persistence (2026-08-24 — LIVE in gen 247)

✓ Spotify config persistence via impermanence bind-mount; verified LIVE via findmnt
✓ Thunderbird persistence via Storage symlink (`~/.thunderbird → /home/lowcache/Storage/thunderbird`); symlink chain verified correct and LIVE
✓ Both mechanisms activated in gen 247; email/profile data and Spotify login persisted across tmpfs-root wipe

### Audio Module — Implemented, Built, Awaiting Activation (2026-08-25)

✓ Created `nixos/modules/audio.nix` (146 lines, option-typed, vol.audio namespace)
✓ Integrated into `nixos/modules/default.nix` imports
✓ Merged repeated `vol.*` keys in `nixos/hosts/volnix.nix` into single `vol = { … }` block
✓ `make check` exit 0; `make build` completed successfully
✓ Verified in closure: wireplumber-extra-config generates three drop-in configs with correct codec/policy/parked-card rules
✓ Codec support verified in closure: libfdk-aac (AAC), libldacBT (LDAC), libfreeaptx (aptX)
- [ ] **Awaiting activation:** `make switch` to apply module to running system
- [ ] Post-switch: `sed -i '/pci-0000_01_00.1/d; /pci-0000_66_00.1/d' ~/.local/state/wireplumber/default-profile && systemctl --user restart wireplumber` to apply parked-card rules

---

## IN PROGRESS / AWAITING ACTION

### Backport Discovery Mechanism to claude-companion Plugin (2026-09-06 — Load-Bearing)

**Context:** The luau template now uses runtime discovery of `*.luau` files via `builtins.readDir`. Controlled testing showed this prevents undeclared-reference bugs that hardcoded file lists miss (false negatives). The source plugin flake.nix still uses the old nine-file hardcoded list and is thus vulnerable.

**Implication:** Any new plugin functions added to claude-companion could silently have missing declarations (gate passes, plugin breaks at runtime). This is the exact failure mode the plugin flake's own comments acknowledge.

- [ ] Open `~/CodeRepo/claude-companion/noctalia-claude-plugin/flake.nix`
- [ ] Replace hardcoded `luauFiles` string with discovery logic from `templates/luau/flake.nix`
- [ ] Test: run `nix flake check` on the plugin repo; verify all gates pass
- [ ] Commit to claude-companion repo

### Audio Module Activation (2026-08-25 — USER DECISION PENDING)

**Status:** Audio module is built and ready. Requires activation via `make switch` (will also apply unrelated theme formatting from dots/). Post-switch needs WirePlumber restart to apply parked-card rules.

- [ ] User runs `make switch` to activate audio module
- [ ] Post-switch: run WirePlumber restart + sed removal of stored pins
- [ ] Verify: `wpctl status` shows two sinks (Realtek + headset), not seven; `pactl list short sinks` works

### Plugin Attribution — Email Drafted, PR Staged (2026-08-25)

**Status:** Two community-plugins PRs staged locally in `/home/lowcache/CodeRepo/claude-companion/community-plugins` on branches `attribution/opencode-companion` (commit db9fe8d) and `attribution/9router-control` (commit 10648ea). Email draft written to `scratchpad/weinguyen-email.txt`. Nothing pushed.

**Sequence:** Email first at `weinguyen1224@gmail.com`, then PR if no response within ~1 week.

- [ ] Review email draft at `scratchpad/weinguyen-email.txt`
- [ ] Send email to weinguyen1224@gmail.com
- [ ] If no response in ~1 week, push branches and open PRs against upstream/main
  - PR 1: `attribution/opencode-companion` (4 lines: notice + Credits section + version bump)
  - PR 2: `attribution/9router-control` (4 lines: notice + Credits section + version bump)
- [ ] Note: repo policy is "One plugin per PR" (enforced by `enforce-pr-template` workflow)
- [ ] Note: PR author can request changes before merge unless fix is broken or mechanical repo-wide change

### Wire android-integration — Choose Strategy (2026-08-03 — USER DECISION PENDING)

**Status:** termux-am builds successfully. Two approaches:

1. **disabledModules approach** (~60 lines): Full feature set (termux-open-url, termux-wake-lock), but track upstream drift.
2. **xdg-open shim** (~5 lines): Gets OAuth's browser opening; skips wake-lock and setup-storage.

**User decision needed:** Which approach (1 or 2)? Or defer entirely?

### Verify tether × gemini-cli 0.25.2 (AWAITING USER DECISION)

**Question:** Does tether require antigravity-cli specifically, or will gemini-cli 0.25.2 (nixos-25.11) suffice?

- [ ] User clarifies antigravity vs 0.25.2
- [ ] If 0.25.2 works: add to `droid/agents.nix` (no backport)
- [ ] If antigravity required: backport (lower priority than rtk/mcp-gateway)

### apply_theme.py — Decision: Keep Dormant Code or Delete (2026-09-05 — USER DECISION PENDING)

**Context:** `dots/color-engine/apply_theme.py` no longer invoked (replaced by Noctalia's community template system for M3 palette and starship theming). File remains but **is destructive if executed**: line 145 uses a greedy regex that, when run, consumes the M3 palette block in `dots/starship/starship.toml`, erases the file tail, and recreates `volnix.json`.

**Options:**
1. Delete `apply_theme.py` entirely (recommended: M3 management is now Noctalia's responsibility; apply_theme.py serves no function).
2. Keep for historical reference; add prominent warning comment on line 145 documenting the hazard.

- [ ] User specifies preference (delete or warn)
- [ ] Curator implements decision and documents in decisions.md #38

---

## BACKLOG / DEFERRED

### Fix statix Lint on flake.nix:177-178 (2026-08-24 — Low Priority)

**Issue:** `nix flake check` fails at statix gate: "Assignment instead of inherit from" on lines 177-178 (`extraSpecialArgs = { nix-on-droid = ... }`, `home-manager-path = ...`).

**Status:** Trivial fixup (convert assignments to inherit). Host and droid targets evaluate clean; only the lint gate blocks `make check`.

- [ ] Rewrite as `inherit (inputs) nix-on-droid;` and equivalent for home-manager-path
- [ ] Run `nix flake check` to confirm gate passes
- [ ] Commit

### Wiki SEO Optimization — Noctalia Title & Meta-Description (Identified 2026-08-24, High ROI)

**Context:** GSC shows noctalia page has 701 impressions at position 9.29 with only 0.43% CTR (should be ~1.5-2.5% at that position). Title and meta-description are likely misaligned with search intent. Rewrite alone could yield 3-4× more clicks without changing ranking — highest-leverage SEO work available.

**Discovery:** Measured via GSC `search_analytics` (infernalcode.com domain property, 2026-07-25 to 2026-08-21 window).

- [ ] Analyze current title and meta-description for alignment with top search queries
- [ ] Rewrite title and meta to better match user intent (40-60 chars title, 140-160 char meta)
- [ ] Publish change to wiki
- [ ] Monitor CTR recovery via `gsc/search_analytics` over next 2-3 weeks

### Hotelevangelism Blog Post Series & Social Promotion Research (2026-08-24 — BACKLOG)

**Context:** User plans to write blog posts for hotelevangelism. GSC integration now enables discovery-based outreach (finding open questions that existing content answers). Two tracks: content production + promotional channel research.

**Content track:**
- [ ] Write blog post(s) for hotelevangelism
- [ ] Publish to ~/CodeRepo/blogs/ (hotelevangelism.blog)

**Promotion research + execution:**
- [ ] Identify relevant subreddits and HN threads where hotelevangelism content answers open questions
- [ ] Use `reddit-research-mcp` (semantic search: 20k+ subreddits) or `hackernews-mcp` (ask_hn filter) to find threads
- [ ] Craft response posts framed as answering the specific question (not bare link-drops; outreach strategy proven to work per blogs/CLAUDE.md)
- [ ] Post responses with citations to the wiki/blog

**Constraint:** Avoid bare promotional link-drops (reddit/HN ban for this). Frame as answering open questions. Proven approach: "outreach framed as answering an open question works" (noted in blogs/CLAUDE.md).

**MCP servers:**
- `reddit-research-mcp` (king-of-the-grackles/reddit-research-mcp): semantic search + citation
- `hackernews-mcp` (cyanheads/hn-mcp-server): Algolia full-text search, `ask_hn` filter, no auth

### MCP Server Evaluation — Cloudflare Official Tier + Third-Party Triage (2026-08-24 — Survey Complete, Partial Activation)

**Status:** MCP server landscape surveyed via tether (198 lines at `scratchpad/mcp-survey.md`). Results categorized and prioritized. GSC (Tier 1, Cloudflare official) is now live and verified.

**Findings:**
- **Tier 1 (Cloudflare official, recommended):** 12 servers (Workers Builds, Observability, GraphQL, DNS Analytics, Cloudflare API, Docs, Radar, Browser Run, Logpush, Audit Logs, AI Gateway, Bindings). All require `http_url:` / `streamable_http:` config in gateway.yaml (not `command:`, since these are remote stdio endpoints). Workers Builds connects directly to your open CI todo. GSC verified live (2026-08-24).
- **Tier 2 (SEO, third-party OAuth-required):** GSC (activated 2026-08-24), GA4, Bing. Require OAuth grant to your Search Console + analytics accounts.
- **Tier 3 (Other high-value third-party):** Sentry (official remote, free with account), Stripe (official, monetization-coupled), CVE MCP (free, NVD+CISA+GitHub Advisories, local uvx), SAST MCP (local Semgrep/Bandit/Trivy wrapper).

**Caution:** Survey lists Postgres as "Official + Active" in upstream servers repo; this is likely stale (most reference servers were archived). Verify before using.

**Security constraint:** Each MCP server credential grant expands trust surface. MCPS Audit ([razashariff/mcps-audit](https://github.com/razashariff/mcps-audit)) scans MCP configs against OWASP MCP Top 10. Before expanding beyond current 11 backends, run audit on `.model/.claude/.mcp.json` + `gateway.yaml`.

**Next steps:**
- [ ] Run MCPS Audit on existing 11 backends; resolve any medium/high findings before expansion
- [ ] Prioritize Cloudflare Workers Builds + Observability (aligns with wiki/deployment CI todo)
- [ ] Conditional: Activate Sentry (free, error/trace querying) + CVE MCP (security scanning)
- [ ] Defer: Stripe MCP (monetization not yet live), full GSC/GA4 suite (SEO work now underway, additional analytics less urgent)
- [ ] Archive `scratchpad/mcp-survey.md` post-implementation (reference only, not durable)

### Wiki — Polish and CI Integration (2026-08-15, partially done)

- [ ] Connect Workers Builds CI (set command `./build.sh`, var `HUGO_VERSION=0.164.0`)
- [ ] Convert home page to native data-driven layout (currently markdown, should be hero/card-grid yaml)
- [ ] Visual overhaul: port Material palette to E25DX, center content (currently left-aligned)
- [ ] Re-check GSC Page Indexing report ~2026-08-30: confirm whether the 40 "Crawled – currently not indexed" URLs (spiked 2026-08-17, post MkDocs→Hugo port) are draining out — recovery signal, not yet confirmed
- [ ] If the nix-on-droid #480 reporter confirms the same proot `_defaultUnpack` bug, open an upstream PR contributing `prootUnpack` (decisions.md #32) rather than leaving it as a local backport

### Noctalia Bar — Dual Wrap-Around Layout (2026-06-22 — LIVE, CAPTURE PENDING)

- [ ] Capture runtime state to `dots/noctalia/config.toml`
- [ ] Commit Ayu Green color-engine theme
- [ ] Commit regenerated dotfiles

### XWayland Satellite Startup — Permanent niri Integration (2026-06-23)

- [ ] Add `spawn-at-startup "xwayland-satellite" ":0"` to `dots/niri/config.kdl`
- [ ] Test: launch FireAlpaca without manual `:0` start

### SessionEnd Hook — Work-Routing (2026-06-18)

- [ ] Code path-prefix routing logic (dots/ → dots inbox, else → root)
- [ ] Register hook in `~/.claude/settings.json` as SessionEnd event
- [ ] Test with dummy work note

### Nix-on-Droid Blog Series (2026-08-03 — Functional Work Complete)

**Pending posts (user writing, lower priority):**
- [ ] Architecture post (portable layer, one-flake strategy, glibc pin)
- [ ] Deployment post (phone setup, Makefile targets, adb debug channel)
- [ ] MCP integration post (phone-agent Termux shim, Tailscale)
- [ ] proot portability post (chmod denial & structural sandbox fix)
- [ ] (Optional) Performance/runtime gotchas, troubleshooting recovery ladder

### Blog Post: "The workaround that outlived its bug" (Krita post — Outline Ready 2026-08-24)

**Status:** Outline complete at `volnixos-blog/content/posts/drafts/krita-on-a-volatile-root.md` with `draft: true`. Comprehensive beat structure, verified citations, angle: one story covering both the swap SIGBUS hazard and the philosophical cost of undeclared state on an impermanence system.

- [ ] Write full body (user authoring)
- [ ] Cross-check cited numbers against decisions.md #21, mistakes.md 2026-08-24, state.md §9 (Krita section)
- [ ] Publish (remove `draft: true`, then `cd volnixos-blog && make build && make deploy`)

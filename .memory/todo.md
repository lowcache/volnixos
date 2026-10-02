---
type: todo
project: Vol NixOS
last_updated: 2026-10-02
status: active
---

# Open Tasks and Enhancement Roadmap (`memory/todo.md`)

---

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

### Anon-Mode Fail-Closed Redesign — Testing Completed (2026-09-16)

✓ Redesign built and activated (2026-09-12)
✓ Transient boot failure on 2026-09-16 04:49 resolved without intervention by 15:29
✓ anon-selftest L4 ladder passed: enforced path verified through Tor (exit 185.100.85.25), loopback resolver unreachable, IPv6 egress blocked, jail route intact
✓ Full L0-L4 readiness ladder confirmed working in live operation
✓ fail-closed invariant proven: guest cannot leak traffic or detect lack of Tor without explicit path verification

---

## IN PROGRESS / AWAITING ACTION

### Rollback Nixpkgs Lock Pin — Playwright libmanette (2026-09-18, Temporary Workaround)

**Context:** flake.lock is pinned to f4a6f271 (2026-09-17, nixos-unstable-small) ahead of flake.nix `ref = nixos-unstable` due to a transient packaging issue in nixpkgs.

**Issue:** playwright 1.63.0 at channel rev b1b8759 requires libmanette-0.2.so.0. The upstream fix ("playwright-webkit: add missing libmanette", commit 67bf9043) postdates that channel revision by 47 minutes. auto-patchelf fails without it, blocking playwright-mcp → home-manager-path → toplevel. Pin resolves CI failures; no impact on flake user experience.

**Rollback condition:** Once nixos-unstable channel advances to or past commit 67bf9043.

**Steps:**
- [ ] Monitor nixos-unstable channel for 67bf9043 landing (check upstream nixpkgs git log)
- [ ] When available in channel: run `nix flake update nixpkgs`
- [ ] Verify: `make check` passes (all CI gates), `nix flake show` lists all outputs
- [ ] Commit the flake.lock update
- [ ] Remove the explanatory comment block from flake.nix inputs
- [ ] Expected rollback window: ~2 days from 2026-09-18 (by ~2026-09-20)

### Backport Discovery Mechanism to claude-companion Plugin (2026-09-06 — Load-Bearing)

**Context:** The luau template now uses runtime discovery of `*.luau` files via `builtins.readDir`. Controlled testing showed this prevents undeclared-reference bugs that hardcoded file lists miss (false negatives). The source plugin flake.nix still uses the old nine-file hardcoded list and is thus vulnerable.

**Implication:** Any new plugin functions added to the plugin could silently have missing declarations (gate passes, plugin breaks at runtime). This is the exact failure mode the plugin flake's own comments acknowledge.

- [ ] Open `~/CodeRepo/noctalia-plugs/noctalia-claude-plugin/flake.nix` (path corrected 2026-10-02; `~/CodeRepo/claude-companion/` no longer exists on disk)
- [ ] Replace hardcoded `luauFiles` string with discovery logic from `templates/luau/flake.nix`
- [ ] Test: run `nix flake check` on the plugin repo; verify all gates pass
- [ ] Commit to the noctalia-plugs repo

### Audio Module Activation (2026-08-25 — USER DECISION PENDING)

✓ Audio module built and activated via `make switch` (2026-09-24)
✓ Speaker mute issue discovered and fixed (codec hardware mute bit was set)
✓ Sound now emitting from onboard Realtek ALC256 speakers
- [ ] **Investigate headphone jack-sense detection failure:** jack-sense reports "not available" even when headphones are physically inserted. Possible causes: (1) missing `cctl set` command for jack-detect kcontrol, (2) BIOS ACPI DSDT issue, (3) kernel driver config mismatch. Test procedure: check ALSA jack kcontrols (`amixer -c 2 scontents | grep -i jack`), verify jack-detect enabled, check dmesg for jack events on insertion.
- [ ] Post-switch: run WirePlumber restart + sed removal of stored pins (parked-card rules still pending)
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

- [ ] Connect Workers Builds CI (set command `./build.sh`, build var `HUGO_VERSION=0.164.0`)
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

### Persist LUKS2 Encryption Migration (2026-09-23 — Planning Phase)

**Status:** Decision moved to decisions.md #45. Procedure available at `~/Storage/luks-migration/` (7-step sequence). Reversible via 99-rollback.sh. LUKS UUID d3307480-8eb3-4305-b5d6-d8d67c679022 pinned in config.

**Critical constraint:** Do NOT run `make switch` or `make boot` between steps 02 (staging) and 05 (post-boot flip).

**Open discrepancy (2026-10-02):** An unrelated session command showed `findmnt`-style output for `~/.omo` (which lives under `/persist`) backed by `/dev/mapper/cryptpersist`. This section's status is still "Planning Phase" with the migration checklist below unstarted — before resuming the LUKS plan, confirm whether `cryptpersist` is a leftover/unrelated test mapper or whether some form of persist-partition encryption is already active.

**Procedure (sequential, do not skip or repeat):**
- [ ] Step 00-setup: Prepare Ubuntu live medium, enroll MS Secure Boot keys, verify STORAGE staging directory is writable
- [ ] Step 01-format: Zero PARTUUID f994fab7-… (~/persist partition) to remove filesystem headers
- [ ] Step 02-stage: Create encrypted loop container on STORAGE as staging area; populate with current /persist contents
- [ ] Step 03-encrypt: Format actual /persist partition as LUKS2 (`d3307480-…`); copy staged contents into encrypted container
- [ ] Step 04-migrate: Verify encrypted /persist is correct; prepare boot chain
- [ ] Step 05-post-boot: First boot into `.#volnix-luks` (flake override active); systemd mounts encrypted /persist; verify unlock succeeds; flip `vol.persistLuks.enable = true` in main config; remove flake override
- [ ] Step 06-finalize: Reboot into main `volnix` config (LUKS unlock happens in initrd); verify impermanence binds work through decrypted /persist; test persistence across reboot
- [ ] **Backup LUKS header** post-step-06: `cryptsetup luksHeaderBackup /dev/mapper/luks0 --header-backup-file ~/Storage/luks-migration/luks0.header.backup` (cold-boot disaster recovery)

**If problems arise:**
- [ ] Run `~/Storage/luks-migration/99-rollback.sh` to re-stage plaintext /persist from pre-encryption backup
- [ ] Boot plaintext `volnix` config; troubleshoot and retry

**Future enhancement (TPM-only unlock, deferred):**
- [ ] Design USB-stick hidden blob + evdev key-chord sequence (AND factor)
- [ ] Update initrd to support TPM+USB combined unlock
- [ ] Test TPM unlock path end-to-end
- [ ] Remove passphrase keyslot (keyslot 0) from LUKS header once TPM path proven
- [ ] Backup LUKS header after keyslot removal (TPM-only configuration for disaster recovery)

### Backup Hardware Monitoring — Install smartmontools & Monitor SMART (2026-09-24)

**Context:** External Seagate 2TB USB backup drive reported unrecovered read error on 2026-09-24 during routine backup run. No SMART health monitoring had been configured on the host. Error was logged at block layer (sector 3574956888, near end of device); `restic check` passed despite the medium failure.

**Status:** Diagnostic infrastructure not yet in place; device remains attached and untested post-error.

**Actions:**
- [ ] Install `pkgs.smartmontools` (smartctl, smartd) to system package set
- [ ] On next device attach: run `sudo smartctl -a -d sat /dev/sda` to read full SMART status (esp. Reallocated_Sector_Ct, Current_Pending_Sector, Offline_Uncorrectable)
- [ ] Run long self-test: `sudo smartctl -t long -d sat /dev/sda` (leave device attached for hours; check results post-completion)
- [ ] If self-test reports uncorrectable errors or if pending/reallocated counts are non-zero, back up the restic repository to a new drive before the medium fails entirely
- [ ] If counts are climbing across multiple backup runs, replace the Seagate drive and re-seed the restic repo (may be approaching end-of-life)
- [ ] Document trend results in state.md §12 (SMART history) for future reference

### Audit Fix Pass — Commit, Switch, and User-Only Follow-Ups (2026-09-30, Activated 2026-10-02)

**Status:** Full-repo audit fix pass built locally (`nix build --no-link`, exit 0, reconfirmed clean 2026-10-02) and activated via `make switch` (2026-10-02). Working tree still not committed or pushed.

**Resolved 2026-10-01/02:** `~/.omo` wipe (mistakes.md 2026-10-01) recovered via `cp -a ~/.omo` to `/persist/home/lowcache/.omo` (landed, 2.2M, content-identical). `home/persist.nix` declares `~/.omo` `home.file` persistence entries (nixfmt/statix/deadnix clean). Three omo extensions (`dots/omo/memd.js`, `dots/omo/rtk.js`, `dots/omo/mcp.json`) added and symlinked into `~/.omo/agent/extensions/`; see decisions.md #26 amendments 2-3.

**New issue found and fixed during this switch (2026-10-02):** The `~/.omo` bind-mount came up after Home Manager placed its `home.file` symlinks, hiding them under the later mount. Re-running Home Manager's activation (`systemctl restart home-manager-lowcache.service`) placed the links correctly on the mounted view. Future boots mount `~/.omo` before Home Manager runs, so this was a one-time, switch-introduced issue, not a recurring one. Full root cause: mistakes.md 2026-10-02.

**Omo extension verification (2026-10-02 — mostly confirmed):** In a live post-switch omo session: `memd.js` injected the project-memory brief into the system prompt (and fires on compaction/session-end); `rtk.js` rewrote a bash call via `rtk hook claude` (confirmed: `git status --short | head -3` → `rtk git status --short | head -3`); `gateway` and `noctalia` MCP servers connected and surfaced tools via `tool_search`. `phone-agent` could not be verified — `fetch failed` because the phone was off the tailnet at test time (`curl` timed out, exit 28), not a config/secret defect (`PHONE_AGENT_TOKEN` read by name, nothing committed). Retest `phone-agent` once the phone is reachable.

**Remaining steps:**
- [ ] Review and commit working-tree diff — scope spans the original 2026-09-30 audit-pass files (decisions.md #48, 2026-09-30 mistakes.md entries) plus `dots/omo/{memd.js,rtk.js,mcp.json}`, the `home/persist.nix` edit, `home/common/fish.nix` (new `omo` wrapper function, 2026-10-02), and `hooks/omo-pulse.js` + `PROTOCOL.md` in the noctalia-plugs companion repo (path corrected 2026-10-02, decisions.md #26)
- [ ] Post-switch: verify `decapitate-fuse-mounts`, `phone-proximity-daemon`, ingest-sync, anon-selftest, and anon-watch behave correctly under audit fixes
- [ ] Retest `phone-agent` MCP in omo once the phone is back on the tailnet

**Stale todos resolved by audit pass (close once committed):**
- "Fix statix Lint on flake.nix:177-178" — rewritten as `inherit`, `STATIX_OK` confirmed against working tree
- "Rollback Nixpkgs Lock Pin — Playwright libmanette" — assessed droppable (nixos-unstable now past commit 67bf9043); confirm lock pin was removed in flake.lock diff before closing

**User-only items (not automatable):**
- [ ] Revoke the `ghp_` token exposed in public git history (commits 82ba557/3cb3be6) and rewrite history
- [ ] Give net-gate its own age key — currently holds the host key and is a recipient of `host-secrets.yaml`
- [ ] Remove `test_secret` from `host-secrets.yaml`
- [ ] Add a LICENSE
- [ ] Decide whether `.memory/` stays tracked in the public repo

### rtk vs snip Consolidation — Drop Duplicate Bash-Rewrite Hook (2026-10-02 — USER DECISION PENDING)

**Context:** Porting Claude Code's bash-rewrite hooks into omo (2026-10-02 session) found that `rtk` and `snip` do the same job — both rewrite every bash tool call into a token-saving wrapper — and Claude Code currently runs both on every call via `PreToolUse`. Only `rtk` was ported into omo (`dots/omo/rtk.js`, verified live).

**Recommendation:** Keep `rtk` only inside omo (already done). For Claude Code itself, drop the redundant `snip hook` from `PreToolUse` (user's call — changes the existing Claude Code setup, not just omo's).

- [ ] User decides whether to remove `snip hook` from Claude Code's `PreToolUse` in `~/.claude/settings.json`
- [ ] If removed: confirm `rtk`'s own rewrite-rule coverage is sufficient (`~/.claude/rules/cli-corrections.md` is `snip learn`-generated — check whether that corrections file has a non-`snip` dependency before dropping it)

### Reduce omo Token/System-Prompt Overhead — Fish Wrapper Implemented, Awaiting Switch (2026-10-02)

**Status:** Investigation, implementation, and live measurement are complete per this session's own tracked phases (6/6 done). Remaining work is purely deployment: commit, `make switch`, and a post-switch live confirmation.

**Finding (why it mattered):** omo-senpi's background `memory` component runs its own model sessions (reflection, "dream", facts, kibitzer recall) — over the prior two days this burned 223 model turns: ~745K tokens written to cache, ~7.9M read from cache, ~107K output tokens, all billed on top of `memd`, which already does the same job. Per-turn nags also add up: `comment-checker` demands a justification and the (unused — no language servers installed) `lsp` hook demands an install, on every write; a todo/goal reminder re-injects text every turn.

**Fix implemented:** New `omo` fish function in `home/common/fish.nix`. For interactive and `-p` invocations it appends four flags: `--omo-senpi-memory-disabled`, `--omo-senpi-comment-checker-disabled`, `--omo-senpi-lsp-disabled`, `--omo-senpi-todo-fanout-reminder-disabled`. Subcommands (`config`, `auth`, `list`, etc.) pass through unwrapped — the flags break subcommand routing if applied there.

**Rejected approach:** A persisted `~/.omo/omo.jsonc` config file (the original plan) was dropped in favor of the fish-level wrapper — wrapping at the shell layer is simpler and scopes the flags to exactly the invocation shapes that need them, without a second declarative config surface to keep in sync.

**Measured (pre-switch, 2026-10-02):** System prompt 64,973 chars baseline → 60,035 chars with the four flags (~8% cut). On a trivial one-line turn: 37,342 total tokens baseline vs 35,596 lean.

**Verified:** `nixfmt`/`statix`/`deadnix` clean; full system build passed; both wrapper branches tested (`omo config --help` reaches real subcommand help; a prompt run produces the lean prompt).

**Caveats:**
- Disabling `lsp` also removes omo's language-server tools — acceptable since none are installed here.
- Launches that bypass the fish function (including omo's own spawned child agents) still get the full flag-less invocation; whether child agents inherit the parent's flags was not checked.
- This session's own omo process does not pick up the change — it applies to new omo sessions started after the next `make switch`.
- The fish.nix change is uncommitted; it joins the rest of the 2026-09-30 audit-fix-pass working tree (see the Audit Fix Pass entry).

**Remaining weight (not addressed, user's call):** The `<available_skills>` block is ~23,000 chars (38% of the lean prompt) and is re-read every turn; ~13,500 chars of that comes from the `~/.claude/skills` root alone.

- [ ] Commit `home/common/fish.nix` along with the rest of the audit-fix-pass diff
- [ ] `make switch` to activate the wrapper
- [ ] Start a fresh omo session post-switch; confirm the lean prompt and absence of memory/comment-checker/lsp/todo-reminder nags in a live run (not just the pre-switch probe)
- [ ] User call: whether to also trim the skills-list overhead (23,000 chars) — no mechanism proposed yet

### Compare omo vs Claude Code Token Baseline — Harness Options Presented (2026-10-02 — USER DECISION PENDING)

**Context:** Following the omo overhead cut above, user asked how to get an apples-to-apples token/cost comparison between omo and Claude Code on the same task, while running `make git` and `make switch` in parallel. Assistant presented options only; nothing was built or decided.

**Groundwork confirmed:** Both CLIs report usage headlessly — `claude -p --output-format json` returns usage/cost directly; `omo -p --mode json` emits a `message_end` event with usage per model call. Better common yardstick: omo's subscription lane already mirrors every session as a Claude Code-format transcript into `~/.claude/projects/`, so a single `jq` sum over `message.usage` (input/cacheWrite/cacheRead/output) can score both tools from the same file format instead of trusting two different self-reports.

**Fairness requirements identified:** same model/effort pinned on both sides; fresh `git worktree` per run so neither tool sees the other's edits; matched permissions (Claude Code's `-p` mode needs `--allowedTools` or it stalls on approval; omo needs nothing); matched cache state (run all-cold with >5 min gaps, or all-warm with a throwaway first run, alternating which tool goes first); a correctness check on top of cost (cheaper-but-wrong isn't a win); at least 3 runs per configuration, compare medians.

**Options given:**
1. Fixed-overhead probe only (~15 min): trivial "reply ok" ×5 per configuration — isolates harness cost, says nothing about working-loop cost. omo side already measured (see overhead entry above: 37,342 vs 35,596 tokens).
2. **Recommended:** scripted `bench.sh` harness, three task tiers (trivial / read-only / larger task), fresh worktree per run, sums usage from `~/.claude/projects/` transcripts via `jq`, includes a correctness check, prints a comparison table.
3. A third option was being described when the session digest cuts off — not recorded; re-derive from the assistant if needed.

- [ ] User picks an option (recommended: #2, the scripted harness)
- [ ] If #2: build `bench.sh` — task-tier files, worktree-per-run orchestration, `jq` usage-summing over `~/.claude/projects/` transcripts, correctness check, median-of-≥3 reporting
- [ ] Run the harness and report comparative baseline

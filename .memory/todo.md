---
type: todo
project: Vol NixOS
last_updated: 2026-10-03
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

### Rollback Nixpkgs Lock Pin — Playwright libmanette (2026-09-18 — READY TO MERGE)

**Status (2026-10-03):** The upstream fix ("playwright-webkit: add missing libmanette", commit 67bf9043) landed in nixos-unstable at c59305b (2026-10-01). Lock bump is now safe.

**Changes already made (uncommitted):**
- Bumped flake.lock (nixpkgs now points to c59305b)
- Removed flake.nix input comment explaining the pin

**Steps to complete:**
- [ ] Run `nix build --no-link` to verify full system builds cleanly with the bumped lock
- [ ] Run `make check` to verify all CI gates pass
- [ ] Commit the flake.lock update with message mentioning 67bf9043 landed
- [ ] No user-facing changes; playwright-mcp will simply work without the intermediate workaround

### Backport Discovery Mechanism to claude-companion Plugin (2026-09-06 — Load-Bearing)

**Context:** The luau template now uses runtime discovery of `*.luau` files via `builtins.readDir`. Controlled testing showed this prevents undeclared-reference bugs that hardcoded file lists miss (false negatives). The source plugin flake.nix still uses the old nine-file hardcoded list and is thus vulnerable.

**Implication:** Any new plugin functions added to the plugin could silently have missing declarations (gate passes, plugin breaks at runtime). This is the exact failure mode the plugin flake's own comments acknowledge.

- [ ] Open `~/CodeRepo/noctalia-plugs/noctalia-claude-plugin/flake.nix` (path corrected 2026-10-02; `~/CodeRepo/claude-companion/` no longer exists on disk)
- [ ] Replace hardcoded `luauFiles` string with discovery logic from `templates/luau/flake.nix`
- [ ] Test: run `nix flake check` on the plugin repo; verify all gates pass
- [ ] Commit to the noctalia-plugs repo

### Audio Module Activation (2026-08-25 — USER DECISION PENDING)

### Audio Module Activation (2026-08-25 — LIVE, PARTIAL)

✓ Audio module built and activated via `make switch` (2026-09-24)
✓ Speaker mute issue discovered and fixed (codec hardware mute bit was set)
✓ Sound now emitting from onboard Realtek ALC256 speakers
✓ Module live in current generation; parked-card rules applied
- [ ] **Investigate headphone jack-sense detection failure:** jack-sense reports "not available" even when headphones are physically inserted. Possible causes: (1) missing `cctl set` command for jack-detect kcontrol, (2) BIOS ACPI DSDT issue, (3) kernel driver config mismatch. Test procedure: check ALSA jack kcontrols (`amixer -c 2 scontents | grep -i jack`), verify jack-detect enabled, check dmesg for jack events on insertion. Deferred, low priority.

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

**Phone-agent MCP connectivity (2026-10-02):** Tested in omo post-make-switch; tool connection failed with `fetch failed` (curl timeout, exit 28). Cause: phone offline/unreachable on Tailscale at test time, not a config or secret-handling defect (`PHONE_AGENT_TOKEN` read by name from env, zero secrets committed). Re-test once phone is back on tailnet.

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

✓ Committed as b0d38fc (2026-10-02): flake input pruning (NUR removal, nixos-hardware/impermanence follows per decisions.md #48), statix lint fixes, omo integration
✓ Switched 2026-10-02; system live
✓ ~/.omo bind-mount recovery post-switch: `systemctl restart home-manager-lowcache.service` placed symlinks correctly on mounted view (see mistakes.md 2026-10-02)
✓ Omo extension verification (2026-10-02): memd.js injected project-memory brief; rtk.js rewrote bash via `rtk hook claude`; gateway/noctalia MCP connected
✓ phone-agent MCP tested; `fetch failed` because phone offline (not config/secret issue, `PHONE_AGENT_TOKEN` read by name). Retest pending when phone reachable.
✓ CI dry-run analyzed: 1001 total derivations, 354 non-trivial
✓ GitHub key rotated and added to sops-nix (2026-10-03); live
✓ snip removed from home/pkgs.nix (2026-10-03); rtk consolidation complete (decisions.md #26 amendment 3)
✓ Executor (pkgs.llm-agents.executor) cut from home/pkgs.nix (2026-10-03); evaluated vs mcp-gateway and found unsuitable
✓ devenv plugin MCP disabled in Claude Code settings.json (2026-10-03) to resolve Lix 2.95.2 coredump cascade; nix-dev MCP provides equivalent coverage (see mistakes.md 2026-10-03)

**Stale todos closed:**
✓ "Fix statix Lint on flake.nix:177-178" — fixed in pass
✓ "Revoke `ghp_` token exposed in public git history" — rotated and in sops (2026-10-03)
✓ "snip Removal from home/pkgs.nix" — removed and confirmed intentional (2026-10-03)

**Outstanding:** Nixpkgs lock pin status (see separate todo) — verify whether playwright libmanette fix landed; expected rollback window ~2026-09-20 (now past, may be ready).

**User-only items (not automatable):**
- [ ] Give net-gate its own age key (currently holds host key)
- [ ] Remove `test_secret` from `host-secrets.yaml`
- [ ] Add LICENSE
- [ ] Decide whether `.memory/` stays tracked in public repo

### rtk vs snip Consolidation — Drop Duplicate Bash-Rewrite Hook (2026-10-02 — USER DECISION PENDING)

**Context:** Porting Claude Code's bash-rewrite hooks into omo (2026-10-02 session) found that `rtk` and `snip` do the same job — both rewrite every bash tool call into a token-saving wrapper — and Claude Code currently runs both on every call via `PreToolUse`. Only `rtk` was ported into omo (`dots/omo/rtk.js`, verified live).

**Recommendation:** Keep `rtk` only inside omo (already done). For Claude Code itself, drop the redundant `snip hook` from `PreToolUse` (user's call — changes the existing Claude Code setup, not just omo's).

- [ ] User decides whether to remove `snip hook` from Claude Code's `PreToolUse` in `~/.claude/settings.json`
- [ ] If removed: confirm `rtk`'s own rewrite-rule coverage is sufficient (`~/.claude/rules/cli-corrections.md` is `snip learn`-generated — check whether that corrections file has a non-`snip` dependency before dropping it)

### Reduce omo Token/System-Prompt Overhead — Fish Wrapper Implemented, Awaiting Switch (2026-10-02)

✓ Fish `omo` wrapper implemented in `home/common/fish.nix` (disables memory, comment-checker, lsp, todo-fanout-reminder via `--omo-senpi-*=true` flags)
✓ System prompt overhead cut ~8% (64,973 → 60,035 chars)
✓ Fixed flag bug: bare flags swallowed next word; now use `=true` syntax. Subcommands pass through bare.
✓ Committed in audit-fix-pass b0d38fc (2026-10-02)
✓ Switched 2026-10-02; post-switch verification completed: lean prompt active, nags absent
✓ Wrapper verified working in live omo sessions
- [ ] User decision: trim `<available_skills>` block (23,000 chars, ~38% of lean prompt)? No mechanism proposed yet.

### Compare omo vs Claude Code Token Baseline — Harness Options Presented (2026-10-02 — USER DECISION PENDING)

**A/B test completed (2026-10-02, both on `claude-opus-5`):**
- Fixed overhead ("Reply: ok", cold): Claude Code 37,127 tokens; omo lean 35,199 (wash)
- Lookup with known answer ×2: Claude Code ~27k cache-write per run; omo 3.5k/833 (warm cache mixed in). Cache-read variance (Claude 48k-87k, omo 70k-140k) driven by cache state, not tool.
- **Verdict:** Per-request cost is comparable. Earlier omo "burn" was memory component (now off) + nag hooks.

**Discoveries:**
- Claude Code 2.1.272 cannot run Opus 5.5 (needs >= 2.1.280); bare `--model claude-opus-5` is current pin
- omo quirks: bare model name fails; use `anthropic-subscription/claude-opus-5`. `--mode json` without `--no-session` also produces no output.

**Harness options given:**
1. Fixed-overhead probe only (~15 min): trivial "ok" ×5 per config
2. **Recommended:** Scripted `bench.sh`, three task tiers, fresh worktree per run, usage sum via `jq` over `~/.claude/projects/` transcripts, correctness check, comparison table
3. (Third option partially described; not recorded)

**Next steps:**
- [ ] User picks option (recommended: #2)
- [ ] Fix Claude Code model ID mismatch in test config (verify against 2.1.272)
- [ ] Fix omo JSON/session mode invocation (confirm flag order, `--no-session` behavior)
- [ ] If #2: build `bench.sh`, run, report baseline

### Brave Browser — Popups and Page Hangs (2026-10-02 — Diagnostics Pending)

**Symptom:** Version 153.1.95.101 experiencing unwanted popups/new-tab opens and page hangs requiring manual refresh. Both behaviors never seen before in this install.

**Diagnostic procedure:**
- [ ] Check Brave version; update to latest stable if behind
- [ ] Disable all extensions, restart, reproduce symptom
- [ ] If gone: re-enable one-by-one to identify culprit
- [ ] If persists: check `about://crashes` and DevTools console for errors
- [ ] Test in fresh profile (Settings → Profiles → Add) to isolate profile-specific state
- [ ] Monitor resources (top/htop) during hangs for CPU/memory spike
- [ ] If reproducible: capture console output and JavaScript errors

**Likely causes:** (1) Misbehaving extension, (2) Corrupted profile state, (3) Brave version regression. Isolating variables required to diagnose.
### Ollama Hardening — ProtectHome + BindPaths vs Relocate ~/.ollama Identity (2026-10-03 — USER DECISION PENDING)

**Context:** ollama runs as lowcache user with `ProtectHome=false`, making it reachable tailnet-wide via the tailscale VM DNAT. Two hardening options:

1. **ProtectHome + BindPaths approach:** Set `ProtectHome = true` in nixos/ollama.nix systemd service, then `BindPaths = [ "/home/lowcache/Storage/ollama" ]` to allow only the model cache. Reduces attack surface: home directory invisible to ollama.
2. **Relocate identity:** Move `~/.ollama` (identity/config) to `~/Storage/ollama` (persistent storage like krita-swap), symlink it back via `home.file`. Keeps `ProtectHome=false` but clusters ollama state in external storage.

**Trade-off:** Option 1 is cleaner isolation; option 2 is simpler (no systemd hardening, follows existing Storage symlink pattern). Option 1 breaks if models live in `~/.ollama` instead of `~/Storage/ollama` (needs verification).

**Recommendation:** Option 1 if models are in Storage; Option 2 if identity is tied to home.

- [ ] User decides: hardening (1) or relocation (2)?
- [ ] Implement the chosen option
- [ ] Verify ollama still functions and models load correctly

### Phone-Network-Routing User Unit — Orphaned, Wire or Delete (2026-10-03 — USER DECISION PENDING)

**Context:** `nixos/phone-agent/network-routing.nix` defines a systemd user unit but it has no `wantedBy`, `timer`, or explicit caller. The unit exists but is never started.

**Options:**
1. **Delete:** If network routing is handled elsewhere, remove the orphaned unit
2. **Wire:** If it should run automatically, add `wantedBy = [ "default.target" ]` or attach to an existing timer/service
3. **Document:** If it's intentionally manual-invoke-only, add a comment explaining the use case

- [ ] User clarifies intent
- [ ] Implement (delete/wire/document)

### ~/.config/phone-agent Ownership — tmpfiles Rule (2026-10-03 — Low Priority)

**Context:** `~/.config/phone-agent` is created by sops-nix with ownership `root:root` and mode `755`. Should be `0700` and owned by lowcache user (follows typical home config conventions).

**Fix:** Add tmpfiles.d rule: `d /home/lowcache/.config/phone-agent 0700 lowcache users -`

**Priority:** Low (current permissions are readable by group, which is acceptable for config; harmless but not ideal).

- [ ] Add tmpfiles rule to nixos/tmpfiles.nix or phone-agent module
- [ ] Test: verify ownership post-switch

### Lix Coredumps — devenv Plugin MCP Duplicate Server (2026-10-03 — REGRESSION)

**Context:** 56 Lix 2.95.2 coredumps in 3 days, all triggered by `nix-shell -p uv --run 'uvx mcp-nixos'` (devenv Claude Code plugin's MCP invocation). Stack trace shows `RunningProgram` dtor assertion on session teardown. Root cause: devenv plugin and nix-dev plugin both start mcp-nixos servers; devenv tries to run via `nix-shell`, nix-dev via `nix run`. Duplication causes resource contention or lifecycle mismatch.

**Current workaround:** Disabled devenv plugin (user already did this).

**Fix approach (user directive 2026-10-03):** Remove devenv plugin MCP entirely (option 1); rely on nix-dev MCP alone. Simplest approach and aligns with snip/rtk consolidation.

**Implementation:**
- [ ] Remove devenv plugin MCP configuration from Claude Code settings
- [ ] Verify devenv plugin still functions (MCP is optional; plugin's shell/direnv integration remains)
- [ ] Monitor for coredumps over 1-week test window post-implementation

### Tether Brief Size Limit — MAX_ARG_STRLEN (2026-10-03 — BLOCKER FOR LARGE BRIEFS)

**Context:** tether's `-f` flag (full project state) embeds the entire brief into a single argv string. With briefs >128 KiB, this hits kernel `MAX_ARG_STRLEN` limit (~131 KiB), causing "Argument list too long" error when invoking the agent via agy.

**Current workaround:** Use smaller `-f` scope or pass via stdin.

**Fix:** Refactor tether to pass large briefs via file descriptor or stdin instead of argv.

**Priority:** Low (only blocks very large memd/system briefs; typical project briefs fit).

- [ ] Refactor tether brief passing (file/stdin path)
- [ ] Test with >200 KiB brief (volnixos full state) to verify

# Wiki fixins: 2026-09-19 review fixes

Config changes from a code review of `~/.nix-config`. Pages are relative to
`~/CodeRepo/sites/blogs/wiki/content/en`. Line numbers are from wiki commit `4b57c32`.

**Before editing:** the config changes were uncommitted when this was written. Confirm they
landed (`git log -- nixos/phone-agent nixos/modules/ai-stack.nix nixos/modules/containers.nix`)
and read the current files. If the config has moved on since, the config wins over this file.

| Config file | Change |
|---|---|
| `nixos/phone-agent/ingest-sync.nix` | Verify before retiring; per-file failure isolation |
| `nixos/phone-agent/client.nix` (new) | Shared phone client used by every unit and the CLI |
| `nixos/phone-agent/push.nix` | Opens `pushPort` on `vm-tailscale` in the host firewall |
| `nixos/phone-agent/{default,proximity,network-routing}.nix` | Use `client.nix`; trimmed `PATH`s |
| `nixos/modules/ai-stack.nix` | Removed `OLLAMA_ORIGINS=*` |
| `nixos/modules/containers.nix` | fooocus published on `127.0.0.1` only |

---

## 1. `phone/phone-agent.md`

### 1a. Ingest section (lines 136–148): rewrite, and drop the CAUTION block

The CAUTION block ("Deletion happens before verification") is now false. It was also inaccurate
before the fix: `delete_after:true` *moves* the phone's copy to `~/ingest/staged-delivered`, it
does not delete it (commit `babfbbb` recovered a file by moving it back to `staged` by hand).

Facts to cover. All were verified against the real phone on 2026-09-19.

- Each listed file not already present locally is fetched with `delete_after:false`. The phone
  keeps its copy in `~/ingest/staged`.
- The payload is decoded to `<ingestDir>/staged/.tmp.<name>` and its sha256 compared to the listing.
  On a match it is moved to `<ingestDir>/staged/<name>`. Then `phone.ingest.fetch` is called again
  with `delete_after:true`, which moves the phone's copy to `~/ingest/staged-delivered`.
- So the phone retires a file only after the laptop holds a verified copy. **Cost: every file
  crosses the link twice.** The phone server exposes only `list` and `fetch`, so retiring means
  a second fetch. A phone-side ack tool would make it one transfer (not implemented).
- Failures are per file. A fetch error, a hash mismatch, or a failed retire is logged to stderr,
  counted and skipped: `fetch failed for <name>`, `sha mismatch for <name>`, `retire failed for <name>`.
  The rest of the batch still runs, and the unit exits 1 at the end with
  `N file(s) failed; will retry next run`, so it shows as failed in `systemctl --user status`.
  - Nothing is lost: an unverified file is still in the phone's `staged` and is retried next run.
  - A file verified on an earlier run whose retire failed gets retired on the next run.
- A delivered file re-staged under the same name with **different** content is logged as
  `name collision for <name>; left on phone`. It is not counted as a failure and is never overwritten.
- The phone server reports tool errors as HTTP 200 with `{"error": …}` in the result text, not
  as MCP `isError`. The script therefore counts a fetch as successful only if the reply carries
  `content_b64` (first fetch) or `sha256` (retire).
- An unreachable phone is still a silent no-op (health check, exit 0). Unchanged.

Optional history note, the author's call: files stranded by the old behavior before 2026-09-19
may still be sitting in the phone's `~/ingest/staged-delivered`. Moving one back to `staged`
gets it re-synced.

### 1b. MCP transport paragraph (lines 83–85)

Current: "it is the `phone-agent` CLI plus the shared `nixos/phone-agent/scripts/phone-mcp-call.sh`
dispatcher, governed globally by `enable`."

Add that `nixos/phone-agent/client.nix` wraps the dispatcher once with the phone's address and
token. Every unit and the `phone-agent` CLI call the phone through it (`client.call`), and the
health checks build their URL from `client.url`. The address and token are declared in one place,
not copied into each unit.

### 1c. PATH paragraph (lines 87–90): now wrong in detail

Current text says every MCP-calling unit gets `curl`, `coreutils` and `bash`, and that `jq` is
always referenced by store path. Replace with:

| Script | `PATH` |
|---|---|
| shared client (`phone-call`) | `curl`, `coreutils`; runs the dispatcher with `bash` by store path |
| `phone-ingest-sync` | `curl`, `coreutils`, `jq` (jq is now used at several call sites here) |
| `phone-proximity-daemon` | `curl`, `coreutils`, `niri` |
| `phone-network-routing` | `coreutils` |
| `phone-push-server` | `coreutils` (unchanged) |

`jq` is still referenced by store path in proximity, network-routing and the CLI. `logger` and
`python3` are unchanged, still referenced by store path.

### 1d. Push section (lines 123–124) and the `pushPort` row in the Options table (line 67)

Current: "reaching it from the tailnet requires the matching `:8463` `forwardPorts` entry in `vms.nix`."

That was half the story. Reaching it takes two pieces:

1. the `:8463` `forwardPorts` DNAT in the tailscale guest (`vms.nix`), and
2. a host firewall exception on `vm-tailscale`. `push.nix` now declares it itself, gated on
   `enablePush`:
   ```nix
   networking.firewall.interfaces."vm-tailscale".allowedTCPPorts = [ cfg.pushPort ];
   ```

Before 2026-09-19 the exception was missing. The host firewall (`trustedInterfaces` is only `lo`
and `waydroid0`) refused the DNAT'd connections, so push was unreachable from the tailnet even
with `enablePush = true`. Whether to mention that is the author's call.

Options table, `pushPort` purpose: "Port on `pushBindAddr`; the module opens it on `vm-tailscale`.
Needs a matching `forwardPorts` entry in `vms.nix`."

---

## 2. `system/ai-stack.md`

### 2a. Ollama environment table (line 58): remove the `OLLAMA_ORIGINS=*` row

The row's stated reason, "Allow web origins (Open WebUI)", was wrong. Open WebUI calls Ollama from
its backend (`OLLAMA_API_BASE_URL`), not from the browser, so it needs no CORS.

Suggested replacement, a sentence after the table: `OLLAMA_ORIGINS` is deliberately unset. `*`
let any web page open in the browser call the API on `127.0.0.1:11434` and read the replies
(loopback is a trusted interface, so the firewall never applies). Ollama's default admits only
local origins, and nothing here needs more. The check applies only to requests carrying an
`Origin` header, which browsers add. Server-side callers, such as Open WebUI's backend and the
Termux phone agent, normally send none. (That the phone sends none is inferred, not tested.)

Verified 2026-09-19 against Ollama 0.34.0 with `OLLAMA_ORIGINS` unset:

| Request | Response |
|---|---|
| `Origin: https://attacker.example` | `403` |
| `Origin: http://localhost:3000` | `200`, `Access-Control-Allow-Origin: http://localhost:3000` |
| no `Origin` header | `200` |

### 2b. Fooocus snippet (line 75) plus a sentence after it

- `ports = [ "7865:7865" ];` → `ports = [ "127.0.0.1:7865:7865" ];`
- Explain: a Docker published port bypasses the NixOS firewall. Docker's NAT rules forward the
  traffic before `nixos-fw` sees it, and the NixOS option docs for
  `virtualisation.oci-containers.containers.<name>.ports` say so directly. An unprefixed
  `7865:7865` exposed the unauthenticated UI to every network the laptop joined while the
  container ran. The UI is at `http://127.0.0.1:7865`.
- `CMDARGS = "--listen"` stays. It binds `0.0.0.0` *inside* the container, which the port mapping
  needs. The host side is what's restricted.

---

## 3. `networking/tailscale.md`

### 3a. The `:8463` paragraph (lines 69–72)

Add that the host-side firewall exception for `:8463` lives in `nixos/phone-agent/push.nix` and
follows `phone-agent.enablePush`. Ollama's `:11434` exception is different: it follows
`vol.ai-stack.ollama.exposeToTailscaleVm` (see `system/ai-stack.md`). Link back to the phone-agent
Push section (fix 1d) rather than repeating it.

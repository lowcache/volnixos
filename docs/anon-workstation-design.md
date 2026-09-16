# Anonymity Workstation — Design

Status: implemented and verified end to end.

## Goal

Give CLI/automation workloads a **kernel boundary** instead of a uid boundary.

`anon-run` today is a routing jail: uid 10000 selects a policy routing table whose
default is a blackhole unless the net-gate gateway route is installed. That
enforces *egress*, and it enforces it well — an application that ignores every
proxy variable still cannot reach the clearnet. What it does not provide is
isolation. The workload runs on the host kernel, as a host uid, with access to
the host filesystem. A kernel bug or a privilege escalation escapes every layer
at once.

This design adds `anon-box`: a workstation microvm whose only network path is the
existing net-gate Tor gateway, entered interactively via `anon-shell`.

## Non-goals

- **Not a GUI workstation.** Browsing is already served by the SOCKS interface
  (`tor-brave`, `tor-curl`). No display path, no clipboard policy.
- **Not persistent-identity comms.** That needs durable secret state and
  encryption at rest, and is a separate project with an opposite state lifecycle.
- **Not a replacement for `anon-run`.** The uid jail stays for quick one-offs
  where VM boot latency is not worth paying.
- **Not application-layer anonymity.** Fingerprinting, cookies, logins and
  timezone leaks operate above this boundary and are untouched by it.

## Architecture

```
         ┌─ tap vm-netgate ─ 192.168.100.1 ──┐
  host ──┤                                    ├── net-gate ── WAN (masq .2/32)
         └─ (uid jail, SOCKS — unchanged) ────┘      │
                                                     │ tap vm-ngi
                                              [ br-anon ]  ← host holds NO address
                                                     │ tap vm-anonbox
                                               anon-box  192.168.102.2
```

net-gate becomes two-legged: WAN-side on `vm-netgate`, inner side on
`192.168.102.1`. `br-anon` is a networkd bridge carrying **no host address** and
`LinkLocalAddressing=no`.

The property this buys, and the reason for the topology: **the workload never
runs on the machine that terminates Tor.** Compromise anon-box and you still
cannot read the guard set, rewrite torrc, or learn the host's WAN address. The
host is not in the data path and cannot reach the workstation over IP at all.

### Addressing

| Interface | host tap | MAC | Address | Gateway |
|---|---|---|---|---|
| net-gate outer | `vm-netgate` | `02:00:00:00:00:01` | 192.168.100.2/24 | 192.168.100.1 |
| net-gate inner | `vm-ngi` | `02:00:00:00:00:03` | 192.168.102.1/24 | *none* |
| anon-box | `vm-anonbox` | `02:00:00:00:00:04` | 192.168.102.2/24 | 192.168.102.1 |

`vm-ngi` and `vm-anonbox` are enslaved to `br-anon`; neither carries an address
host-side. MACs `:01` and `:02` are already allocated to net-gate and the
tailscale guest, so `:03`/`:04` are free.

**vsock CID: 12.** net-gate holds 10 and tailscale holds 11. `anon-shell` reaches
the guest through the hybrid-vsock socket at
`/var/lib/microvms/anon-box/notify.vsock` (see the constraint below — this is a
Unix socket, not kernel AF_VSOCK). The CID must not collide with a future guest.

## Verified platform constraints

These were confirmed against the pinned `microvm.nix` and the running system.
Each one invalidates an obvious-looking alternative, so they are recorded rather
than rediscovered.

**cloud-hypervisor supports only `tap` and `macvtap` interfaces.** The runner
ends its interface dispatch with
`else throw "Unsupported interface type ${type} for Cloud-Hypervisor"`.
A `type = "bridge"` interface fails at evaluation. The bridge is therefore formed
host-side: microvm creates plain taps, and networkd enslaves them. This follows
the existing pattern for the tap `.network` units already declared in
`nixos/vms.nix`.

**Guest closures are curated by default.** `microvm.storeOnDisk` defaults to
`! (any share has source == "/nix/store")`. Because no guest shares the host
store, each boots an erofs image built from its own closure alone. The guest
learns nothing about host-installed software. net-gate's closure is ~975MB; a CLI
toolset is expected around 1.5GB.

**Shares have no read-only option.** The share submodule exposes `tag`, `socket`,
`source`, `mountPoint`, `proto` — nothing else. A read-only input share must be a
host-side read-only bind mount that is then shared.

**cloud-hypervisor's vsock is NOT kernel AF_VSOCK.** It implements *hybrid*
vsock: the guest gets a real virtio-vsock device, but the host end is a Unix
socket (`--vsock cid=N,socket=notify.vsock`) speaking a handshake — write
`CONNECT <port>\n`, read `OK <assigned>\n`, then the stream is wired to that
port in the guest. `socat VSOCK-CONNECT:<cid>:<port>` therefore cannot reach the
guest no matter which kernel modules are loaded, and neither can
`systemd-ssh-proxy`; both exist on this host, which is what made the assumption
easy to make. The guest side uses ordinary `VSOCK-LISTEN`; only the host side
needs the handshake. The socket is mode 0700 owned by the microvm user, so the
host side requires root.

**REDIRECT targets the arriving interface's primary address.** A gateway serving
two legs therefore needs a listener on EACH leg's address: host-jail traffic
arrives on the outer leg and is redirected to the outer address, workstation
traffic arrives on the inner leg and is redirected to the inner one. A listener
bound only to the outer address serves the host and silently blackholes the
workstation — the redirect still fires, it just points at a port nobody is on.
This presented as the workstation being unable to resolve anything.

**net-gate's guest network currently matches `Name = "en* eth*"`.** With a second
NIC that matches both and would misconfigure the inner leg. Matching moves to
`MACAddress`, which is deterministic because MACs are pinned explicitly.

**`microvm@.service` sets `X-RestartIfChanged=false`.** A rebuild updates
`/var/lib/microvms/<name>/current` but leaves the running guest on the old
closure. Guest changes require an explicit restart.

## Components

### anon-box guest

- **Root:** tmpfs, ephemeral. Nothing survives a restart except the explicit
  shares. Every arm is a fresh machine — no shell history, no cache, nothing to
  correlate one session against the next.
- **Store:** curated closure (see above). Adding a tool is an edit plus a
  rebuild plus a restart, wrapped by a Makefile target.
- **Journal:** **not** persisted. This deliberately inverts net-gate's choice.
  net-gate persists its journal because a dead tor was once invisible for days,
  and it logs mechanism rather than destinations. anon-box's journal would record
  actual activity, so it stays in RAM. Debugging means catching it live.
- **Resources:** 2048MB / 2 vcpu.
- **User:** unprivileged `anon` for the shell. The VM is the real boundary, but
  there is no reason to hand a scraper root inside it.
- **Reverse-path filtering needs no change.** anon-box has one NIC and its
  default route is through it, so replies arrive on the interface the reverse
  lookup expects. The asymmetry that requires `checkReversePath = "loose"` on the
  host exists only where the tap is not the default route.

### Shares

| host | guest | direction |
|---|---|---|
| `~/Storage/anon/in` (read-only bind) | `/in` | operator → workload |
| `~/Storage/anon/out` | `/out` | workload → operator |

The split is **accident prevention, not a security boundary.** It stops a
workload rewriting its own inputs and makes it harder to stage an identifying
file without thinking. It does not defend against a compromised guest root, which
can remount what it likes inside its own VM.

Output lands on unencrypted disk until the pending disk-encryption work lands.
`/out` lives under `~/Storage` specifically so it moves behind LUKS when it does.

### net-gate changes

- Second interface on `br-anon`, addressed `192.168.102.1/24`, no gateway. The
  default route stays via the host tap; that is its WAN path.
- Guest networks re-matched by MAC rather than name.
- nat rules gain a workstation arm mirroring the host's: udp/53 from the
  workstation into `DNSPort`, `RETURN` for in-subnet so SOCKS stays directly
  reachable, all remaining TCP into `TransPort`.
- `ip_forward = 0` and `FORWARD -j DROP` stop being belt-and-braces. With two
  legs they are the mechanism preventing the workstation being routed to the WAN,
  and should be treated as load-bearing.

### Readiness — L5

The existing ladder verifies the **host's** uid-jail path: L4 asserts that
`anon-exec` as uid 10000 reaches an endpoint reporting Tor egress. The
workstation's path is different — a different source address, a different leg of
the gateway, different nat rules. **L4 passing says nothing about whether the
workstation's path works.**

Treating "the gateway is verified" as "the workstation is anonymous" would
reintroduce exactly the conflation this module exists to prevent, in a new place.

**L5: the workstation's own egress reports Tor, asserted from inside the guest.**
Not simulated from the host — asked of the machine whose traffic it is, for the
same reason L4 queries the routing decision from inside the jail rather than with
a `uid` hint from root.

`anon-shell` is verify-then-enter: it runs the check inside the guest and refuses
to open a shell if it fails. An anonymous shell you can enter before the path is
proven is a shell you will use before the path is proven.

### Control surface

```
anonymous.target
  ├─ anon-routing      (host uid jail gateway route)
  ├─ anon-check        (L0-L4, writes the readiness stamp)
  ├─ anon-reap
  └─ microvm@anon-box  (new: After/Requires anon-check, PartOf the target)
```

anon-box boots only once L4 has passed, via a drop-in on the templated unit,
matching the drop-in pattern already present for net-gate. `PartOf` means disarm
takes it down. `anon-watch`'s seal path already stops `anonymous.target`, so a
health loss kills the workstation with no new code. Ephemeral root means there is
nothing to clean up.

### Makefile handles

| target | purpose |
|---|---|
| `anon-shell` | verify L5, then enter the guest over vsock |
| `anon-box-rebuild` | rebuild the guest closure and restart it (the add-a-tool path) |
| `anon-status` | extended to show the workstation leg and L5 |

`anon-run` and `anon-shell` are both kept. They differ by one word and by trust
domain — `anon-run` is the host uid jail (same kernel, instant, weaker),
`anon-shell` is the workstation VM (real boundary, boot latency). This was a
deliberate decision: alternative names were considered and made the confusion
worse rather than better.

## Failure modes

| condition | behaviour |
|---|---|
| net-gate down | workstation has no route; fails shut |
| L4 fails | anon-box never boots (Requires anon-check) |
| L5 fails | `anon-shell` refuses to open a shell |
| path health lost | `anon-watch` seals; PartOf takes anon-box down |
| guest compromised | cannot reach host over IP; cannot see tor state or WAN address |
| bridged frames | `br_netfilter` subjects them to the host FORWARD chain; an explicit intra-bridge ACCEPT keeps them independent of docker's and libvirt's chains |
| host rebuild | guest keeps old closure until explicitly restarted |

## Testing

- Extend `anon-selftest` with workstation-side negative assertions mirroring the
  host's: the guest must not reach the clearnet with the gateway withdrawn, must
  not resolve via any path but the gateway, and must fail shut on IPv6.
- Assert the host cannot reach `192.168.102.0/24` — the no-shared-L3 property is
  the design's central claim and should be tested, not assumed.
- Assert anon-box's default route is the gateway and that no other route exists.

## Known limitations

- **The `local` table bypass is unaffected on the host side.** `ip rule` consults
  `local` at priority 0, ahead of the uid jail at 100, so host-local addresses
  skip the jail. This is a property of `anon-run`, not of anon-box, which has no
  host-local addresses to reach.
- **Stream isolation on the transparent path is per-destination.** All transparent
  flows reach tor from one client address, so per-invocation isolation remains a
  SOCKS-interface property.
- **Output is unencrypted at rest** until the disk-encryption work lands.
- **Guest root can remount its own shares**, so the in/out direction split is
  advisory against a compromised workload.

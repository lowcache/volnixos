# Anonymous-mode isolation.
#
# CORE INVARIANT
#   An anonymous workload either traverses the net-gate Tor VM in a
#   verified-ready state, or it has no network connectivity at all.
#
# Everything here exists to enforce, test, or observe that one sentence.
#
# ENFORCEMENT IS ROUTING, NOT COOPERATION. The workload is not asked to use a
# proxy and is not trusted to. uid ${uid} (anon-user) selects a policy: its own
# routing table, whose default route is a blackhole. Arming replaces that default
# with one pointing at the Tor VM; disarming puts the blackhole back. An
# application that ignores every proxy variable still cannot reach the clearnet,
# because no route to it exists for that uid. The uid is a policy selector — it
# is not itself evidence that traffic was anonymised.
#
# LAYERS (each independently sufficient to stop a leak, none trusted alone):
#   1. Routing jail (anon-jail, armed at boot, never auto-released). Per-uid
#      table with a blackhole default, v4 and v6.
#   2. Transport enforcement (anon-routing + guest nat REDIRECT). While armed the
#      uid's default route points at the guest, which rewrites every TCP flow
#      into Tor's TransPort and every DNS query into Tor's DNSPort. UDP other
#      than :53 is simply not carried — Tor cannot carry it, so QUIC fails shut
#      instead of escaping.
#   3. Process confinement (anon-exec). A transient unit in anon.slice with the
#      loopback denied (so the workload cannot reach the host's stub resolver and
#      thus cannot leak a DNS query sideways), IPv6 sockets refused outright, and
#      /etc/resolv.conf replaced by one pointing at the gateway.
#
# SOCKS (9050) remains as an *interface* for applications that speak it
# deliberately — tor-curl, tor-brave. It is not the enforcement boundary.
#
# READINESS LADDER (anon-check). "The VM is running" is not "traffic is Tor'd":
#   L0 microvm@net-gate is active
#   L1/L2 something is listening on the SOCKS port (process alive and bound;
#         not separable without a control port in the guest)
#   L3 a request through SOCKS completes — circuits exist, i.e. bootstrapped
#   L4 the same request, made as the jailed uid with no proxy, comes back
#      "IsTor":true — the enforced path itself is verified
# The workload is not released (anon-exec refuses) until L4 has been recorded.
#
# Arm/disarm (manual/on-demand, never autostarts):
#   arm:    sudo systemctl start anonymous.target   (fails unless L4 passes)
#   disarm: sudo systemctl stop  anonymous.target   (re-seals, reaps anon.slice)
#   prove:  sudo anon-selftest                     (positive AND negative paths)
#
# WHY NO NETFILTER ON THE HOST. The previous design marked packets with an
# iptables mangle OUTPUT rule installed via networking.firewall.extraCommands.
# firewall-reload deletes that rule and only re-adds it when firewall-start runs,
# so every firewall reload — most `make switch` runs — opened a window where
# anon-user egress was unmarked and left over clearnet. `ip rule uidrange` needs
# no netfilter, survives firewall reloads, and leaves this host free to migrate
# to nftables later (extraCommands only works with the iptables backend).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.vol.anon-mode;

  ip = "${pkgs.iproute2}/bin/ip";
  systemctl = "${config.systemd.package}/bin/systemctl";
  systemdRun = "${config.systemd.package}/bin/systemd-run";
  curl = "${pkgs.curl}/bin/curl";

  table = toString cfg.routingTable;
  priority = toString cfg.rulePriority;
  uidRange = "${toString cfg.uid}-${toString cfg.uid}";

  # Two defaults coexist in the jail's table. The gateway wins while armed; the
  # blackhole is the floor that outlives it, because it hangs off lo rather than
  # the tap and so survives the tap being torn down with the VM.
  gatewayMetric = "100";
  blackholeMetric = "1024";
  socks = "${cfg.torVmAddress}:${toString cfg.socksPort}";

  # /24-shaped check only: enough to catch an address that can never be reached
  # through the tap, without pulling a CIDR library into the eval.
  subnetPrefix = lib.concatStringsSep "." (lib.take 3 (lib.splitString "." cfg.torVmSubnet)) + ".";

  # Bounded TCP probe, deliberately one line: it is used as a command in
  # `if ...; then` and `... && exit 0`, which a multi-line string would break.
  probeSocks = "${pkgs.coreutils}/bin/timeout 2 ${pkgs.bash}/bin/bash -c ': >/dev/tcp/${cfg.torVmAddress}/${toString cfg.socksPort}' 2>/dev/null";

  # Installing the jail, idempotently, and then CHECKING THAT IT LANDED.
  #
  # Shared by anon-jail (at boot) and anon-watch (which re-asserts it every
  # tick), because a rule that silently fails to install is a fail-OPEN jail: uid
  # ${toString cfg.uid} falls through to the main table and straight out to the
  # clearnet. That is not hypothetical — it happened on 2026-09-12. The rule went
  # in at 03:39:46 and systemd-networkd removed it nine seconds later when the
  # net-gate tap was recreated, because networkd reaps foreign routing policy
  # rules on link reconfiguration. The unit reported success throughout, having
  # never looked. ManageForeignRoutingPolicyRules is off below so networkd cannot
  # do it again, and the verification stays anyway: an unverified jail is not a
  # jail.
  jailUp = pkgs.writeShellScript "anon-jail-up" ''
    set -e

    for fam in "" "-6"; do
      ${ip} $fam rule list \
        | ${pkgs.gnugrep}/bin/grep -q "uidrange ${uidRange} lookup ${table}" \
        || ${ip} $fam rule add uidrange ${uidRange} table ${table} priority ${priority}
    done

    # The floor of the jail. Installed unconditionally at a worse metric than the
    # gateway, so arming does not remove it and it simply wins again the moment
    # the gateway route goes away. The previous "seal only if nothing owns the
    # default" form left table ${table} EMPTY when the kernel dropped the tap's
    # routes on a VM restart, and an empty table falls through to `main` — i.e.
    # straight to the clearnet. Being on lo is what makes it outlive the tap.
    ${ip} route replace blackhole 0.0.0.0/0 metric ${blackholeMetric} table ${table}
    ${ip} -6 route replace blackhole ::/0 metric ${blackholeMetric} table ${table}

    # MIGRATION GUARD. The previous design marked this uid's packets from a
    # `type route` mangle OUTPUT chain. A route-type chain re-runs the routing
    # decision whenever it changes the mark, and the `fwmark` rule that used to
    # catch that mark no longer exists. A leftover marking rule therefore lets
    # table ${table} supply the SOURCE address and then silently re-routes the
    # packet onto `main` for the DEVICE — egress over the clearnet with the
    # host's real address, while every `ip route get` still reports the tap.
    # Observed on 2026-09-12: the rule survived the overhaul in the running
    # kernel because nothing in the new config removes it. Refuse to report the
    # jail armed while it exists.
    #
    # Read the ruleset ONCE and check that the read itself worked. Piping nft
    # straight into grep with stderr discarded made an unreadable ruleset
    # indistinguishable from a clean one: the guard reported the boundary clear
    # precisely when it could not see the boundary. In a module whose whole
    # premise is fail-closed, "could not check" must mean "not verified".
    if ! ruleset=$(${pkgs.nftables}/bin/nft list ruleset 2>&1); then
      echo "cannot read the netfilter ruleset to check for a stale marking rule:" >&2
      echo "$ruleset" >&2
      echo "refusing to report the jail armed on a boundary that was not verified." >&2
      exit 1
    fi
    if ${pkgs.coreutils}/bin/printf '%s' "$ruleset" \
        | ${pkgs.gnugrep}/bin/grep -q "skuid ${toString cfg.uid}"; then
      echo "a stale packet-marking rule for uid ${toString cfg.uid} is live in netfilter." >&2
      echo "it re-routes this uid AFTER the jail has chosen a source address," >&2
      echo "which leaves over the clearnet with this host's real address." >&2
      echo "remove it, then restart this unit:" >&2
      echo "  nft -a list chain ip mangle OUTPUT     # find the handle" >&2
      echo "  nft delete rule ip mangle OUTPUT handle <N>" >&2
      exit 1
    fi

    # Verify. Reporting success over an open jail is the worst failure available
    # to this module, so it is the one thing checked explicitly.
    for fam in "" "-6"; do
      if ! ${ip} $fam rule list \
          | ${pkgs.gnugrep}/bin/grep -q "uidrange ${uidRange} lookup ${table}"; then
        echo "jail NOT installed: no '$fam' uidrange rule ${uidRange} -> table ${table}." >&2
        echo "uid ${toString cfg.uid} would reach the clearnet; refusing to report success." >&2
        exit 1
      fi
    done
    if ! ${ip} route show table ${table} \
        | ${pkgs.gnugrep}/bin/grep -qE "^(blackhole )?default"; then
      echo "jail NOT sealed: table ${table} has no default route at all." >&2
      exit 1
    fi
  '';

  # THE gateway route, raised and withdrawn as one definition — used by
  # anon-routing's ExecStart/ExecStop, by anon-check when a verification fails,
  # and by anon-selftest's "gateway withdrawn" case.
  #
  # Callers must use THESE and not `systemctl start/stop anon-routing.service`.
  # The unit is not a safe handle on the route: anon-check and anonymous.target
  # both Require= it, and systemd stops a unit whose Requires= target is
  # explicitly stopped. So stopping anon-routing does not withdraw a route — it
  # tears down the whole stack (stamp removed, anon.slice reaped), and starting
  # it again restores only the route, leaving anonymous mode silently disarmed.
  # anon-selftest did exactly that on every run.
  routingUp = pkgs.writeShellScript "anon-routing-up" ''
    # The tap is created by the microvm unit and can lag it slightly.
    for i in $(${pkgs.coreutils}/bin/seq 1 30); do
      [ -d /sys/class/net/${cfg.tapInterface} ] && break
      ${pkgs.coreutils}/bin/sleep 1
    done
    if [ ! -d /sys/class/net/${cfg.tapInterface} ]; then
      echo "${cfg.tapInterface} never appeared — is microvm@net-gate running?" >&2
      exit 1
    fi
    ${ip} route replace ${cfg.torVmSubnet} dev ${cfg.tapInterface} \
      src ${cfg.tapAddress} table ${table}
    ${ip} route replace default via ${cfg.torVmAddress} dev ${cfg.tapInterface} \
      src ${cfg.tapAddress} metric ${gatewayMetric} table ${table}
  '';

  routingDown = pkgs.writeShellScript "anon-routing-down" ''
    # anon-jail's blackhole floor is always underneath, so dropping the gateway
    # re-seals the table without a gap. Re-assert it first anyway: this must not
    # depend on anon-jail having run more recently than a flush.
    ${ip} route replace blackhole 0.0.0.0/0 metric ${blackholeMetric} table ${table}
    ${ip} route del default via ${cfg.torVmAddress} dev ${cfg.tapInterface} \
      metric ${gatewayMetric} table ${table} 2>/dev/null || true
    ${ip} route del ${cfg.torVmSubnet} dev ${cfg.tapInterface} table ${table} 2>/dev/null || true
  '';

  # The workload's resolver: the gateway, whose nat rules bend :53 into Tor's
  # DNSPort. Bound over /etc/resolv.conf inside anon-exec, so a workload that
  # never heard of Tor still resolves through it.
  anonResolvConf = pkgs.writeText "anon-resolv.conf" ''
    nameserver ${cfg.torVmAddress}
    options timeout:5 attempts:2
  '';

  # THE one definition of what "running as the anonymous workload" means. Both
  # anon-run (home/scripts.nix) and anon-selftest go through this, so the
  # confinement cannot drift between the thing users run and the thing tests
  # prove. Needs root to address the system manager; callers use sudo.
  anonExec = pkgs.writeShellScriptBin "anon-exec" ''
    probe=0
    if [ "$1" = "--probe" ]; then
      # Used by anon-check/anon-watch, which are what ESTABLISHES readiness and
      # therefore cannot require it. Not for interactive use.
      probe=1
      shift
    fi
    if [ "$#" -eq 0 ]; then
      echo "Usage: anon-exec [--probe] <command> [args...]" >&2
      exit 64
    fi
    if [ "$probe" = 0 ] && [ ! -e ${cfg.readyStamp} ]; then
      echo "anon-exec: anonymous mode is not verified ready (no ${cfg.readyStamp})." >&2
      echo "           arm it with: sudo systemctl start anonymous.target" >&2
      exit 69
    fi
    # --pty when there is a terminal to attach, --pipe when output is captured.
    if [ -t 0 ] && [ -t 1 ]; then
      io="--pty"
    else
      io="--pipe --wait"
    fi
    exec ${systemdRun} \
      --slice=anon.slice \
      -p User=anon-user \
      -p Group=nogroup \
      --quiet --collect $io \
      --working-directory=/tmp \
      --unit="anon-$$" \
      -p IPAddressDeny=localhost \
      -p RestrictAddressFamilies="AF_INET AF_UNIX AF_NETLINK" \
      -p NoNewPrivileges=yes \
      -p PrivateTmp=yes \
      -p ProtectHome=yes \
      -p ProtectSystem=strict \
      -p ProtectKernelTunables=yes \
      -p ProtectControlGroups=yes \
      -p BindReadOnlyPaths=${anonResolvConf}:/etc/resolv.conf \
      -- "$@"
  '';

  # The path probe. Used by anon-check (L4) and anon-watch, and deliberately
  # incapable of leaking:
  #
  #   L4a identity  — the launcher must actually be dropping privileges. Checked
  #                   by asking the confined process for its own uid. The first
  #                   L4 failure on 2026-09-12 returned the host's real public
  #                   address, which is only possible if the probe ran outside
  #                   the jailed uid; an unverified launcher is as dangerous as
  #                   an unverified jail.
  #   L4b jail      — the kernel's routing decision for the jailed uid, queried
  #                   FROM INSIDE the jail rather than simulated from root with a
  #                   `uid` hint (the two disagreed on 2026-09-12, and the
  #                   simulated form passed over a leaking path). Sends nothing at
  #                   all, so it can establish that the jail is intact without
  #                   risking a packet on the answer.
  #   L4c exit      — only then a real request, bound to the gateway device. If
  #                   the jail were broken, SO_BINDTODEVICE leaves it with no
  #                   route rather than a clearnet one: the probe fails shut
  #                   instead of announcing this host to the endpoint, which is
  #                   exactly what the earlier version did.
  pathProbe = pkgs.writeShellScript "anon-path-probe" ''
    who=$(${anonExec}/bin/anon-exec --probe ${pkgs.coreutils}/bin/id -u 2>/dev/null || true)
    if [ "$who" != "${toString cfg.uid}" ]; then
      echo "L4a FAIL: the launcher ran as uid '$who', not ${toString cfg.uid}." >&2
      echo "          the workload would not be governed by the jail at all." >&2
      exit 1
    fi

    # Queried from INSIDE the jail, not simulated from root with a `uid` hint.
    # Those can disagree: on 2026-09-12 the root-side simulation returned the tap
    # while the workload's own connection left over the WAN, so this assertion
    # passed over a leaking path. Asking through anon-exec puts the lookup in the
    # same uid/slice context as the traffic it is vouching for.
    decision=$(${anonExec}/bin/anon-exec --probe ${ip} route get ${cfg.probeAddress} 2>/dev/null || true)
    case "$decision" in
      *"dev ${cfg.tapInterface}"*) ;;
      *)
        echo "L4b FAIL: the kernel routes uid ${toString cfg.uid} somewhere other than" >&2
        echo "          ${cfg.tapInterface}: $decision" >&2
        exit 1
        ;;
    esac

    # Unbound, exactly as a workload would issue it — L4b is what makes this
    # safe: the kernel has just confirmed this uid's route lies through the
    # gateway, so the request cannot take the clearnet. The earlier version
    # pinned the socket to the tap with --interface instead; that was both less
    # representative (workloads do not bind) and the cause of a fast failure
    # whose error text this now captures rather than discards.
    # -w makes the client report the address it actually left from, which is the
    # one fact that distinguishes "the jail did not apply to this socket" from
    # "the packet reached the gateway and the gateway mishandled it". Inferring it
    # from the outside cost several round trips; the probe can just say so.
    err=$(${pkgs.coreutils}/bin/mktemp)
    if ! out=$(${anonExec}/bin/anon-exec --probe ${curl} -sS --max-time 30 \
        -w '\nANONMETA local=%{local_ip} remote=%{remote_ip}' \
        ${cfg.exitCheckUrl} 2>"$err"); then
      echo "L4c FAIL: no answer through the enforced path." >&2
      echo "          client said: $(${pkgs.coreutils}/bin/cat "$err")" >&2
      ${pkgs.coreutils}/bin/rm -f "$err"
      exit 1
    fi
    ${pkgs.coreutils}/bin/rm -f "$err"
    meta=$(${pkgs.coreutils}/bin/printf '%s' "$out" | ${pkgs.gnugrep}/bin/grep "^ANONMETA" || true)
    body=$(${pkgs.coreutils}/bin/printf '%s' "$out" | ${pkgs.gnugrep}/bin/grep -v "^ANONMETA")
    case "$body" in
      *'"IsTor":true'*) ;;
      *)
        echo "L4c FAIL: the enforced path answered but NOT via Tor: $body" >&2
        echo "          socket: $meta" >&2
        echo "          local=${cfg.tapAddress} only means the socket took the jail's" >&2
        echo "          source address. It does NOT prove the packets left via" >&2
        echo "          ${cfg.tapInterface}: a masqueraded egress reports the same, because" >&2
        echo "          SNAT happens in POSTROUTING, long after getsockname(). Confirm" >&2
        echo "          with a capture on ${cfg.tapInterface} before blaming the gateway." >&2
        exit 1
        ;;
    esac
    ${pkgs.coreutils}/bin/printf '%s' "$body" \
      | ${pkgs.gnused}/bin/sed -n 's/.*"IP":"\([^"]*\)".*/\1/p'
  '';

  # Proves the NEGATIVE paths, which is the half that a working exit IP cannot
  # establish. "It has a Tor IP" says nothing about whether it could also have
  # left another way.
  anonSelftest = pkgs.writeShellScriptBin "anon-selftest" ''
    fail=0
    pass() { echo "PASS  $1"; }
    bad() {
      echo "FAIL  $1"
      fail=1
    }

    if [ "$(${pkgs.coreutils}/bin/id -u)" != 0 ]; then
      echo "anon-selftest must run as root (it toggles the gateway route)." >&2
      exit 77
    fi
    if [ ! -e ${cfg.readyStamp} ]; then
      echo "anonymous mode is not armed; run: sudo systemctl start anonymous.target" >&2
      exit 69
    fi

    # 1. POSITIVE: the enforced path reaches the internet, and through Tor.
    if exit_ip=$(${pathProbe}); then
      pass "enforced path verified (uid, jail route, Tor exit $exit_ip)"
    else
      bad "enforced path is not verifiably Tor'd (reason above)"
    fi

    # 2. NEGATIVE: the host's stub resolver must be unreachable, or a
    #    proxy-ignorant application could leak its lookups to the LAN resolver.
    if ${anonExec}/bin/anon-exec --probe ${pkgs.coreutils}/bin/timeout 3 \
        ${pkgs.bash}/bin/bash -c ': >/dev/tcp/127.0.0.53/53' >/dev/null 2>&1; then
      bad "loopback resolver (127.0.0.53:53) is REACHABLE from the workload"
    else
      pass "loopback resolver is unreachable (no sideways DNS)"
    fi

    # 3. NEGATIVE: IPv6 must be refused at the socket, not merely unrouted.
    if ${anonExec}/bin/anon-exec --probe ${curl} -6 -sS --max-time 10 https://example.com >/dev/null 2>&1; then
      bad "IPv6 egress SUCCEEDED from the workload"
    else
      pass "IPv6 egress refused"
    fi

    # 4. NEGATIVE: SO_BINDTODEVICE must not escape the jail. Picking the WAN
    #    device explicitly is the obvious bypass attempt; table ${table} has no
    #    route through it, so the blackhole default must catch it.
    wan=$(${ip} route get 1.1.1.1 2>/dev/null | ${pkgs.gnused}/bin/sed -n 's/.* dev \([^ ]*\).*/\1/p')
    if [ -n "$wan" ]; then
      if ${anonExec}/bin/anon-exec --probe ${curl} -sS --max-time 10 --interface "$wan" \
          https://example.com >/dev/null 2>&1; then
        bad "binding to the WAN device ($wan) ESCAPED the jail"
      else
        pass "binding to the WAN device ($wan) is blackholed"
      fi
    fi

    # 5. NEGATIVE: with the gateway route withdrawn, the workload must have no
    #    connectivity — not fall back to the host's default route. This is the
    #    "gateway down" case, tested at the routing layer so the VM keeps
    #    running. If this script dies here the jail stays SEALED, which is the
    #    safe direction to fail in.
    #
    #    Withdrawn with routingDown, NOT by stopping anon-routing.service: both
    #    anon-check and anonymous.target Require= that unit, so stopping it
    #    cascades into a full disarm — the readiness stamp is deleted and
    #    anon.slice is reaped, killing any workload the user had running — and
    #    the matching `start` restored only the route. Every selftest run used
    #    to leave anonymous mode disarmed while reporting all assertions held.
    ${routingDown}
    if ${anonExec}/bin/anon-exec --probe ${curl} -sS --max-time 10 https://example.com >/dev/null 2>&1; then
      bad "workload still reached the internet with the gateway route REMOVED"
    else
      pass "gateway route removed => no connectivity (no clearnet fallback)"
    fi
    if ! ${routingUp}; then
      echo "anon-selftest: FAILED TO RESTORE the gateway route." >&2
      echo "               the jail is sealed (blackhole floor), so this is safe," >&2
      echo "               but anonymous mode is now down. Re-arm with:" >&2
      echo "               sudo systemctl restart anonymous.target" >&2
      exit 1
    fi

    if [ "$fail" = 0 ]; then
      echo "anon-selftest: all assertions held."
    else
      echo "anon-selftest: FAILURES above — treat anonymous mode as unsafe." >&2
    fi
    exit "$fail"
  '';
in
{
  options.vol.anon-mode = {
    enable = lib.mkEnableOption "anonymous-mode egress via the net-gate Tor VM";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10000;
      description = ''
        Policy-selector UID. Traffic from this uid receives the anonymous
        networking policy (its own blackhole-by-default routing table). Fixed so
        the `ip rule uidrange` selector is stable. The uid identifies which
        traffic is governed; it is not itself proof of anonymity.
      '';
    };

    tapInterface = lib.mkOption {
      type = lib.types.str;
      default = "vm-netgate";
      description = "Host tap interface facing the net-gate guest.";
    };

    tapAddress = lib.mkOption {
      type = lib.types.str;
      default = "192.168.100.1";
      description = ''
        Host address on the net-gate tap. Also the source address pinned on the
        jail's gateway route, so the guest's nat rules can match the host's
        anonymous traffic by source without guessing an interface name.
      '';
    };

    torVmAddress = lib.mkOption {
      type = lib.types.str;
      default = "192.168.100.2";
      description = "net-gate guest address. Single source of truth: nixos/vms.nix and home/scripts.nix both read this.";
    };

    torVmSubnet = lib.mkOption {
      type = lib.types.str;
      default = "192.168.100.0/24";
      description = "net-gate tap subnet. Assumed /24 by the address assertions.";
    };

    socksPort = lib.mkOption {
      type = lib.types.port;
      default = 9050;
      description = "Tor SOCKS5 port in the guest. An interface for proxy-aware apps, not the enforcement boundary.";
    };

    transPort = lib.mkOption {
      type = lib.types.port;
      default = 9040;
      description = "Tor TransPort in the guest. Every TCP flow from the jail is rewritten into it.";
    };

    dnsPort = lib.mkOption {
      type = lib.types.port;
      default = 5353;
      description = "Tor DNSPort in the guest. Every :53 query from the jail is rewritten into it.";
    };

    routingTable = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Policy routing table holding the uid's blackhole default and (while armed) the gateway route.";
    };

    rulePriority = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Priority of the `ip rule uidrange` selector. Must beat the main table (32766).";
    };

    readyStamp = lib.mkOption {
      type = lib.types.path;
      default = "/run/anon-mode/ready";
      description = ''
        Written by anon-check once L4 (enforced path verified via Tor) holds, and
        removed when anonymous mode is disarmed or health is lost. anon-exec
        refuses to launch a workload without it: readiness gates release.
      '';
    };

    bootstrapTimeout = lib.mkOption {
      type = lib.types.int;
      default = 180;
      description = ''
        Seconds the readiness ladder waits for tor to become able to carry
        traffic before arming fails. A cold tor with no cached consensus needs
        well over a minute: the first arm after the DataDirectory was created
        failed at 45s on 2026-09-12 while tor was still bootstrapping — a race
        in the gate, not a fault in the path. With persistTorState = true later
        arms reuse the consensus and are quick.
      '';
    };

    probeAddress = lib.mkOption {
      type = lib.types.str;
      default = "1.1.1.1";
      description = ''
        Off-subnet address used for the packet-free jail check
        (`ip route get <addr> uid <uid>`). Never connected to; it only has to be
        an address the clearnet route would claim.
      '';
    };

    exitCheckUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://check.torproject.org/api/ip";
      description = ''
        Endpoint asserting that a request really left through Tor. Must return a
        body containing `"IsTor":true`. Arming fails if it does not, which is the
        point of the check rather than an inconvenience.
      '';
    };

    sealOnHealthLoss = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When the periodic path check fails twice in a row while armed, disarm:
        withdraw the gateway route, drop the readiness stamp, and reap
        anon.slice. The workload loses the network rather than continuing
        through a gateway that can no longer be shown to anonymise it. Set false
        to keep long-running jobs alive through gateway flaps and accept that
        they stall instead.
      '';
    };

    persistTorState = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Persist the guest's Tor DataDirectory (consensus + entry guards) across
        VM restarts, via a virtiofs share onto /persist.

        Function, and the trade it makes: entry-guard stability is a Tor design
        property — a client that picks fresh guards on every boot is more
        exposed to guard-discovery attacks, and also pays a full consensus
        download (tens of seconds) before it can carry traffic. Persisting buys
        both back. The cost is that /persist is unencrypted, so the guard set and
        its timestamps are recoverable from the disk: evidence of when this host
        used Tor, though not of what it reached. No workload or application state
        is kept here — only Tor's own operational state.
      '';
    };

    persistGuestJournal = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Persist the guest's journal so the privacy mechanism can be observed at
        all. Without it the VM is a black box after boot: its tor.service died on
        2026-09-08 and the host had no way to see why for four days.

        Scope is deliberately the mechanism, not the activity: Tor's SafeLogging
        stays on and the log level stays at notice, which records bootstrap
        progress, circuit failures, restarts and resource problems — not
        destinations or connection histories.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.routingTable > 0 && cfg.routingTable < 253;
        message = "vol.anon-mode.routingTable must be 1-252; 253-255 are the reserved default/main/local tables.";
      }
      {
        assertion = cfg.rulePriority > 0 && cfg.rulePriority < 32766;
        message = "vol.anon-mode.rulePriority must be below the main table's rule (32766) or the jail never applies.";
      }
      {
        assertion = lib.hasPrefix subnetPrefix cfg.torVmAddress;
        message = "vol.anon-mode.torVmAddress (${cfg.torVmAddress}) is outside torVmSubnet (${cfg.torVmSubnet}); the gateway route would not reach it.";
      }
      {
        assertion = lib.hasPrefix subnetPrefix cfg.tapAddress;
        message = "vol.anon-mode.tapAddress (${cfg.tapAddress}) is outside torVmSubnet (${cfg.torVmSubnet}); the guest's nat rules match on it.";
      }
    ];

    # networkd's defaults have it delete routes and routing policy rules it did
    # not create whenever it reconfigures a link. The jail's uidrange rule is
    # exactly such a foreign rule, and the net-gate tap is recreated on every VM
    # restart — so the boundary was being removed by routine events. Host-wide
    # setting, and the right one here regardless: tailscale, libvirt and docker
    # all install routes networkd has no business reaping.
    systemd.network.config.networkConfig = {
      ManageForeignRoutes = false;
      ManageForeignRoutingPolicyRules = false;
    };

    # STRICT REVERSE-PATH FILTERING SILENTLY KILLS THE ENFORCED PATH.
    #
    # NixOS defaults checkReversePath to strict, emitting
    #   -t mangle -A nixos-fw-rpfilter -m rpfilter --validmark -j RETURN
    #   -t mangle -A nixos-fw-rpfilter -j DROP
    # in PREROUTING, which runs at priority -150 — ahead of nat, and ahead of
    # any routing decision.
    #
    # The enforced path is asymmetric by construction. A workload's TCP flow
    # leaves via ${cfg.tapInterface} to the guest, which REDIRECTs it into tor. The reply
    # has already been un-NAT'd by the guest's conntrack by the time it is on the
    # wire, so it reaches this host on ${cfg.tapInterface} carrying the ORIGINAL
    # destination as its source — a public address whose reverse route is the
    # WAN, not the tap. Strict rpfilter sees the mismatch and drops it. No RST,
    # no log, nothing on the guest: the client simply waits out its timeout.
    #
    # This is why DNS appeared to work while TCP did not. A DNS reply's source
    # is the guest's own address (${cfg.torVmAddress}), whose reverse route IS the
    # tap, so it passes — making the gateway look healthy while every real flow
    # through it hung. Diagnosed 2026-09-15, after the routing fixes stopped the
    # packets leaking out the WAN and let them reach the guest for the first
    # time; the two faults had been stacked, and the second was invisible until
    # the first was fixed.
    #
    # Loose mode accepts a source reachable by ANY interface, which is what an
    # asymmetric path requires. It still drops unroutable/martian sources, so
    # the anti-spoofing property that matters here is retained.
    networking.firewall.checkReversePath = "loose";

    users.users.anon-user = {
      inherit (cfg) uid;
      isSystemUser = true;
      group = "nogroup";
      description = "Policy-selector UID for anonymous-mode workloads";
    };

    environment.systemPackages = [
      anonExec
      anonSelftest
    ];

    # An execution boundary, not just a label: every workload lands here, so
    # disarming can take the whole tree down at once — `systemctl stop
    # anon.slice` kills children too, and KillMode=control-group leaves nothing
    # orphaned holding a socket.
    systemd = {
      slices.anon = {
        description = "Anonymous-mode workloads (uid ${toString cfg.uid})";
        sliceConfig = {
          TasksMax = 4096;
          # Inherited by every unit in the slice (deny lists intersect down the
          # hierarchy), so the loopback is closed for anything that lands here —
          # not only for workloads launched through anon-exec. Without this, a
          # future unit declaring User=anon-user would keep loopback access and
          # could leak lookups to the host's stub resolver.
          IPAddressDeny = "localhost";
        };
      };

      services = {
        # THE JAIL. Armed at boot and left armed. The anon uid must be unable to
        # reach the clearnet before arming, after disarming, and while anon-routing
        # is restarting — so this is not partOf anything and nothing releases it
        # automatically. systemd ordering coordinates startup; it is not the
        # security boundary. The routing policy is.
        anon-jail = {
          description = "Fail-closed routing jail for anonymous-mode uid ${toString cfg.uid}";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = jailUp;

            # DELIBERATELY NO ExecStop. The jail is the fail-closed boundary and
            # nothing may release it — least of all a routine event.
            #
            # There used to be one, tearing down the uidrange rule and flushing
            # table ${table}. Because systemd stops a changed unit before starting it,
            # and nixos-rebuild changes this unit whenever the script text
            # changes, EVERY `make switch` opened a window in which uid
            # ${toString cfg.uid} had no rule at all and therefore fell through to `main` —
            # straight to the clearnet. It is in the journal: the jail was
            # stopped at 16:11:28 on 2026-09-12 and not restored until 16:11:31.
            # Three seconds of unjailed egress, produced by a rebuild, from the
            # very teardown that was supposed to be tidy. This is the same class
            # of bug as the firewall-reload window described at the top of this
            # file, reintroduced from the other end.
            #
            # jailUp is idempotent, so a restart simply re-asserts. Stopping the
            # unit now leaves the rules installed: a uid with a blackhole default
            # is the correct resting state for a boundary nothing releases. To
            # actually remove them (disabling the module), reboot — or delete the
            # rule and table by hand, deliberately, which is the only way it
            # should ever happen.
          };
        };

        # Arming: replace the blackhole default with the gateway. `src` pins the
        # source address so the guest can match anonymous traffic by source rather
        # than by an interface name it would have to guess, and so selection cannot
        # drift to the WAN address.
        anon-routing = {
          description = "Point the anon jail's default route at the net-gate Tor VM";
          requires = [ "anon-jail.service" ];
          after = [
            "anon-jail.service"
            "microvm@net-gate.service"
          ];
          # partOf the VM as well as the target: the gateway route is `dev
          # ${cfg.tapInterface}`, so the kernel deletes it when the tap goes away with
          # the VM. Without this the unit stays "active" (RemainAfterExit) over
          # routes that no longer exist, and reports success over an open jail.
          partOf = [
            "anonymous.target"
            "microvm@net-gate.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = routingUp;
            ExecStop = routingDown;
          };
        };

        # The readiness ladder. A TCP handshake proves only that something is
        # listening; it passes on a Tor that cannot build a circuit, which is how
        # this stack sat broken for four days. L3 tests circuits through SOCKS, L4
        # tests the enforced path itself — and only L4 writes the stamp that
        # releases workloads.
        anon-check = {
          description = "Verify the anonymous path end to end (L0-L4)";
          requires = [ "anon-routing.service" ];
          after = [
            "anon-routing.service"
            "microvm@net-gate.service"
          ];
          partOf = [ "anonymous.target" ];
          onFailure = [ "anon-seal.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # DefaultTimeoutStartSec is 90s, which would kill the ladder mid-wait
            # and report a timeout instead of the real state — the one failure
            # mode this module cannot tolerate, since a timeout says nothing
            # about whether the path leaks.
            #
            # Headroom is computed from the ladder's actual worst case, not
            # guessed: L2 waits 30 iterations of (2s probe + 1s sleep) = 90s;
            # L3's deadline is bootstrapTimeout but each iteration can overrun it
            # by one (20s curl + 5s sleep); L4 makes 3 attempts of (30s curl + 5s
            # sleep) = 105s. At the old +150 a cold start could exceed the
            # timeout and be killed mid-L4.
            TimeoutStartSec = cfg.bootstrapTimeout + 300;
            ExecStart = pkgs.writeShellScript "anon-check" ''
              # Every failure below re-seals before exiting. anon-check runs
              # AFTER anon-routing, so by the time any of these fire the jail's
              # default already points at the gateway. Exiting without
              # withdrawing it left the failed arm in the one state this module
              # is built to exclude: a uid routed at a gateway that could not be
              # shown to anonymise it, with no readiness stamp to explain why.
              # anon-exec refuses without the stamp, but a process already
              # running under the uid does not consult it.
              fail() {
                ${routingDown}
                exit 1
              }

              # L0
              if ! ${systemctl} -q is-active microvm@net-gate.service; then
                echo "L0 FAIL: microvm@net-gate is not active." >&2
                fail
              fi
              echo "L0 ok: net-gate VM is running"

              # L1/L2
              listening=0
              for i in $(${pkgs.coreutils}/bin/seq 1 30); do
                if ${probeSocks}; then
                  listening=1
                  break
                fi
                ${pkgs.coreutils}/bin/sleep 1
              done
              if [ "$listening" != 1 ]; then
                echo "L2 FAIL: nothing listening at ${socks} after 30s." >&2
                echo "         the guest's tor.service is down: journalctl -u microvm@net-gate" >&2
                fail
              fi
              echo "L2 ok: tor is listening at ${socks}"

              # L3 — a completed request through SOCKS means circuits exist. Tor is
              # not ready the instant it binds: a cold start must fetch a consensus
              # first, so WAIT for the capability rather than sampling it once and
              # calling a bootstrap in progress a failure.
              deadline=$(( $(${pkgs.coreutils}/bin/date +%s) + ${toString cfg.bootstrapTimeout} ))
              bootstrapped=0
              while [ "$(${pkgs.coreutils}/bin/date +%s)" -lt "$deadline" ]; do
                if ${curl} -sS --max-time 20 --socks5-hostname ${socks} \
                    ${cfg.exitCheckUrl} >/dev/null 2>&1; then
                  bootstrapped=1
                  break
                fi
                echo "L3 waiting: tor is listening but not yet carrying traffic..."
                ${pkgs.coreutils}/bin/sleep 5
              done
              if [ "$bootstrapped" != 1 ]; then
                echo "L3 FAIL: tor still cannot carry a request after ${toString cfg.bootstrapTimeout}s." >&2
                echo "         check guest egress (tap masquerade), then the guest journal:" >&2
                echo "         sudo journalctl -D /persist/var/log/net-gate-journal -u tor" >&2
                fail
              fi
              echo "L3 ok: tor is bootstrapped (SOCKS request completed)"

              # L4 — identity, jail integrity, then a leak-proof exit check.
              # See pathProbe: none of its three assertions can put a packet on
              # the clearnet, which the first version of this check could — and
              # did, on 2026-09-12, with this host's real address.
              exit_ip=""
              for attempt in 1 2 3; do
                exit_ip=$(${pathProbe}) && break
                exit_ip=""
                ${pkgs.coreutils}/bin/sleep 5
              done
              if [ -z "$exit_ip" ]; then
                echo "L4 FAIL: the enforced path is not verifiably Tor'd (detail above)." >&2
                fail
              fi
              ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname ${cfg.readyStamp})"
              ${pkgs.coreutils}/bin/printf 'verified=%s exit=%s\n' \
                "$(${pkgs.coreutils}/bin/date -Is)" "$exit_ip" > ${cfg.readyStamp}
              echo "L4 ok: enforced path verified — Tor exit $exit_ip"
              echo "anonymous mode armed. Prove the negative paths with: sudo anon-selftest"
            '';
            ExecStop = "${pkgs.coreutils}/bin/rm -f ${cfg.readyStamp}";
          };
        };

        # Re-seals the UNIT STATE after a failed arm, which the sealing inside
        # anon-check cannot do for itself.
        #
        # anon-check's fail() withdraws the gateway route immediately, closing
        # the hole. But anon-routing is a RemainAfterExit oneshot, so it stays
        # `active` over a route that is no longer there — and systemd will not
        # re-run ExecStart on a unit it already considers active. The next
        # `systemctl start anonymous.target` would therefore never reinstall the
        # gateway, and anon-check would fail at L4b (no route at all) instead of
        # wherever the real fault is. One failed arm would poison every retry
        # until anon-routing was restarted by hand.
        #
        # Stopping anon-routing is the correct sledgehammer HERE, precisely
        # because of the Requires= cascade documented on routingUp/routingDown:
        # it drags anon-check and anonymous.target down with it, which is the
        # intended end state after a failed arm. Everything returns to inactive
        # and the next attempt starts clean.
        anon-seal = {
          description = "Reset anon-routing after a failed arm so retries start clean";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${systemctl} stop anon-routing.service";
          };
        };

        # Disarming must also stop what was using the tunnel. Otherwise processes
        # keep running under a uid whose jail just re-sealed — alive, networkless,
        # and confusing.
        anon-reap = {
          description = "Reap anon.slice when anonymous mode is disarmed";
          partOf = [ "anonymous.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.coreutils}/bin/true";
            ExecStop = "${systemctl} stop anon.slice";
          };
        };

        # PATH liveness, not process liveness. "Tor's PID exists" and even "tor
        # answers" are weaker claims than "the anonymous path still traverses the
        # gateway", so this re-runs L4 and, on a confirmed loss, takes the network
        # away from the workload instead of leaving it on an unproven path.
        anon-watch = {
          description = "Watch the anonymous path and seal on health loss";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "anon-watch" ''
              armed=0
              [ -e ${cfg.readyStamp} ] && armed=1

              # Re-assert the jail first: it is the fail-closed boundary, so
              # anything that removed it (a link reconfiguration, a manual
              # flush) gets corrected before the path is judged, not after.
              #
              # And CHECK that it worked. This used to call jailUp bare, with no
              # `set -e` in scope, so the one failure the whole script exists to
              # catch — the boundary cannot be re-established — was discarded,
              # and the disarmed branch below went on to exit 0 reporting health.
              # A jail that cannot be asserted is not a jail; if we are armed,
              # that is a sealing condition like any other.
              if ! ${jailUp}; then
                echo "jail re-assertion FAILED: the fail-closed boundary is not verified." >&2
                if [ "$armed" = 1 ]; then
                  ${lib.optionalString cfg.sealOnHealthLoss ''
                    echo "sealing: disarming anonymous.target." >&2
                    ${systemctl} stop anonymous.target
                  ''}
                fi
                exit 1
              fi

              if [ "$armed" = 0 ]; then
                # Disarmed: report on the mechanism, change nothing.
                ${systemctl} -q is-active microvm@net-gate.service || exit 0
                ${probeSocks} && exit 0
                echo "microvm@net-gate is running but nothing listens at ${socks};" >&2
                echo "the guest's tor.service is down — anonymous mode cannot arm." >&2
                exit 1
              fi

              verified() {
                ${pathProbe} >/dev/null
              }

              if verified; then
                exit 0
              fi
              # One retry: a single failed circuit is not a broken gateway.
              ${pkgs.coreutils}/bin/sleep 10
              if verified; then
                echo "anonymous path recovered after one failed check." >&2
                exit 0
              fi

              # Classify before acting, so the journal says which layer broke.
              if ! ${probeSocks}; then
                echo "gateway down: nothing listening at ${socks}." >&2
              elif ${curl} -sS --max-time 30 --socks5-hostname ${socks} \
                  ${cfg.exitCheckUrl} >/dev/null 2>&1; then
                echo "tor carries SOCKS requests but the ENFORCED path does not —" >&2
                echo "suspect the jail's gateway route or the guest's nat REDIRECT rules." >&2
              else
                echo "cannot verify the path at all: either tor stopped carrying traffic" >&2
                echo "or ${cfg.exitCheckUrl} is unreachable. Unverifiable counts as unsafe." >&2
              fi
              ${lib.optionalString cfg.sealOnHealthLoss ''
                # The invariant is "verified-ready, or no connectivity". Inability to
                # verify is therefore a sealing condition, not a warning — including
                # when the verification endpoint itself is what broke. Set
                # vol.anon-mode.sealOnHealthLoss = false to trade that for uptime.
                echo "sealing: disarming anonymous.target (the workload loses the network)." >&2
                ${systemctl} stop anonymous.target
              ''}
              exit 1
            '';
          };
        };
      };

      timers.anon-watch = {
        description = "Periodic anonymous-path liveness check";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = "10min";
          AccuracySec = "1min";
        };
      };

      # Arm/disarm handle. requires (not wants) so a failed verification fails the
      # target instead of leaving it "active" over traffic that never reached Tor.
      # The VM is only wanted: it stays up after disarming, since the SOCKS
      # interface (tor-curl, tor-brave) is useful without the jail being open.
      targets.anonymous = {
        description = "Anonymous mode: verified egress via the net-gate Tor VM (manual/on-demand)";
        wants = [ "microvm@net-gate.service" ];
        requires = [
          "anon-routing.service"
          "anon-check.service"
          "anon-reap.service"
        ];
        after = [ "microvm@net-gate.service" ];
      };
    };
  };
}

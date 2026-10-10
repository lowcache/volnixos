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
# WHY NO NETFILTER ON THE HOST. A mangle-OUTPUT marking rule was dropped on every
# firewall reload (most `make switch` runs), leaking the uid. `ip rule uidrange`
# needs no netfilter and survives reloads.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.vol.anon-mode;
  inherit
    (import ./scripts.nix {
      inherit
        config
        lib
        pkgs
        cfg
        ;
    })
    systemctl
    socks
    socksRequest
    subnetPrefix
    probeSocks
    jailUp
    routingUp
    routingDown
    anonExec
    pathProbe
    anonVsock
    anonShell
    anonSelftest
    ;
in
{
  imports = [ ./options.nix ];

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

    # BRIDGED FRAMES TRAVERSE THE HOST'S iptables FORWARD CHAIN.
    #
    # br_netfilter is loaded here (docker loads it) and
    # net.bridge.bridge-nf-call-iptables is 1, so traffic bridged between the
    # workstation and the gateway is subjected to the host's FORWARD chain even
    # though it is pure L2 and is never routed by this host. The policy here is
    # ACCEPT and docker's drops live in its own chains, so this is insurance
    # rather than a fix for an observed break — but with docker and libvirt both
    # inserting into FORWARD, intra-bridge traffic should not depend on their
    # chains happening to RETURN.
    #
    # Clearing the sysctl would also fix it, and would break docker's own
    # networking, so accept exactly the intra-bridge case instead.
    #
    # Yes, this is host netfilter, which the header of this file argues against.
    # The distinction that makes it acceptable: the old marking rule's ABSENCE
    # caused a leak, so every firewall reload was a security event. This rule's
    # absence causes a DROP — the workstation loses connectivity and fails shut.
    # Losing it costs function, not anonymity, which is the safe direction.
    networking.firewall = {
      extraCommands = ''
        iptables -C FORWARD -i ${cfg.workstation.bridge} -o ${cfg.workstation.bridge} -j ACCEPT 2>/dev/null \
          || iptables -I FORWARD -i ${cfg.workstation.bridge} -o ${cfg.workstation.bridge} -j ACCEPT
      '';
      extraStopCommands = ''
        iptables -D FORWARD -i ${cfg.workstation.bridge} -o ${cfg.workstation.bridge} -j ACCEPT 2>/dev/null || true
      '';

      # Loose, not strict, reverse-path filtering. The enforced path is asymmetric:
      # replies return on the tap carrying public sources whose reverse route is the
      # WAN, so strict rpfilter silently drops every TCP reply (DNS still passes, which
      # makes the gateway look healthy). Loose still drops martian sources.
      checkReversePath = "loose";
    };

    users.users.anon-user = {
      inherit (cfg) uid;
      isSystemUser = true;
      group = "nogroup";
      description = "Policy-selector UID for anonymous-mode workloads";
    };

    environment.systemPackages = [
      anonExec
      anonSelftest
      anonShell
      # On PATH deliberately: when the workstation misbehaves, being able to
      # open a raw channel to it by hand is the difference between diagnosing
      # the guest and guessing about it.
      anonVsock
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

            # DELIBERATELY NO ExecStop: nothing may release the jail. A rebuild stops a
            # changed unit before restarting it, so an ExecStop teardown left the uid unjailed
            # for ~3 s on every `make switch`. jailUp is idempotent; a restart re-asserts.
            # To remove the rules, reboot or delete them by hand.
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
            ExecStart = lib.getExe (
              pkgs.writeShellApplication {
                name = "anon-check";
                runtimeInputs = [ pkgs.coreutils ];
                bashOptions = [ ];
                text = ''
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
                  for _ in $(seq 1 30); do
                    if ${probeSocks}; then
                      listening=1
                      break
                    fi
                    sleep 1
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
                  deadline=$(( $(date +%s) + ${toString cfg.bootstrapTimeout} ))
                  bootstrapped=0
                  while [ "$(date +%s)" -lt "$deadline" ]; do
                    if ${socksRequest 20}; then
                      bootstrapped=1
                      break
                    fi
                    echo "L3 waiting: tor is listening but not yet carrying traffic..."
                    sleep 5
                  done
                  if [ "$bootstrapped" != 1 ]; then
                    echo "L3 FAIL: tor still cannot carry a request after ${toString cfg.bootstrapTimeout}s." >&2
                    echo "         check guest egress (tap masquerade), then the guest journal:" >&2
                    echo "         sudo journalctl -D ${cfg.guestJournalDir} -u tor" >&2
                    fail
                  fi
                  echo "L3 ok: tor is bootstrapped (SOCKS request completed)"

                  # L4 — identity, jail integrity, then a leak-proof exit check
                  # (see pathProbe: none of its assertions can reach the clearnet).
                  exit_ip=""
                  for _ in 1 2 3; do
                    exit_ip=$(${pathProbe}) && break
                    exit_ip=""
                    sleep 5
                  done
                  if [ -z "$exit_ip" ]; then
                    echo "L4 FAIL: the enforced path is not verifiably Tor'd (detail above)." >&2
                    fail
                  fi
                  mkdir -p "$(dirname ${cfg.readyStamp})"
                  printf 'verified=%s exit=%s\n' \
                    "$(date -Is)" "$exit_ip" > ${cfg.readyStamp}
                  echo "L4 ok: enforced path verified — Tor exit $exit_ip"
                  echo "anonymous mode armed. Prove the negative paths with: sudo anon-selftest"
                '';
              }
            );
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

        # THE WORKSTATION'S GATE. `wants` on the target starts anon-box but
        # orders nothing, so without this the guest races the readiness ladder
        # and can be up — and enterable — before the path is proven. Readiness
        # gates release here exactly as it does for anon-exec.
        #
        # PartOf is what makes disarm reach it: anon-watch's seal path stops
        # anonymous.target, and that must take the workstation down with it
        # rather than leaving a VM running on a path just declared unsafe.
        # Its root is tmpfs, so there is nothing to clean up afterwards.
        "microvm@anon-box" = {
          requires = [ "anon-check.service" ];
          after = [ "anon-check.service" ];
          partOf = [ "anonymous.target" ];
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
            ExecStart = lib.getExe (
              pkgs.writeShellApplication {
                name = "anon-watch";
                runtimeInputs = [ pkgs.coreutils ];
                bashOptions = [ ];
                text = ''
                  armed=0
                  [ -e ${cfg.readyStamp} ] && armed=1

                  # Re-assert the jail first: it is the fail-closed boundary, so
                  # anything that removed it (a link reconfiguration, a manual
                  # flush) gets corrected before the path is judged, not after.
                  #
                  # And CHECK that it worked: a jail that cannot be asserted is not a
                  # jail, and while armed that is a sealing condition like any other.
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
                  sleep 10
                  if verified; then
                    echo "anonymous path recovered after one failed check." >&2
                    exit 0
                  fi

                  # Classify before acting, so the journal says which layer broke.
                  if ! ${probeSocks}; then
                    echo "gateway down: nothing listening at ${socks}." >&2
                  elif ${socksRequest 30}; then
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
              }
            );
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
        wants = [
          "microvm@net-gate.service"
          "microvm@anon-box.service"
        ];
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

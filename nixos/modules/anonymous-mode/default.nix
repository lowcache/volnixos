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
  imports = [
    ./options.nix
    ./guests.nix
  ];

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

    # By default networkd reaps routes/rules it didn't create on every link
    # reconfigure, and the net-gate tap is recreated on each VM restart: that
    # removed the jail's uidrange rule. Host-wide, and right for tailscale,
    # libvirt and docker routes too.
    systemd.network.config.networkConfig = {
      ManageForeignRoutes = false;
      ManageForeignRoutingPolicyRules = false;
    };

    # Bridged frames traverse the host FORWARD chain (docker loads br_netfilter,
    # bridge-nf-call-iptables=1), so accept the intra-bridge case explicitly
    # rather than depend on docker/libvirt chains RETURNing. Clearing the sysctl
    # would break docker. Host netfilter is acceptable HERE because losing this
    # rule fails shut (workstation loses connectivity), unlike the old marking rule.
    networking.firewall = {
      extraCommands = ''
        iptables -C FORWARD -i ${cfg.workstation.bridge} -o ${cfg.workstation.bridge} -j ACCEPT 2>/dev/null \
          || iptables -I FORWARD -i ${cfg.workstation.bridge} -o ${cfg.workstation.bridge} -j ACCEPT
      '';
      extraStopCommands = ''
        iptables -D FORWARD -i ${cfg.workstation.bridge} -o ${cfg.workstation.bridge} -j ACCEPT 2>/dev/null || true
      '';

      # The enforced path is asymmetric (replies on the tap carry public sources
      # routed via the WAN), so strict rpfilter drops every TCP reply while DNS
      # passes. Loose still drops martians.
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
      # Raw channel to the workstation, for diagnosing it by hand.
      anonVsock
    ];

    # Every workload lands in anon.slice, so disarming stops the whole tree at once.
    systemd = {
      slices.anon = {
        description = "Anonymous-mode workloads (uid ${toString cfg.uid})";
        sliceConfig = {
          TasksMax = 4096;
          # Inherited by every unit in the slice, not only anon-exec workloads:
          # closes the path to the host's stub resolver.
          IPAddressDeny = "localhost";
        };
      };

      services = {
        # THE JAIL. Armed at boot, partOf nothing, never released automatically:
        # the uid must have no clearnet before arming, after disarming, and while
        # anon-routing restarts. The routing policy is the boundary, not ordering.
        anon-jail = {
          description = "Fail-closed routing jail for anonymous-mode uid ${toString cfg.uid}";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = jailUp;

            # DELIBERATELY NO ExecStop: a rebuild stops changed units first, which left
            # the uid unjailed for ~3 s per switch. jailUp is idempotent.
          };
        };

        # Arming: replace the blackhole default with the gateway. `src` pins the
        # source so the guest matches by address and selection can't drift to the WAN.
        anon-routing = {
          description = "Point the anon jail's default route at the net-gate Tor VM";
          requires = [ "anon-jail.service" ];
          after = [
            "anon-jail.service"
            "microvm@net-gate.service"
          ];
          # partOf the VM too: the kernel drops the route with the tap, and without
          # this the unit would stay "active" over a route that no longer exists.
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

        # The readiness ladder (see header). Only L4 writes the stamp that releases
        # workloads; a TCP handshake passes on a tor that cannot build circuits.
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
            # Worst case, not a guess: L2 30x(2s+1s)=90s; L3 bootstrapTimeout plus one
            # overrun (20s+5s); L4 3x(30s+5s)=105s. A timeout would hide the real state.
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

        # Resets UNIT STATE after a failed arm. anon-check's fail() already pulled
        # the route, but anon-routing (RemainAfterExit) stays "active", so the next
        # arm would never reinstall it and every retry would fail at L4. Stopping it
        # cascades (Requires=) through anon-check and the target: a clean retry.
        anon-seal = {
          description = "Reset anon-routing after a failed arm so retries start clean";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${systemctl} stop anon-routing.service";
          };
        };

        # The workstation's gate: without the ordering it races the ladder and is
        # enterable before the path is proven. PartOf lets a seal take it down.
        "microvm@anon-box" = {
          requires = [ "anon-check.service" ];
          after = [ "anon-check.service" ];
          partOf = [ "anonymous.target" ];
        };

        # Disarming also stops what was using the tunnel.
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

        # PATH liveness, not process liveness: re-runs L4 and seals on confirmed loss.
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

      # requires, so failed verification fails the target. net-gate is only wanted:
      # it stays up after disarm for the SOCKS interface (tor-curl, tor-brave).
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

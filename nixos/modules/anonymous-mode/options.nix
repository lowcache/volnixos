# vol.anon-mode options. Addressing is consumed by nixos/vms.nix and home/scripts.nix too.
{ lib, ... }:
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
        failed at 45s while tor was still bootstrapping — a race
        in the gate, not a fault in the path. With persistTorState = true later
        arms reuse the consensus and are quick.
      '';
    };

    probeAddress = lib.mkOption {
      type = lib.types.str;
      default = "1.1.1.1";
      description = ''
        Off-subnet address for the packet-free jail check (`ip route get <addr>`,
        run from inside the jail). Never connected to; it only has to be
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
        all. Without it the VM is a black box after boot: its tor.service died once
        and the host had no way to see why for four days.

        Scope is deliberately the mechanism, not the activity: Tor's SafeLogging
        stays on and the log level stays at notice, which records bootstrap
        progress, circuit failures, restarts and resource problems — not
        destinations or connection histories.
      '';
    };

    guestJournalDir = lib.mkOption {
      type = lib.types.str;
      default = "/persist/var/log/net-gate-journal";
      description = "Host directory holding net-gate's persisted journal (read with `journalctl -D`).";
    };

    # WORKSTATION (anon-box). Addressing lives here, not in nixos/vms.nix, for
    # the same reason the gateway's does: three files consume it and a drifted
    # copy does not fail loudly, it quietly stops anonymising something.
    workstation = {

      address = lib.mkOption {
        type = lib.types.str;
        default = "192.168.102.2";
        description = "anon-box's address on the workstation segment. The gateway's nat rules match anonymous traffic by this source.";
      };

      gatewayAddress = lib.mkOption {
        type = lib.types.str;
        default = "192.168.102.1";
        description = ''
          net-gate's inner-leg address — anon-box's only route off its segment,
          and its only resolver. The host deliberately holds no address here.
        '';
      };

      bridge = lib.mkOption {
        type = lib.types.str;
        default = "br-anon";
        description = ''
          Host bridge joining net-gate's inner leg to the workstation. The host
          holds no address on it; it exists only so the two guests share an L2
          segment without the host being a hop between them.
        '';
      };

      vsockCid = lib.mkOption {
        type = lib.types.int;
        default = 12;
        description = ''
          anon-box's vsock context ID. The host reaches the workstation ONLY
          over vsock: it has no address on the workstation bridge, which is the
          isolation property, so vsock is the channel that does not spend it.
          CIDs 10 and 11 belong to net-gate and the tailscale guest.
        '';
      };

      shellPort = lib.mkOption {
        type = lib.types.int;
        default = 1024;
        description = "vsock port serving the interactive shell that anon-shell attaches to.";
      };

      verifyPort = lib.mkOption {
        type = lib.types.int;
        default = 1025;
        description = ''
          vsock port serving the L5 path check. Separate from shellPort so
          verification is a non-interactive request with a parseable answer
          rather than something scraped out of a terminal.
        '';
      };
    };
  };
}

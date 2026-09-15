{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:
let
  # net-gate addressing comes from vol.anon-mode (nixos/modules/anonymous-mode.nix)
  # so the host jail, this guest, and the home-manager tor wrappers cannot drift
  # apart. Previously the same three literals appeared in all three places.
  #
  # NOTE: `config` in this file is the HOST config. Inside microvm.vms.<name>.config
  # the guest has its own module scope, but a bare `config.` reference written
  # there still resolves to this host binding — use let-bound values like `anon`
  # instead of reaching into `config` from a guest block.
  anon = config.vol.anon-mode;
  netgatePrefix = lib.last (lib.splitString "/" anon.torVmSubnet);

  # The host's WAN, named here because the net-gate masquerade must be scoped to
  # one source address and systemd-networkd's IPMasquerade cannot express that.
  # If this stops matching the real uplink the guest loses egress and anonymous
  # mode fails to arm — which is the safe direction for it to be wrong in.
  wanInterface = "wlp4s0";
in
{

  # MicroVM Host Configuration
  imports = [
    inputs.microvm.nixosModules.host
  ];

  # Tor's egress, and NOTHING else on the net-gate link. The guest's address is
  # masqueraded so tor can reach its guards; the host's own tap address is not,
  # so a workload packet the guest failed to redirect finds no NAT, leaves with
  # an unroutable private source, and dies. Previously IPMasquerade covered the
  # whole ${anon.torVmSubnet} and could not tell those two cases apart, which
  # turned every guest-side miss into an egress with the host's real address.
  networking.nat = {
    enable = true;
    externalInterface = wanInterface;
    internalIPs = [ "${anon.torVmAddress}/32" ];
  };

  microvm.vms.net-gate = {
    autostart = true;
    config = {
      # Use the same inputs
      _module.args.inputs = inputs;

      imports = [
        inputs.microvm.nixosModules.microvm
        inputs.sops-nix.nixosModules.sops
      ];

      networking = {
        hostName = "net-gate";
        useNetworkd = true;
        firewall = {
          enable = true;
          # nat rewrites the destination port before filter/INPUT runs, so these
          # are the ports the redirected packets actually arrive on. The single
          # NIC faces the host tap, so an interface-scoped rule adds nothing.
          allowedTCPPorts = [
            anon.socksPort
            anon.transPort
          ];
          allowedUDPPorts = [ anon.dnsPort ];

          # TRANSPARENT PROXY — the enforcement boundary. Traffic from the host's
          # anon jail arrives with src = the tap address (pinned by `src` on the
          # jail's gateway route), so we match on that rather than guessing this
          # guest's interface name.
          #
          # Order matters. DNS first, so queries aimed at this guest itself (the
          # workload's resolv.conf points here) are bent into Tor's DNSPort
          # before the in-subnet RETURN can exempt them. Then RETURN for the rest
          # of the subnet, so the SOCKS interface stays directly usable. Then
          # every remaining TCP flow into Tor's TransPort.
          #
          # Nothing enables ip_forward here, and that is deliberate: REDIRECT
          # makes a packet local before the forwarding decision, so anything the
          # rules do NOT rewrite — UDP other than :53, ICMP, anything Tor cannot
          # carry — is dropped rather than forwarded. Fails shut, including QUIC.
          extraCommands = ''
            # Backstop for the "must not route" invariant above: anything that
            # reaches the forwarding path instead of tor dies here.
            iptables -A FORWARD -j DROP
            iptables -t nat -A PREROUTING -s ${anon.tapAddress} -p udp --dport 53 \
              -j REDIRECT --to-ports ${toString anon.dnsPort}
            iptables -t nat -A PREROUTING -s ${anon.tapAddress} -d ${anon.torVmSubnet} -j RETURN
            iptables -t nat -A PREROUTING -s ${anon.tapAddress} -p tcp \
              -j REDIRECT --to-ports ${toString anon.transPort}
          '';
          extraStopCommands = ''
            iptables -D FORWARD -j DROP 2>/dev/null || true
            iptables -t nat -D PREROUTING -s ${anon.tapAddress} -p udp --dport 53 \
              -j REDIRECT --to-ports ${toString anon.dnsPort} 2>/dev/null || true
            iptables -t nat -D PREROUTING -s ${anon.tapAddress} -d ${anon.torVmSubnet} -j RETURN 2>/dev/null || true
            iptables -t nat -D PREROUTING -s ${anon.tapAddress} -p tcp \
              -j REDIRECT --to-ports ${toString anon.transPort} 2>/dev/null || true
          '';
        };
      };

      systemd = {
        network = {
          enable = true;
          networks."10-lan" = {
            matchConfig.Name = "en* eth*";
            networkConfig = {
              Address = [ "${anon.torVmAddress}/${netgatePrefix}" ];
              Gateway = anon.tapAddress;
              DNS = [ anon.tapAddress ];
            };
          };
        };
        services = {
          tor.serviceConfig.TimeoutStopSec = "2s";
        };
      };

      microvm = {
        hypervisor = "cloud-hypervisor";
        mem = 512;
        vcpu = 1;
        #cloud-hypervisor supports systemd-notify via vsock, but `microvm.vsock.cid` must be set to enable this.
        vsock.cid = 10;
        interfaces = [
          {
            type = "tap";
            id = anon.tapInterface;
            mac = "02:00:00:00:00:01";
          }
        ];
        shares = [
          {
            source = "/persist/etc/ssh";
            mountPoint = "/etc/ssh";
            tag = "ssh-keys";
            proto = "virtiofs";
          }
        ]
        ++ lib.optional anon.persistTorState {
          # Tor's DataDirectory (StateDirectory=tor). The guest root is tmpfs, so
          # without this the consensus is re-fetched and entry guards re-chosen on
          # every start: slow arming, and guard churn is an anonymity loss in its
          # own right. Trade-off (and the reason this is an option) is documented
          # on vol.anon-mode.persistTorState. The host dir comes from tmpfiles
          # below; tor.service chowns the mountpoint from inside the guest.
          source = "/persist/var/lib/net-gate-tor";
          mountPoint = "/var/lib/tor";
          tag = "tor-state";
          proto = "virtiofs";
        }
        ++ lib.optional anon.persistGuestJournal {
          # Guest journal. journald's Storage=auto turns persistent the moment
          # /var/log/journal exists, so mounting this is the whole mechanism.
          # Without it the VM is a black box after boot — which is why a dead
          # tor.service went unnoticed for four days.
          source = "/persist/var/log/net-gate-journal";
          mountPoint = "/var/log/journal";
          tag = "journal";
          proto = "virtiofs";
        };
      };

      # Fix Entropy and VSOCK early load
      boot.kernelParams = [ "random.trust_cpu=on" ];

      # This guest TERMINATES traffic into tor; it must never route it. Nothing
      # here enables forwarding, but "nothing enables it" is a property of the
      # current config rather than a stated invariant — and if forwarding were
      # ever on, a packet the nat rules failed to redirect would be forwarded
      # back to the host, masqueraded out the WAN, and leave with the host's real
      # address instead of failing shut. Say it explicitly, and back it with a
      # FORWARD drop so the invariant does not depend on a sysctl default.
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 0;
        "net.ipv4.conf.all.forwarding" = 0;
        "net.ipv6.conf.all.forwarding" = 0;
      };

      # Tor anonymity layer: one SOCKS5 listener, bound to the tap address.
      #
      # The listener comes from client.socksListenAddress, NOT settings.SOCKSPort.
      # client.enable emits its own `SOCKSPort 127.0.0.1:9050 IsolateDestAddr`
      # from that option, so a hand-rolled second SOCKSPort on the same port made
      # torrc carry two listeners on 9050 and tor died at startup on the second
      # bind (listener bind failures are fatal). ExecStartPre --verify-config does
      # not bind, so it passed and the only symptom was a refused connection from
      # the host — which the wrappers misreported as "arm it with anon-on".
      services.tor = {
        enable = true;
        client = {
          enable = true;
          # IsolateDestAddr = one circuit per destination. It is the option's
          # default and was silently lost while the listener was hand-rolled.
          socksListenAddress = {
            addr = anon.torVmAddress;
            port = anon.socksPort;
            IsolateDestAddr = true;
          };
        };
        settings = {
          # OPT-IN proxy, not a transparent enforcer. Host traffic is Tor'd only
          # through the proxy (anon-run / tor-curl / tor-brave) or the uid jail
          # in nixos/modules/anonymous-mode.nix:
          #   curl --socks5-hostname 192.168.100.2:9050 https://example.com
          #   sudo systemctl start anonymous.target
          #
          # TransPort/DNSPort carry the ENFORCED path (see the nat rules above).
          # Declared here rather than via client.transparentProxy.enable /
          # client.dns.enable: those emit listeners on 127.0.0.1, and because
          # these settings are list-typed they MERGE rather than override — which
          # is exactly how the duplicate SOCKSPort that killed tor was created.
          TransPort = [
            {
              addr = anon.torVmAddress;
              port = anon.transPort;
              # Every transparent flow reaches tor from the same client address,
              # so tor's default IsolateClientAddr separates nothing here. Per
              # destination is the isolation actually available on this path; the
              # finer per-invocation isolation stays a SOCKS-interface property
              # (anon-run/tor-curl pass throwaway credentials).
              IsolateDestAddr = true;
            }
          ];
          DNSPort = [
            {
              addr = anon.torVmAddress;
              port = anon.dnsPort;
            }
          ];
          # Keep tor's own logging about the mechanism (bootstrap, circuits,
          # restarts) while scrubbing addresses out of it: we observe the privacy
          # machinery, not the user's destinations. This is tor's default; it is
          # spelled out because the guest journal is now persisted.
          SafeLogging = true;
          # Automapped hostnames get an address out of this range, and the
          # workload then CONNECTS to it. So the range must not contain any
          # address the host answers for: `ip rule` consults the `local` table at
          # priority 0, ahead of the jail's uidrange rule (priority 100), and a
          # destination that is a local address never reaches the jail's table
          # at all. The connection would go to this host instead of through tor,
          # with the routing table still looking entirely correct — the exact
          # "kernel says tor, the web says otherwise" signature.
          #
          # 172.16.0.0/12 was wrong here: this host's WAN is 172.16.32.111/22 and
          # docker0 is 172.17.0.1/16, both inside it. 10.192.0.0/10 is the
          # conventional range for transparent-proxy setups and collides with
          # nothing this host holds (its 10-net address is 10.187.3.118/24, below
          # the /10). Re-check this if the host's addressing changes.
          VirtualAddrNetworkIPv4 = "10.192.0.0/10";
          AutomapHostsOnResolve = true;
          # No IPv6 uplink on this host: don't spend circuit-build attempts on
          # v6 ORPorts that cannot be reached.
          ClientUseIPv6 = false;
        };
      };

      # Sops Configuration
      sops = {
        defaultSopsFile = ./vm-secrets.yaml; # Relative to THIS file (nixos/vms.nix)
        age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
        # secrets.wg_private_key = {}; # Commented until added to vm-secrets.yaml
      };

      environment.systemPackages = [ pkgs.ssh-to-age ];
      # networking.wg-quick.interfaces.wg0 = {
      #   address = [ "10.0.0.2/32" ];
      #   privateKeyFile = config.sops.secrets.wg_private_key.path;
      #   peers = [
      #     {
      #       publicKey = "REPLACE_WITH_YOUR_VPN_PUBLIC_KEY";
      #       allowedIPs = [ "0.0.0.0/0" ];
      #       endpoint = "REPLACE_WITH_YOUR_VPN_ENDPOINT:51820";
      #       persistentKeepalive = 25;
      #     }
      #   ];
      # };

      system.stateVersion = "24.11";
    };
  };

  microvm.vms.tailscale = {
    autostart = true;
    config = {
      _module.args.inputs = inputs;

      imports = [
        inputs.microvm.nixosModules.microvm
        inputs.sops-nix.nixosModules.sops
      ];

      networking = {
        hostName = "tailscale";
        useNetworkd = true;
        firewall = {
          enable = true;
          allowedUDPPorts = [ 41641 ];
        };
      };

      systemd = {
        network = {
          enable = true;
          networks."10-lan" = {
            matchConfig.Name = "en* eth*";
            networkConfig = {
              Address = [ "192.168.101.2/24" ];
              Gateway = "192.168.101.1";
              DNS = [ "192.168.101.1" ];
            };
          };
        };
      };

      microvm = {
        hypervisor = "cloud-hypervisor";
        mem = 256;
        vcpu = 1;
        vsock.cid = 11;
        interfaces = [
          {
            type = "tap";
            id = "vm-tailscale";
            mac = "02:00:00:00:00:02";
          }
        ];
        shares = [
          {
            source = "/persist/var/lib/tailscale-vm";
            mountPoint = "/var/lib/tailscale";
            tag = "tailscale-state";
            proto = "virtiofs";
          }
        ];
      };

      boot.kernelParams = [ "random.trust_cpu=on" ];

      services.tailscale = {
        enable = true;
        useRoutingFeatures = "both";
        # Auto-join the tailnet on boot from a key placed in the persisted
        # state share (host path: /persist/var/lib/tailscale-vm/authkey → guest
        # /var/lib/tailscale/authkey). No guest console needed for first auth.
        authKeyFile = "/var/lib/tailscale/authkey";
        # Advertise as an exit node so tailscaled installs the forward/accept
        # rules that let the guest route non-tailscale traffic (from the host
        # tap) out over tailscale0. Admin approval not required for the local
        # rules to be installed.
        extraUpFlags = [ "--advertise-exit-node" ];
      };

      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };

      # SNAT host-originated traffic (192.168.101.0/24, arriving on the host
      # tap) onto this node's tailnet IP so tailnet peers route replies back
      # to the VM. Lets the volnix host reach 100.x peers via a host route
      # through 192.168.101.2 without itself being a tailnet node.
      networking.nat = {
        enable = true;
        externalInterface = "tailscale0";
        internalIPs = [ "192.168.101.0/24" ];
        # Publish the volnix host's Ollama to the tailnet: DNAT inbound
        # tailscale0 :11434 (100.66.249.117) → the host at 192.168.101.1:11434.
        # Return path reuses the host's existing 100.64.0.0/10 route via this
        # guest, so conntrack un-DNATs the replies. Unblocks phone voice.ask
        # source=laptop and the Phase-7 laptop_required scheduler tasks.
        #
        # Same shape for :8463, the phone-agent push server (phone-agent.pushPort):
        # the phone pulls files from the laptop over this, so laptop→phone
        # transfer stays phone-initiated and needs no inbound listener there.
        forwardPorts = [
          {
            proto = "tcp";
            sourcePort = 11434;
            destination = "192.168.101.1:11434";
          }
          {
            proto = "tcp";
            sourcePort = 8463;
            destination = "192.168.101.1:8463";
          }
        ];
      };

      system.stateVersion = "24.11";
    };
  };

  # Host-side overrides for fast shutdown
  systemd = {
    # Backing dirs for the net-gate shares. virtiofsd refuses to start if a
    # source is missing, and tmpfiles (sysinit.target) runs well before the
    # microvm units in multi-user.target.
    tmpfiles.rules =
      lib.optional anon.persistTorState "d /persist/var/lib/net-gate-tor 0700 root root -"
      ++ lib.optional anon.persistGuestJournal "d /persist/var/log/net-gate-journal 0700 root root -";
    services = {
      "microvm@net-gate".serviceConfig.TimeoutStopSec = "10s";
      "microvm-virtiofsd@net-gate" = {
        serviceConfig = {
          Type = lib.mkForce "simple";
          TimeoutStopSec = "5s";
        };
      };
      "microvm@tailscale".serviceConfig.TimeoutStopSec = "10s";
      "microvm-virtiofsd@tailscale" = {
        serviceConfig = {
          Type = lib.mkForce "simple";
          TimeoutStopSec = "5s";
        };
      };
    };
    network = {
      enable = true;
      wait-online.enable = false;
      networks."10-microvm-tap" = {
        matchConfig.Name = anon.tapInterface;
        networkConfig = {
          Address = [ "${anon.tapAddress}/${netgatePrefix}" ];
          IPv4Forwarding = true;
          # Deliberately NO IPMasquerade: it SNATs the entire subnet, and cannot
          # distinguish tor's own egress (src ${anon.torVmAddress}) from a workload
          # packet the guest failed to redirect (src ${anon.tapAddress}). The
          # narrow replacement lives in networking.nat at the top of this file.
        };
        # Ensure this network doesn't become the default route for the host
        linkConfig.RequiredForOnline = "no";
      };
      networks."11-tailscale-tap" = {
        matchConfig.Name = "vm-tailscale";
        networkConfig = {
          Address = [ "192.168.101.1/24" ];
          IPv4Forwarding = true;
          # SNAT the guest's traffic out the host WAN so tailscaled can reach
          # the coordination server (and DERP) to authenticate. Without this
          # the guest forwards but leaves with src 192.168.101.2 and gets no
          # return path — same idiom the android VM tap uses.
          IPMasquerade = "both";
        };
        # Host route to the tailnet CIDR via the guest; pairs with the
        # guest-side SNAT onto tailscale0 (see networking.nat in the VM).
        routes = [
          {
            Destination = "100.64.0.0/10";
            Gateway = "192.168.101.2";
          }
        ];
        # Ensure this network doesn't become the default route for the host
        linkConfig.RequiredForOnline = "no";
      };
    };
  };
  # Host-side networking to communicate with the VM
  # We use systemd-networkd BUT we must ensure it doesn't touch your main interfaces

  # Tell NetworkManager to ignore the VM taps so it doesn't try to manage them
  networking.networkmanager.unmanaged = [
    "interface-name:${anon.tapInterface}"
    "interface-name:vm-tailscale"
  ];
}

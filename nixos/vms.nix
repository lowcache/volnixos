{
  config,
  pkgs,
  inputs,
  lib,
  username,
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

  # WORKSTATION LEG (anon-box). net-gate becomes two-legged: its existing NIC
  # faces the host tap, and this one faces a bridge shared only with the
  # workstation guest.
  #
  # The host holds NO address on anonBridge. That is the point of the topology,
  # not an oversight: host and workstation share no L3, the host is not in the
  # data path, and it cannot reach the workstation over IP. anon-shell therefore
  # enters over vsock rather than ssh-over-network, which is why anonBoxCid
  # exists.
  #
  # cloud-hypervisor accepts only `tap` and `macvtap` interfaces — a
  # `type = "bridge"` interface throws at eval — so both sides attach as plain
  # taps and the HOST enslaves them (see the 2x-br-anon networks below).
  anonBridge = "br-anon";
  anonInnerTap = "vm-ngi";
  anonBoxTap = "vm-anonbox";
  # Addressing comes from vol.anon-mode.workstation, not from literals here —
  # the module, this file and anon-shell all consume it.
  anonInnerAddr = anon.workstation.gatewayAddress;
  anonBoxAddr = anon.workstation.address;
  anonBoxSubnet = "192.168.102.0/24";
  anonBoxPrefix = "24";
  # MACs :01 and :02 are taken by net-gate and the tailscale guest. Interfaces
  # are matched BY MAC rather than by name: net-gate's networks used to match
  # `en* eth*`, which with a second NIC matches both and misconfigures the inner
  # leg.
  netgateOuterMac = "02:00:00:00:00:01";
  netgateInnerMac = "02:00:00:00:00:03";
  anonBoxMac = "02:00:00:00:00:04";
  # vsock CIDs 10 and 11 are net-gate and tailscale.
  anonBoxCid = anon.workstation.vsockCid;

  # net-gate's transparent-proxy rules for one client; `tail` makes the stop variant tolerant.
  clientRules = op: tail: src: subnet: ''
    iptables -t nat -${op} PREROUTING -s ${src} -p udp --dport 53 \
      -j REDIRECT --to-ports ${toString anon.dnsPort}${tail}
    iptables -t nat -${op} PREROUTING -s ${src} -d ${subnet} -j RETURN${tail}
    iptables -t nat -${op} PREROUTING -s ${src} -p tcp \
      -j REDIRECT --to-ports ${toString anon.transPort}${tail}
  '';

  # Shared by every guest below.
  guestBase = {
    _module.args.inputs = inputs;
    imports = [ inputs.microvm.nixosModules.microvm ];
    networking = {
      useNetworkd = true;
      firewall.enable = true;
    };
    systemd.network.enable = true;
    microvm.hypervisor = "cloud-hypervisor";
    system.stateVersion = "24.11";
  };
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

  microvm.vms = {
    net-gate = {
      autostart = true;
      config = {
        imports = [
          guestBase
          inputs.sops-nix.nixosModules.sops
        ];
        # Fix entropy and vsock early load; kept per guest so it follows microvm's params.
        boot.kernelParams = [ "random.trust_cpu=on" ];

        networking = {
          hostName = "net-gate";
          firewall = {
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
            #
            # TWO CLIENTS, ONE DEFINITION. This gateway now serves the host's uid
            # jail (src ${anon.tapAddress}) and the anon-box workstation (src
            # ${anonBoxAddr}). They get byte-identical treatment because the rules
            # are generated from one function rather than maintained as two copies
            # that can drift — and a drifted copy here does not fail loudly, it
            # quietly stops anonymising one of the two.
            extraCommands = ''
              # Backstop for the "must not route" invariant above: anything that
              # reaches the forwarding path instead of tor dies here. With two
              # legs this stops being belt-and-braces and becomes the mechanism
              # preventing the workstation from being routed out the WAN.
              iptables -A FORWARD -j DROP
            ''
            + clientRules "A" "" anon.tapAddress anon.torVmSubnet
            + clientRules "A" "" anonBoxAddr anonBoxSubnet;

            extraStopCommands = ''
              iptables -D FORWARD -j DROP 2>/dev/null || true
            ''
            + clientRules "D" " 2>/dev/null || true" anon.tapAddress anon.torVmSubnet
            + clientRules "D" " 2>/dev/null || true" anonBoxAddr anonBoxSubnet;
          };
        };

        systemd = {
          network = {
            # MATCHED BY MAC, NOT BY NAME. This used to be `Name = "en* eth*"`,
            # which was correct while the guest had one NIC and silently wrong the
            # moment it grew a second: the glob matches both, and networkd would
            # put the outer address on whichever appeared first.
            networks."10-lan" = {
              matchConfig.MACAddress = netgateOuterMac;
              networkConfig = {
                Address = [ "${anon.torVmAddress}/${netgatePrefix}" ];
                Gateway = anon.tapAddress;
                DNS = [ anon.tapAddress ];
              };
            };
            # Inner leg, facing the workstation. Deliberately NO Gateway: the
            # default route stays out the host tap, which is this guest's path to
            # its guards. A gateway here would make the workstation a candidate
            # next hop for tor's own egress.
            networks."11-inner" = {
              matchConfig.MACAddress = netgateInnerMac;
              networkConfig = {
                Address = [ "${anonInnerAddr}/${anonBoxPrefix}" ];
              };
              linkConfig.RequiredForOnline = "no";
            };
          };
          services = {
            tor.serviceConfig.TimeoutStopSec = "2s";
          };
        };

        microvm = {
          mem = 512;
          vcpu = 1;
          #cloud-hypervisor supports systemd-notify via vsock, but `microvm.vsock.cid` must be set to enable this.
          vsock.cid = 10;
          interfaces = [
            {
              type = "tap";
              id = anon.tapInterface;
              mac = netgateOuterMac;
            }
            # Inner leg. A plain tap: the host enslaves it to ${anonBridge},
            # because cloud-hypervisor rejects `type = "bridge"` outright.
            {
              type = "tap";
              id = anonInnerTap;
              mac = netgateInnerMac;
            }
          ];
          shares = [
            {
              # net-gate's own key (net-gate-ssh-key below), never the host's:
              # the Tor-facing guest must not hold a key that opens host-secrets.
              source = "/persist/var/lib/net-gate-ssh";
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
            source = anon.guestJournalDir;
            mountPoint = "/var/log/journal";
            tag = "journal";
            proto = "virtiofs";
          };
        };

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
        # The listener comes from client.socksListenAddress, NOT settings.SOCKSPort:
        # client.enable already emits a SOCKSPort, and a second one on the same port
        # kills tor at startup (listener bind failures are fatal).
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
            # ONE LISTENER PER LEG, AND THIS IS NOT OPTIONAL.
            #
            # iptables REDIRECT rewrites the destination to the primary address of
            # the interface the packet ARRIVED on. Host-jail traffic arrives on the
            # outer leg and lands on ${anon.torVmAddress}; workstation traffic
            # arrives on the inner leg and lands on ${anonInnerAddr}. A listener
            # bound only to the outer address therefore serves the host and
            # silently blackholes the workstation — the redirect still fires, it
            # just points at a port nobody is on.
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
              {
                addr = anonInnerAddr;
                port = anon.transPort;
                IsolateDestAddr = true;
              }
            ];
            DNSPort = [
              {
                addr = anon.torVmAddress;
                port = anon.dnsPort;
              }
              {
                addr = anonInnerAddr;
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
            # 172.16.0.0/12 collides with this host's WAN and docker0; 10.192.0.0/10 collides
            # with nothing it holds. Re-check if the host's addressing changes.
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

      };
    };

    tailscale = {
      autostart = true;
      config = {
        imports = [
          guestBase
          inputs.sops-nix.nixosModules.sops
        ];
        # Fix entropy and vsock early load; kept per guest so it follows microvm's params.
        boot.kernelParams = [ "random.trust_cpu=on" ];

        networking = {
          hostName = "tailscale";
          firewall = {
            allowedUDPPorts = [ 41641 ];
          };
        };

        systemd = {
          network = {
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

      };
    };

    # THE ANONYMITY WORKSTATION.
    #
    # What this buys over `anon-run`: a kernel boundary instead of a uid boundary.
    # The uid jail enforces egress well — an application that ignores every proxy
    # variable still cannot reach the clearnet — but the workload runs on the host
    # kernel, as a host uid, with the host filesystem in reach. A kernel bug or a
    # privilege escalation escapes all of it at once. Here the workload is a
    # different machine.
    #
    # The gateway/workstation split is the point: the workload never runs on the
    # machine that terminates tor. Compromise this guest and you still cannot read
    # the guard set, rewrite torrc, or learn the host's WAN address.
    #
    # autostart = false. It is started by anonymous.target, AFTER the readiness
    # ladder has proven the path — see nixos/modules/anonymous-mode.nix. A
    # workstation that boots before the gateway is verified is a workstation you
    # will use before the gateway is verified.
    anon-box = {
      autostart = false;
      config = {
        imports = [ guestBase ];
        # Fix entropy and vsock early load; kept per guest so it follows microvm's params.
        boot.kernelParams = [ "random.trust_cpu=on" ];

        networking = {
          hostName = "anon-box";
          # Resolution goes to the gateway's inner leg, whose nat bends :53 into
          # tor's DNSPort. There is no other resolver and no fallback: an
          # unresolvable name must fail, not leak sideways.
          nameservers = [ anonInnerAddr ];
        };

        systemd = {
          network = {
            wait-online.enable = false;
            networks."10-lan" = {
              matchConfig.MACAddress = anonBoxMac;
              networkConfig = {
                Address = [ "${anonBoxAddr}/${anonBoxPrefix}" ];
                Gateway = anonInnerAddr;
                DNS = [ anonInnerAddr ];
              };
            };
          };
          services = {
            # THE HOST'S ONLY WAY IN.
            #
            # The host has no address on this guest's segment, by design — so there is
            # nothing to ssh to, and that is the isolation property rather than an
            # inconvenience. vsock is a host<->guest channel that is not the network,
            # so using it costs none of that property.
            #
            # Two ports, deliberately: verification is a non-interactive request with a
            # parseable answer, not something scraped out of a terminal.
            #
            # Neither listener authenticates. Anyone who can already run code on the
            # host can open a shell here — which is acceptable because the host is the
            # trusted side and this guest holds nothing secret. It is ephemeral, and
            # the risk is someone USING the workstation, not extracting from it.
            anon-vsock-shell = {
              description = "Interactive shell for anon-shell, over vsock";
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.socat}/bin/socat VSOCK-LISTEN:${toString anon.workstation.shellPort},fork,reuseaddr EXEC:'${pkgs.shadow}/bin/login -f anon',pty,stderr,setsid,ctty";
                Restart = "always";
                RestartSec = "1s";
              };
            };
            anon-vsock-verify = {
              description = "L5 path check, answered over vsock";
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                # `,stderr` matters: without it curl's -sS diagnostics go to the guest
                # journal and the host sees an empty stream, making "DNS failed",
                # "no route" and "not Tor" indistinguishable.
                ExecStart = "${pkgs.socat}/bin/socat VSOCK-LISTEN:${toString anon.workstation.verifyPort},fork,reuseaddr EXEC:${
                  lib.getExe (
                    pkgs.writeShellApplication {
                      name = "anon-verify";
                      runtimeInputs = [ pkgs.curl ];
                      bashOptions = [ ];
                      text = ''
                        # Issued exactly as a workload would issue it: no proxy, no bound
                        # interface. This guest has one route and it points at the gateway,
                        # so the request cannot take any other path — which is what makes
                        # an unproxied request safe to make here.
                        curl -sS --max-time 30 ${anon.exitCheckUrl}
                      '';
                    }
                  )
                },stderr";
                Restart = "always";
                RestartSec = "1s";
              };
            };
          };
        };

        # Unprivileged. The VM is the real boundary, but there is no reason to
        # hand a scraper root inside it.
        users.users.anon = {
          isNormalUser = true;
          uid = 1000;
          description = "Anonymous workstation operator";
          home = "/home/anon";
        };

        # THE CURATED TOOLSET. Because no /nix/store share is declared,
        # microvm.storeOnDisk defaults true and this guest boots an erofs image
        # built from its own closure alone — it learns nothing about what is
        # installed on the host. Adding a tool is an edit here plus
        # `make anon-box-rebuild`; that friction is deliberate and cheap.
        environment.systemPackages = with pkgs; [
          curl
          wget
          jq
          git
          python3
          ripgrep
          fd
          openssh
        ];

        # No IPv6 anywhere on this path: tor carries none here, and an unrouted v6
        # socket is a leak waiting for a misconfiguration. Refuse it at the stack.
        boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 1;

        microvm = {
          mem = 2048;
          vcpu = 2;
          vsock.cid = anonBoxCid;
          interfaces = [
            {
              type = "tap";
              id = anonBoxTap;
              mac = anonBoxMac;
            }
          ];
          shares = [
            # Direction is explicit. `/in` is a read-only bind the host prepares
            # (see systemd.mounts below), so a workload cannot rewrite its own
            # inputs and you cannot casually expose your home directory.
            #
            # Honest about what this is: accident prevention, not a wall. Guest
            # root can remount its own mounts. It stops mistakes, not attackers.
            {
              source = "/run/anon-work/in";
              mountPoint = "/in";
              tag = "anon-in";
              proto = "virtiofs";
            }
            {
              source = "/home/${username}/Storage/anon/out";
              mountPoint = "/out";
              tag = "anon-out";
              proto = "virtiofs";
            }
          ];
        };

        # Deliberately NO persistent journal, inverting net-gate's choice.
        # net-gate persists its journal because a dead tor was once invisible for
        # days, and it logs mechanism rather than destinations. This guest's
        # journal would record actual activity, so it stays in RAM and dies with
        # the VM. Debugging means catching it live.
        services.journald.settings.Journal.Storage = "volatile";

      };
    };

  };

  systemd = {
    # Backing dirs for the net-gate shares. virtiofsd refuses to start if a
    # source is missing, and tmpfiles (sysinit.target) runs well before the
    # microvm units in multi-user.target.
    tmpfiles.rules = [
      # anon-box's workspace. Owned by the human, not root: you stage inputs and
      # read results as yourself. They live under ~/Storage rather than /persist
      # so they move behind LUKS when that lands — until then, anonymous output
      # is at rest in the clear, which is a known and accepted gap.
      "d /home/${username}/Storage/anon 0755 ${username} users -"
      "d /home/${username}/Storage/anon/in 0755 ${username} users -"
      "d /home/${username}/Storage/anon/out 0777 ${username} users -"
      # Mountpoint for the read-only view of in/ that the guest actually gets.
      "d /run/anon-work 0755 root root -"
      "d /run/anon-work/in 0755 root root -"
      "d /persist/var/lib/net-gate-ssh 0700 root root -"
    ]
    ++ lib.optional anon.persistTorState "d /persist/var/lib/net-gate-tor 0700 root root -"
    ++ lib.optional anon.persistGuestJournal "d ${anon.guestJournalDir} 0700 root root -";

    # The read-only half of the in/out split, enforced HOST-side.
    #
    # microvm shares have no readOnly option — the submodule accepts only tag,
    # socket, source, mountPoint and proto — so "read-only input" cannot be a
    # share flag. Binding it ro here and sharing the bind is the enforcement
    # that is actually available.
    mounts = [
      {
        what = "/home/${username}/Storage/anon/in";
        where = "/run/anon-work/in";
        type = "none";
        options = "bind,ro";
        requiredBy = [ "microvm@anon-box.service" ];
        before = [ "microvm@anon-box.service" ];
      }
    ];

    services = {
      # Mint net-gate's sops identity once; the journal line is its age recipient
      # for nixos/.sops.yaml (the private half never leaves this root-only dir).
      net-gate-ssh-key = {
        description = "Generate net-gate's own SSH host key";
        requiredBy = [ "microvm-virtiofsd@net-gate.service" ];
        before = [ "microvm-virtiofsd@net-gate.service" ];
        after = [ "systemd-tmpfiles-setup.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          key=/persist/var/lib/net-gate-ssh/ssh_host_ed25519_key
          [ -e "$key" ] || ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C net-gate -f "$key"
          echo "net-gate age recipient: $(${pkgs.ssh-to-age}/bin/ssh-to-age < "$key.pub")"
        '';
      };
    }
    # Fast shutdown. Upstream virtiofsd units are Type=notify; forced to simple
    # alongside the short stop timeouts (1824f5a).
    // lib.genAttrs (map (n: "microvm@${n}") (builtins.attrNames config.microvm.vms)) (_: {
      serviceConfig.TimeoutStopSec = "10s";
    })
    // lib.genAttrs (map (n: "microvm-virtiofsd@${n}") (builtins.attrNames config.microvm.vms)) (_: {
      serviceConfig = {
        Type = lib.mkForce "simple";
        TimeoutStopSec = "5s";
      };
    });
    network = {
      enable = true;
      wait-online.enable = false;

      # THE WORKSTATION SEGMENT. net-gate's inner tap and anon-box's tap are
      # enslaved here so the two guests share an L2 segment directly.
      #
      # The host assigns itself NO address on this bridge and no link-local
      # addressing. That is the security property: the host is not a hop in the
      # workstation's path and cannot reach the workstation over IP, so a
      # compromise on either side does not reach the other by routing. It also
      # means the host cannot ssh in — anon-shell enters over vsock instead.
      netdevs."20-br-anon" = {
        netdevConfig = {
          Name = anonBridge;
          Kind = "bridge";
        };
      };
      networks = {
        "20-br-anon" = {
          matchConfig.Name = anonBridge;
          networkConfig = {
            LinkLocalAddressing = "no";
            IPv6AcceptRA = false;
          };
          linkConfig.RequiredForOnline = "no";
        };
        "21-netgate-inner" = {
          matchConfig.Name = anonInnerTap;
          networkConfig = {
            Bridge = anonBridge;
            LinkLocalAddressing = "no";
          };
          linkConfig.RequiredForOnline = "no";
        };
        "22-anonbox-tap" = {
          matchConfig.Name = anonBoxTap;
          networkConfig = {
            Bridge = anonBridge;
            LinkLocalAddressing = "no";
          };
          linkConfig.RequiredForOnline = "no";
        };

        "10-microvm-tap" = {
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
        "11-tailscale-tap" = {
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
  };
  # Host-side networking to communicate with the VM
  # We use systemd-networkd BUT we must ensure it doesn't touch your main interfaces

  # Tell NetworkManager to ignore the VM taps so it doesn't try to manage them
  networking.networkmanager.unmanaged = [
    "interface-name:${anon.tapInterface}"
    "interface-name:vm-tailscale"
  ];
}

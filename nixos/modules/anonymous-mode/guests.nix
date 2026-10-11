# The anonymity guests and their host plumbing: net-gate (Tor gateway) and
# anon-box (workstation), joined by a host bridge the host holds no address on.
#
# `config` here is the HOST config, including inside microvm.vms.<name>.config;
# guest blocks use the let-bound values below rather than reaching into it.
{
  config,
  pkgs,
  inputs,
  lib,
  username,
  ...
}:
let
  anon = config.vol.anon-mode;
  guestBase = import ../../vm-guest-base.nix inputs;
  netgatePrefix = lib.last (lib.splitString "/" anon.torVmSubnet);

  # The net-gate masquerade is scoped to one source address, which networkd's
  # IPMasquerade cannot express. If this stops matching the uplink, arming
  # fails, which is the safe direction to be wrong in.
  wanInterface = "wlp4s0";

  # Workstation leg. cloud-hypervisor accepts only tap/macvtap (type = "bridge"
  # throws at eval), so both guests attach as taps and the HOST enslaves them.
  anonBridge = anon.workstation.bridge;
  anonInnerTap = "vm-ngi";
  anonBoxTap = "vm-anonbox";
  anonInnerAddr = anon.workstation.gatewayAddress;
  anonBoxAddr = anon.workstation.address;
  anonBoxSubnet = "192.168.102.0/24";
  anonBoxPrefix = "24";
  # Matched BY MAC: a name glob like `en* eth*` matches both of net-gate's NICs.
  # :02 is the tailscale guest.
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
in
{
  config = lib.mkIf anon.enable {
    # Tor's egress and nothing else: only the guest's address is masqueraded.
    # A workload packet the guest failed to redirect leaves with the tap address,
    # finds no NAT, and dies instead of egressing as the host.
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

          networking = {
            hostName = "net-gate";
            firewall = {
              # nat rewrites the port before filter/INPUT, so these are the ports
              # redirected packets actually arrive on.
              allowedTCPPorts = [
                anon.socksPort
                anon.transPort
              ];
              allowedUDPPorts = [ anon.dnsPort ];

              # TRANSPARENT PROXY: the enforcement boundary, matched by client source
              # address. Order matters: DNS first (so queries to this guest reach
              # DNSPort before the in-subnet RETURN), then RETURN (keeps SOCKS
              # usable), then all remaining TCP into TransPort. Nothing enables
              # ip_forward, so anything not rewritten (non-53 UDP, ICMP, QUIC) is
              # dropped rather than forwarded: fails shut.
              #
              # Both clients (host jail, workstation) come from one function: a
              # drifted copy would silently stop anonymising one of them.
              extraCommands = ''
                # Anything reaching the forwarding path instead of tor dies here; with
                # two legs this is what keeps the workstation off the WAN.
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
              networks."10-lan" = {
                matchConfig.MACAddress = netgateOuterMac;
                networkConfig = {
                  Address = [ "${anon.torVmAddress}/${netgatePrefix}" ];
                  Gateway = anon.tapAddress;
                  DNS = [ anon.tapAddress ];
                };
              };
              # Inner leg. NO Gateway: tor's own egress must stay out the host tap,
              # never via the workstation.
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
            # cloud-hypervisor's systemd-notify over vsock needs a CID.
            vsock.cid = 10;
            interfaces = [
              {
                type = "tap";
                id = anon.tapInterface;
                mac = netgateOuterMac;
              }
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
              # Tor's DataDirectory; see vol.anon-mode.persistTorState for the trade-off.
              source = "/persist/var/lib/net-gate-tor";
              mountPoint = "/var/lib/tor";
              tag = "tor-state";
              proto = "virtiofs";
            }
            ++ lib.optional anon.persistGuestJournal {
              # journald's Storage=auto goes persistent once /var/log/journal exists.
              source = anon.guestJournalDir;
              mountPoint = "/var/log/journal";
              tag = "journal";
              proto = "virtiofs";
            };
          };

          # This guest TERMINATES traffic into tor and must never route it: with
          # forwarding on, an unredirected packet would be masqueraded out the WAN
          # as the host. Stated explicitly, backed by the FORWARD drop above.
          boot.kernel.sysctl = {
            "net.ipv4.ip_forward" = 0;
            "net.ipv4.conf.all.forwarding" = 0;
            "net.ipv6.conf.all.forwarding" = 0;
          };

          services.tor = {
            enable = true;
            client = {
              enable = true;
              # The SOCKS listener comes from here, NOT settings.SOCKSPort:
              # client.enable already emits one, and a duplicate bind kills tor.
              socksListenAddress = {
                addr = anon.torVmAddress;
                port = anon.socksPort;
                IsolateDestAddr = true;
              };
            };
            settings = {
              # TransPort/DNSPort carry the enforced path. Declared here, not via
              # client.transparentProxy/dns: those add 127.0.0.1 listeners that MERGE
              # with these list-typed settings.
              #
              # ONE LISTENER PER LEG: REDIRECT targets the primary address of the
              # interface a packet arrived on, so a listener only on the outer address
              # would silently blackhole the workstation.
              TransPort = [
                {
                  addr = anon.torVmAddress;
                  port = anon.transPort;
                  # Every transparent flow shares one client address, so per-destination
                  # is the isolation available here; per-invocation stays a SOCKS feature.
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
              # tor's default, spelled out because the guest journal is persisted.
              SafeLogging = true;
              # Must not overlap any address the host answers for: the `local` table
              # (priority 0) beats the jail's uidrange rule, so a local-address hit
              # bypasses tor while routing still looks correct. 172.16.0.0/12
              # collides with the WAN and docker0; re-check if host addressing changes.
              VirtualAddrNetworkIPv4 = "10.192.0.0/10";
              AutomapHostsOnResolve = true;
              # No IPv6 uplink on this host.
              ClientUseIPv6 = false;
            };
          };

          # vm-secrets.yaml holds only a placeholder today. This wiring (own key,
          # sops module) is kept so a guest secret can be added without re-deriving
          # the trust boundary; drop it if the guest never needs one.
          sops = {
            defaultSopsFile = ../../vm-secrets.yaml;
            age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
          };

          environment.systemPackages = [ pkgs.ssh-to-age ];
        };
      };

      # THE ANONYMITY WORKSTATION: a kernel boundary instead of anon-run's uid
      # boundary, and the workload never runs on the machine that terminates tor.
      #
      # autostart = false: anonymous.target starts it only after the readiness
      # ladder has proven the path (see default.nix).
      anon-box = {
        autostart = false;
        config = {
          imports = [ guestBase ];

          networking = {
            hostName = "anon-box";
            # Only resolver: the gateway's inner leg, bent into tor's DNSPort. No
            # fallback; an unresolvable name must fail, not leak.
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
              # The host's only way in: it has no address on this segment by design,
              # and vsock is not the network. Neither listener authenticates; the host
              # is the trusted side and this ephemeral guest holds nothing secret.
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
                  # `,stderr` sends curl's diagnostics to the host; without it "DNS
                  # failed", "no route" and "not Tor" look identical.
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

          users.users.anon = {
            isNormalUser = true;
            uid = 1000;
            description = "Anonymous workstation operator";
            home = "/home/anon";
          };

          # No /nix/store share, so storeOnDisk boots an erofs image of this closure
          # alone: the guest learns nothing about the host's packages. Adding a tool
          # is an edit here plus `make anon-box-rebuild`.
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

          # tor carries no IPv6 here; an unrouted v6 socket is a leak waiting to happen.
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
            # /in is a host-side read-only bind (systemd.mounts below); accident
            # prevention, not a wall, since guest root can remount.
            shares = [
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

          # Volatile on purpose (unlike net-gate): this journal would record activity,
          # not mechanism.
          services.journald.settings.Journal.Storage = "volatile";
        };
      };
    };

    systemd = {
      # virtiofsd refuses a missing share source; tmpfiles runs well before the
      # microvm units. ~/Storage is NOT encrypted (only /persist is), so anonymous
      # output in anon/out is at rest in the clear: a known, accepted gap.
      tmpfiles.rules = [
        "d /home/${username}/Storage/anon 0755 ${username} users -"
        "d /home/${username}/Storage/anon/in 0755 ${username} users -"
        "d /home/${username}/Storage/anon/out 0777 ${username} users -"
        "d /run/anon-work 0755 root root -"
        "d /run/anon-work/in 0755 root root -"
        "d /persist/var/lib/net-gate-ssh 0700 root root -"
      ]
      ++ lib.optional anon.persistTorState "d /persist/var/lib/net-gate-tor 0700 root root -"
      ++ lib.optional anon.persistGuestJournal "d ${anon.guestJournalDir} 0700 root root -";

      # microvm shares have no readOnly flag, so the read-only input is a ro bind
      # shared in its place.
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

      # Mint net-gate's sops identity once; the journal line is its age recipient
      # for nixos/.sops.yaml (the private half never leaves this root-only dir).
      services.net-gate-ssh-key = {
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

      network = {
        # The workstation segment. The host takes NO address (and no link-local)
        # on it: it is not a hop in the workstation's path and cannot reach it
        # over IP. anon-shell enters over vsock instead.
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
              # NO IPMasquerade: it would SNAT the whole subnet, including workload
              # packets the guest failed to redirect. See networking.nat above.
            };
            linkConfig.RequiredForOnline = "no";
          };
        };
      };
    };

    networking.networkmanager.unmanaged = [ "interface-name:${anon.tapInterface}" ];
  };
}

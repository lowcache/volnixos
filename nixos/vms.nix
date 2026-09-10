{
  pkgs,
  inputs,
  lib,
  ...
}:
{

  # MicroVM Host Configuration
  imports = [
    inputs.microvm.nixosModules.host
  ];

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
          # Allow Tor TransPort (9040), SOCKS5 (9050) and DNSPort (5353) from the host
          allowedTCPPorts = [
            9040
            9050
          ];
          allowedUDPPorts = [ 5353 ];
        };
      };

      systemd = {
        network = {
          enable = true;
          networks."10-lan" = {
            matchConfig.Name = "en* eth*";
            networkConfig = {
              Address = [ "192.168.100.2/24" ];
              Gateway = "192.168.100.1";
              DNS = [ "192.168.100.1" ];
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
            id = "vm-netgate";
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
        ];
      };

      # Fix Entropy and VSOCK early load
      boot.kernelParams = [ "random.trust_cpu=on" ];

      # Tor Anonymity Layer - Transparent Proxy
      services.tor = {
        enable = true;
        client.enable = true;
        settings = {
          # IMPORTANT: Tor VM is an OPT-IN proxy, not a transparent traffic enforcer.
          # Host traffic is NOT automatically routed through Tor.
          # To use: curl --socks5 192.168.100.2:9050
          # Or: sudo systemctl start anonymous.target   (after Phase 5 is complete)
          TransPort = [
            {
              addr = "0.0.0.0";
              port = 9040;
            }
          ];
          # SOCKS5 for per-app proxying from the host (curl/brave wrappers, etc.)
          SOCKSPort = [
            {
              addr = "0.0.0.0";
              port = 9050;
            }
          ];
          DNSPort = [
            {
              addr = "0.0.0.0";
              port = 5353;
            }
          ];
          VirtualAddrNetworkIPv4 = "172.16.0.0/12";
          AutomapHostsOnResolve = true;
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
        matchConfig.Name = "vm-netgate";
        networkConfig = {
          Address = [ "192.168.100.1/24" ];
          IPv4Forwarding = true;
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
    "interface-name:vm-netgate"
    "interface-name:vm-tailscale"
  ];
}

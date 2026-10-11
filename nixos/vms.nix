# MicroVM host and the tailscale gateway guest. The anonymity guests (net-gate,
# anon-box) belong to vol.anon-mode: modules/anonymous-mode/guests.nix.
{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.vol.tailscale-vm;
  guestBase = import ./vm-guest-base.nix inputs;
  prefix = lib.last (lib.splitString "/" cfg.subnet);
in
{
  imports = [
    inputs.microvm.nixosModules.host
  ];

  options.vol.tailscale-vm = {
    tapInterface = lib.mkOption {
      type = lib.types.str;
      default = "vm-tailscale";
      description = "Host-side tap of the tailscale guest.";
    };
    subnet = lib.mkOption {
      type = lib.types.str;
      default = "192.168.101.0/24";
      description = "Host<->guest link subnet.";
    };
    hostAddress = lib.mkOption {
      type = lib.types.str;
      default = "192.168.101.1";
      description = "Host address on the tap: the guest's gateway and DNS, and where it DNATs tailnet ports.";
    };
    guestAddress = lib.mkOption {
      type = lib.types.str;
      default = "192.168.101.2";
      description = "Guest address on the tap: the host's next hop to the tailnet.";
    };
  };

  config = {
    microvm.vms.tailscale = {
      autostart = true;
      config = {
        imports = [ guestBase ];

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
                Address = [ "${cfg.guestAddress}/${prefix}" ];
                Gateway = cfg.hostAddress;
                DNS = [ cfg.hostAddress ];
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
              id = cfg.tapInterface;
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
          # Auto-join from a key in the persisted share
          # (host /persist/var/lib/tailscale-vm/authkey); no console needed.
          authKeyFile = "/var/lib/tailscale/authkey";
          # Exit-node mode makes tailscaled install the forward rules that route
          # host-tap traffic out over tailscale0; admin approval isn't needed for that.
          extraUpFlags = [ "--advertise-exit-node" ];
        };

        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
        };

        # SNAT host traffic onto this node's tailnet IP so peers can reply, letting
        # the host reach 100.x via ${cfg.guestAddress} without being a tailnet node.
        # forwardPorts publish host services to the tailnet (Ollama; the phone-agent
        # push server, which keeps laptop->phone transfer phone-initiated);
        # conntrack un-DNATs replies over the host's 100.64.0.0/10 route.
        networking.nat = {
          enable = true;
          externalInterface = "tailscale0";
          internalIPs = [ cfg.subnet ];
          forwardPorts =
            map
              (port: {
                proto = "tcp";
                sourcePort = port;
                destination = "${cfg.hostAddress}:${toString port}";
              })
              [
                config.services.ollama.port
                config.phone-agent.pushPort
              ];
        };
      };
    };

    systemd = {
      # virtiofsd refuses a missing share source.
      tmpfiles.rules = [ "d /persist/var/lib/tailscale-vm 0700 root root" ];

      # Fast shutdown. Upstream virtiofsd units are Type=notify; forced to simple
      # alongside the short stop timeouts (1824f5a).
      services =
        lib.genAttrs (map (n: "microvm@${n}") (builtins.attrNames config.microvm.vms)) (_: {
          serviceConfig.TimeoutStopSec = "10s";
        })
        // lib.genAttrs (map (n: "microvm-virtiofsd@${n}") (builtins.attrNames config.microvm.vms)) (_: {
          serviceConfig = {
            Type = lib.mkForce "simple";
            TimeoutStopSec = "5s";
          };
        });

      # networkd handles only the VM taps; NetworkManager keeps the physical links.
      network = {
        enable = true;
        wait-online.enable = false;
        networks."11-tailscale-tap" = {
          matchConfig.Name = cfg.tapInterface;
          networkConfig = {
            Address = [ "${cfg.hostAddress}/${prefix}" ];
            IPv4Forwarding = true;
            # So tailscaled can reach the coordination server and DERP to authenticate.
            IPMasquerade = "both";
          };
          # Host route to the tailnet via the guest (pairs with the guest's SNAT).
          routes = [
            {
              Destination = "100.64.0.0/10";
              Gateway = cfg.guestAddress;
            }
          ];
          linkConfig.RequiredForOnline = "no";
        };
      };
    };

    networking.networkmanager.unmanaged = [ "interface-name:${cfg.tapInterface}" ];
  };
}

{ config, pkgs, inputs, lib, ... }: {

  # MicroVM Host Configuration
  imports = [
    inputs.microvm.nixosModules.host
  ];

  # Host-side overrides for fast shutdown
  systemd.services."microvm@net-gate".serviceConfig.TimeoutStopSec = "10s";
  systemd.services."microvm-virtiofsd@net-gate".serviceConfig.TimeoutStopSec = "5s";

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
          # Allow Tor TransPort and DNSPort from the host
          allowedTCPPorts = [ 9040 ];
          allowedUDPPorts = [ 5353 ];
        };
      };

      microvm = {
        hypervisor = "cloud-hypervisor";
        mem = 512;
        vcpu = 1;
        #cloud-hypervisor supports systemd-notify via vsock, but `microvm.vsock.cid` must be set to enable this.
        vsock.cid = 10;
        interfaces = [{
          type = "tap";
          id = "vm-netgate";
          mac = "02:00:00:00:00:01";
        }];
        shares = [{
          source = "/persist/etc/ssh";
          mountPoint = "/etc/ssh";
          tag = "ssh-keys";
          proto = "virtiofs";
        }];
      };

      # Fix Entropy and VSOCK early load
      boot.kernelParams = [ "random.trust_cpu=on" ];

      # Tor Anonymity Layer - Transparent Proxy
      services.tor = {
        enable = true;
        client.enable = true;
        settings = {
          TransPort = [{ addr = "0.0.0.0"; port = 9040; }];
          DNSPort = [{ addr = "0.0.0.0"; port = 5353; }];
          VirtualAddrNetworkIPv4 = "172.16.0.0/12";
          AutomapHostsOnResolve = true;
        };
      };

      # Fast Tor Shutdown
      systemd.services.tor.serviceConfig.TimeoutStopSec = "2s";

      # Sops Configuration
      sops = {
        defaultSopsFile = ./secrets.yaml; # Relative to THIS file (nixos/vms.nix)
        age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
        # secrets.wg_private_key = {}; # Commented until added to secrets.yaml
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

  # Host-side networking to communicate with the VM
  # We use systemd-networkd BUT we must ensure it doesn't touch your main interfaces
  systemd.network = {
    enable = true;
    wait-online.enable = false;
    networks."10-microvm-tap" = {
      matchConfig.Name = "vm-netgate";
      networkConfig = {
        Address = [ "10.0.0.1/24" ];
        DHCPServer = true;
        IPv4Forwarding = true;
      };
      # Ensure this network doesn't become the default route for the host
      linkConfig.RequiredForOnline = "no";
    };
  };

  # Tell NetworkManager to ignore the VM tap so it doesn't try to manage it
  networking.networkmanager.unmanaged = [ "interface-name:vm-netgate" ];
}

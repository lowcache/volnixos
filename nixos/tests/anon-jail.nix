# The fail-closed half of vol.anon-mode, without Tor: the anon uid has no route
# before arming, reaches the gateway only while anon-routing is up, and is
# sealed again after. A stub gateway answers for an off-link address, so a
# successful request proves the uid's default route points at it.
{ inputs }:
{
  name = "anon-jail";

  nodes = {
    gateway =
      { pkgs, ... }:
      {
        networking.firewall.allowedTCPPorts = [ 80 ];
        # The off-link address the anon uid can only reach through this node.
        systemd.services.stub-address = {
          wantedBy = [ "multi-user.target" ];
          before = [ "nginx.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = "${pkgs.iproute2}/bin/ip addr add 203.0.113.1/32 dev lo";
        };
        services.nginx = {
          enable = true;
          virtualHosts.stub = {
            default = true;
            locations."/".return = "200 ok";
          };
        };
      };

    # The real module, with net-gate's tap played by eth1 and the gateway node
    # standing in for net-gate.
    host =
      {
        config,
        lib,
        nodes,
        ...
      }:
      {
        imports = [ ../modules/anonymous-mode ];
        # Stand-ins for the microvm host options the module touches; no guests run.
        options.microvm = {
          vms = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          stateDir = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/microvms";
          };
        };
        config = {
          _module.args = {
            inherit inputs;
            username = "root";
          };
          # Stands in for the real host's WAN default route: loose rpfilter drops
          # replies from a source the main table cannot route back to.
          networking.interfaces.eth1.ipv4.routes = [
            {
              address = "203.0.113.0";
              prefixLength = 24;
              via = nodes.gateway.networking.primaryIPAddress;
            }
          ];
          vol.anon-mode = {
            enable = true;
            tapInterface = "eth1";
            torVmSubnet = "192.168.1.0/24";
            tapAddress = config.networking.primaryIPAddress;
            torVmAddress = nodes.gateway.networking.primaryIPAddress;
          };
        };
      };
  };

  testScript =
    { nodes, ... }:
    let
      gw = nodes.gateway.networking.primaryIPAddress;
    in
    ''
      gw = "${gw}"
      anon = "setpriv --reuid=10000 --regid=65534 --clear-groups "
      off_link = "curl -sf --max-time 5 http://203.0.113.1/"

      start_all()
      gateway.wait_for_unit("nginx.service")
      gateway.wait_for_unit("stub-address.service")
      host.wait_for_unit("anon-jail.service")
      host.wait_until_succeeds(f"curl -sf --max-time 2 http://{gw}/")

      with subtest("sealed before arming, including the on-link gateway"):
          host.succeed("ip rule | grep -q 'uidrange 10000-10000 lookup 100'")
          host.succeed("ip -6 route show table 100 | grep -q '^blackhole default'")
          host.fail(anon + off_link)
          host.fail(anon + f"curl -sf --max-time 5 http://{gw}/")

      with subtest("anon-exec refuses while unarmed"):
          status, _ = host.execute("anon-exec true")
          assert status == 69, f"anon-exec exited {status}, expected 69"

      with subtest("armed: the uid's default route is the gateway"):
          host.succeed("systemctl start anon-routing.service")
          host.succeed(anon + off_link)

      with subtest("disarmed: sealed again"):
          host.succeed("systemctl stop anon-routing.service")
          host.fail(anon + off_link)

      with subtest("jail re-assertion is idempotent"):
          host.succeed("systemctl restart anon-jail.service")
          host.succeed("test $(ip rule | grep -c 'uidrange 10000-10000') -eq 1")
          host.fail(anon + off_link)
    '';
}

{ config, pkgs, lib, inputs, ... }:
let get-host-ip = "$(ip route show | awk '/default/ {print $3; exit}')";
in {
  imports = [
    inputs.nixos-fhs-compat.nixosModules.combined
    ./lsb.nix
  ];

  disabledModules = [
    "${inputs.nixos-fhs-compat}/modules/lsb.nix"
  ];

  environment = {
    fhs.enable = true;
    fhs.linkLibs = true;
    lsb.enable = true;
    lsb.support32Bit = true;
  };

  boot.isContainer = true;

  networking.useDHCP = false;
  networking.hostName = "kalinix";
  networking.firewall.enable = true;

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs;
    [ waypipe socat dpkg xlibs.xeyes ] ++ import ./pkgs.nix pkgs;

  users.users.user = {
    isNormalUser = true;
    uid = 1000;
    description = "Main User";
    password = "";
  };

  systemd.services.waypipe = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "network.target" ];
    path = [ pkgs.socat pkgs.iproute2 ];
    script =
      "socat UNIX-LISTEN:/tmp/waypipe-server.sock,reuseaddr,fork,user=user,group=users,mode=660 TCP-CONNECT:${get-host-ip}:1337";
  };

  environment.shellInit = "export DISPLAY=${get-host-ip}:0";

  environment.sessionVariables._JAVA_AWT_WM_NONREPARENTING = "1";

  services.getty.autologinUser = "user";
}

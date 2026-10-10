# Boot loader & secure boot (kernel/perf config lives in
# ./hardware/asus-ryzen-nvidia/kernel.nix)
{
  lib,
  ...
}:
{
  boot = {
    initrd.systemd.enable = true;
    loader = {
      systemd-boot = {
        # lanzaboote replaces systemd-boot and needs it off.
        enable = lib.mkForce false;
        configurationLimit = 10;
      };
      efi.canTouchEfiVariables = true;
    };
    lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
    };
  };
}

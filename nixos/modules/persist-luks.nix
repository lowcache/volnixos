# /persist inside a LUKS2 container. /boot and /nix stay plaintext; the root is
# tmpfs, so /persist is the only place machine state and secrets live at rest.
# The container is created by ~/Storage/luks-migration (live-USB procedure),
# with its UUID pinned in advance so this config can be built before it exists.
{
  config,
  lib,
  ...
}:
let
  cfg = config.vol.persistLuks;
in
{
  options.vol.persistLuks = {
    enable = lib.mkEnableOption "LUKS2 encryption of the /persist partition";
    uuid = lib.mkOption {
      type = lib.types.str;
      description = "UUID of the LUKS2 header (fixed at `cryptsetup luksFormat --uuid`).";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.initrd.luks.devices.cryptpersist = {
      device = "/dev/disk/by-uuid/${cfg.uuid}";
      # TRIM leaks which blocks are in use, not their contents.
      allowDiscards = true;
      bypassWorkqueues = true;
    };
    fileSystems."/persist".device = lib.mkForce "/dev/mapper/cryptpersist";
  };
}

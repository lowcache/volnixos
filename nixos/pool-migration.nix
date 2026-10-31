# TEMPORARY /persist+Storage pool-migration overlay for the volnix-pool target.
# Pins the new pooled-LUKS header UUID, turns ~/Storage into a bind of
# /persist/storage, and exposes smartctl. Folded into the main config and
# deleted post-migration. See docs/wikifixins/persist-storage-pool-migration.md.
{
  lib,
  pkgs,
  username,
  ...
}:
{
  # Live-USB `cryptsetup luksFormat --uuid` MUST match this.
  vol.persistLuks.uuid = lib.mkForce "5ed6b5fc-331f-47cd-95a0-5f4ff9d613f2";

  # ~/Storage is no longer its own disk; it is a subdir of the pooled /persist.
  fileSystems."/home/${username}/Storage" = lib.mkForce {
    device = "/persist/storage";
    fsType = "none";
    options = [
      "bind"
      "nosuid"
      "nodev"
    ];
    depends = [ "/persist" ];
  };

  # smartd already runs; expose the CLI for SMART pre-flights.
  environment.systemPackages = [ pkgs.smartmontools ];
}

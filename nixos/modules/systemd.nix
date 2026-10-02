# systemd manager tuning, tmpfiles scaffolding on the tmpfs root, and the
# nix-daemon build-temp relocation.
{
  pkgs,
  username,
  ...
}:
{
  systemd = {
    oomd.enable = false;
    tmpfiles.rules = [
      "d /home/${username} 0700 ${username} users"
      "d /home/${username}/AppImage 0755 ${username} users"
      "d /home/${username}/Storage/ai-generation 0755 ${username} users"
      "d /home/${username}/Storage/ai-generation/fooocus 0755 ${username} users"
      "d /home/${username}/Storage/ai-generation/forge 0755 ${username} users"
      "d /persist/var/lib/tailscale-vm 0700 root root"
      # Disk-backed build temp so nix builds never exhaust the 4G tmpfs root.
      "d /nix/tmp 1777 root root -"
    ];
    services = {
      # Build temp on /nix (root-owned, nixbld-accessible) — never the RAM tmpfs.
      # Must NOT live under the user's home (0700) or nixbld can't traverse it.
      nix-daemon.environment.TMPDIR = "/nix/tmp";
      # Shutdown-only: reboot/halt/poweroff all pull in shutdown.target. Without
      # DefaultDependencies=no in [Unit] the unit also Conflicts= that target
      # and systemd breaks the resulting ordering cycle by dropping jobs.
      decapitate-fuse-mounts = {
        description = "Force lazy unmount of xdg-document-portal FUSE to release /nix";
        unitConfig.DefaultDependencies = false;
        before = [
          "umount.target"
          "shutdown.target"
        ];
        wantedBy = [ "shutdown.target" ];
        serviceConfig.Type = "oneshot";
        # Globbed, not a fixed uid: uids are auto-allocated on this host.
        script = ''
          for d in /run/user/*/doc; do
            ${pkgs.util-linux}/bin/umount -f -l "$d" 2>/dev/null || true
          done
          ${pkgs.psmisc}/bin/killall -9 xdg-document-portal fusermount3 2>/dev/null || true
        '';
      };
    };
    settings.Manager = {
      DefaultTimeoutStopSec = "10s";
      DefaultRestartSec = "1s";
    };
    user.settings.Manager.DefaultTimeoutStopSec = "5s";
  };
}

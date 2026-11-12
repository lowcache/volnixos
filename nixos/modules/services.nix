# Small service toggles with no cross-module coupling. The heavier services
# (Ollama, Open WebUI) live in ai-stack.nix; the graphical session in
# desktop.nix.
{ config, pkgs, ... }:
{
  # niri enumerates DRM cards only at startup and on udev "add". A dGPU that
  # cardwired blocked at login (battery) stays invisible after unblocking, and
  # with it every dGPU-wired output (HDMI-A-1). Replay "add" on each unblock;
  # smithay ignores adds for cards it already holds.
  systemd.services.cardwire-drm-replay = {
    description = "Replay DRM add uevents when cardwired unblocks a GPU";
    after = [ "cardwired.service" ];
    bindsTo = [ "cardwired.service" ];
    wantedBy = [ "cardwired.service" ];
    path = [
      pkgs.glib.bin
      config.systemd.package
    ];
    script = ''
      gdbus monitor --system --dest org.opengamingcollective.cardwire |
        while read -r obj rest; do
          [[ $rest == *"'Block': <false>"* ]] || continue
          pci=$(busctl --system call org.opengamingcollective.cardwire "''${obj%:}" \
            org.opengamingcollective.cardwire.Gpu GetDevice | cut -d'"' -f4)
          for card in /sys/bus/pci/devices/"$pci"/drm/card*; do
            [[ -e $card ]] && udevadm trigger --action=add "$card"
          done
        done
    '';
    serviceConfig.Restart = "on-failure";
  };

  services = {
    # Vial keyboard configurator: unprivileged hidraw access for Vial-enabled
    # keyboards (matched by the vial:f64c2b3c magic in the USB serial).
    udev.extraRules = ''
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
    '';
    upower.enable = true;
    fwupd.enable = true;
    smartd.enable = true;
    timesyncd.enable = true;
    geoclue2.enable = true;
    flatpak.enable = true;
    asusd.enable = true;
    # supergfxd unbinds the dGPU's PCI device to switch modes; cardwired blocks
    # access with eBPF/LSM instead and leaves the nvidia driver loaded, so the
    # two are alternatives, not companions. Keep this off.
    supergfxd.enable = false;
    # asusd owns platform_profile and CPU EPP. A second daemon here races it
    # over /sys/firmware/acpi/platform_profile.
    power-profiles-daemon.enable = false;
    # Requires `bpf` in security.lsm (the nixpkgs default) and Wayland; both
    # hold on this host. State lives in /var/lib/cardwire -- persisted in
    # hardware-configuration.nix, or manual-mode GPU state dies with the tmpfs.
    cardwired = {
      enable = true;
      settings = {
        # Reads backwards: battery drops to integrated, and *_mode (default
        # "hybrid") is what AC restores.
        battery_auto_switch = true;
        # Keeps dGPU-wired display outputs usable while in integrated mode.
        external_display_auto_switch = true;
      };
    };
    logind.settings = {
      Login = {
        KillUserProcesses = true;
      };
    };
  };
}

# Small service toggles with no cross-module coupling. The heavier services
# (Ollama, Open WebUI) live in ai-stack.nix; the graphical session in
# desktop.nix.
{
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

{
  lib,
  inputs,
  username,
  ...
}:
{

  imports = [
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
    ./hardware/asus-ryzen-nvidia
  ];

  # Hardware (GPU config lives in ./hardware/asus-ryzen-nvidia/gpu.nix)
  hardware = {
    enableRedistributableFirmware = true;
    bluetooth.enable = true;
  };

  # Swap
  swapDevices = lib.singleton {
    device = "/persist/swapfile";
    size = 16 * 1024; # 16GB physical backup
  };
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50; # Use up to 50% of RAM as compressed swap
  };

  # Impermanence
  fileSystems = {
    "/" = {
      device = "none";
      fsType = "tmpfs";
      options = [
        "defaults"
        "size=4G"
        "mode=755"
      ];
    };
    "/boot" = {
      device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
      # The ESP holds the systemd-boot random seed; keep it root-only.
      options = [ "umask=0077" ];
    };
    "/nix" = {
      device = "/dev/disk/by-label/NIX";
      fsType = "ext4";
    };
    # BOOT DEPENDENCY: neededForBoot = true is required because SOPS decrypts
    # secrets using the SSH host key at /persist/etc/ssh/ssh_host_ed25519_key.
    # If /persist fails to mount, SOPS cannot decrypt passwords and login will fail.
    "/persist" = {
      device = "/dev/disk/by-label/PERSIST";
      fsType = "ext4";
      neededForBoot = true;
    };
    "/home/${username}/Storage" = {
      # Label: STORAGE  (set with: sudo e2label /dev/sdXY STORAGE)
      # Current UUID: 71548923-2081-44c1-b4f1-6826cb7a6ac8
      # Label must exist on the disk BEFORE activating this config
      # (verified present on nvme0n1p1 as of 2026-07-09).
      device = "/dev/disk/by-label/STORAGE";
      fsType = "ext4";
      # Data volume, and anon-box writes into Storage/anon/out over virtiofs:
      # nothing here should ever be honoured as setuid or as a device node.
      options = [
        "nosuid"
        "nodev"
      ];
    };
  };
  # Persistence
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos"
      "/var/lib/bluetooth"
      "/var/lib/NetworkManager"
      "/var/lib/docker"
      "/var/lib/greetd"
      "/var/log"
      "/var/lib/flatpak"
      "/var/lib/sbctl"
      "/var/lib/microvm"
      # waydroid images: ~2.4G of downloaded system/vendor img. Unpersisted it
      # lands on the 4G tmpfs root and fills it (did, 2026-08-21).
      "/var/lib/waydroid"
      "/var/lib/private/open-webui"
      # cardwired's StateDirectory; holds manual-mode GPU state.
      "/var/lib/cardwire"
      # fwupd update history / pending capsule state across reboots.
      "/var/lib/fwupd"
      "/etc/secureboot"
      "/etc/asusd"
      "/etc/ssh"
      "/etc/NetworkManager/system-connections"
    ];
    files = [
      "/etc/machine-id"
    ];
  };
}

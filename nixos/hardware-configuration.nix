{ config, lib, pkgs, modulesPath, inputs, ... }: {

  imports = [
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
  ];

  # Hardware GPU
  hardware = {
    enableRedistributableFirmware = true;
    amdgpu.opencl.enable = true;
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        nvidia-vaapi-driver
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };
    nvidia-container-toolkit.enable = true;
    nvidia = {
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      modesetting.enable = true;
      #dynamicboost.enable = true;
      powerManagement = {
        enable = true;
        finegrained = true;
      };
      open = true;
      prime = {
        offload = {
          enable = true;
          enableOffloadCmd = true;
        };
        sync.enable = false;
        reverseSync.enable = false;
        amdgpuBusId = "PCI:102:0:0"; # 66:00.0 hex -> 102 decimal
        nvidiaBusId = "PCI:1:0:0"; # 01:00.0 hex -> 1 decimal
      };
    };
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
      options = [ "defaults" "size=4G" "mode=755" ];
    };
    "/boot" = {
      device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
    };
    "/nix" = {
      device = "/dev/disk/by-label/NIX";
      fsType = "ext4";
    };
    "/persist" = {
      device = "/dev/disk/by-label/PERSIST";
      fsType = "ext4";
      neededForBoot = true;
    };
    "/home/lowcache/Storage" = {
      device = "/dev/disk/by-uuid/71548923-2081-44c1-b4f1-6826cb7a6ac8";
      fsType = "ext4";
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
      "/var/lib/private/open-webui"
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

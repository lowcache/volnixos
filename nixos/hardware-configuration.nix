{ config, lib, pkgs, modulesPath, inputs, ... }: {

  imports = [ 
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
  ];
  
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
      modesetting.enable = true;
      powerManagement = {
        enable = true;
        finegrained = true;
      };
      open = true; # Use the open-source kernel module for 40-series cards
      prime = {
        offload = {
          enable = true;
          enableOffloadCmd = true;
        };
        amdgpuBusId = "PCI:102:0:0"; # 66:00.0 in decimal (6*16+6=102)
        nvidiaBusId = "PCI:1:0:0";   # 01:00.0
      };
    };
  };
  
  swapDevices = [ 
    {
      device = "/persist/swapfile";
      size = 16 * 1024; # 16GB physical backup
    } 
  ];
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50; # Use up to 50% of RAM as compressed swap
  };
  
  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [ "defaults" "size=4G" "mode=755" ];
  };

  fileSystems."/boot" = { device = "/dev/disk/by-label/BOOT"; fsType = "vfat"; };
  fileSystems."/nix" = { device = "/dev/disk/by-label/NIX"; fsType = "ext4"; };
  fileSystems."/persist" = { 
    device = "/dev/disk/by-label/PERSIST"; 
    fsType = "ext4"; 
    neededForBoot = true; 
  };

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
      "/etc/secureboot"
      "/etc/asusd"
      "/etc/NetworkManager/system-connections"
    ];
    files = [ 
      "/etc/machine-id"
    ];
  };
}

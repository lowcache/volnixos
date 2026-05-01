{ config, pkgs, inputs, lib, ... }: {
  # Kernel & Performance
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.systemd-boot.configurationLimit = 3;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [ "nvidia.NVreg_EnableGpuFirmware=1" ];
  hardware.enableRedistributableFirmware = true;
  hardware.nvidia-container-toolkit.enable = true;  
  # Asus TUF A16 (2024) Hardware Support
  imports = [ 
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
  ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = true; # Use the open-source kernel module for 40-series cards
    prime = {
      offload.enable = true;
      amdgpuBusId = "PCI:102:0:0"; # 66:00.0 in decimal (6*16+6=102)
      nvidiaBusId = "PCI:1:0:0";   # 01:00.0
    };
  };
  # Security & Anonymity
  networking = {
    networkmanager = {
      enable = true;
      wifi.scanRandMacAddress = true;
    };
  };
  systemd = {
    tmpfiles.rules = [ "d /home/nondeus 0700 nondeus users" ];
    services = { 
      greetd.serviceConfig = {
        type = "idle";
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "journal";
        TTYReset = true;
        TTYHangup = true;
        TTYDeallocate = true;
      };
      nix-daemon.serviceConfig.KillMode = "process";
      decapitate-fuse-mounts = {
        description = "Force lazy unmount of xdg-document-portal FUSE to release /nix";
        before = [ "local-fs.target" ];
        wantedBy = [ "shutdown.target" "reboot.target" "halt.target" ];
        serviceConfig = {
          Type = "oneshot";
          DefaultDependencies = false;
          ExecStart = "${pkgs.coreutils}/bin/umount -f -l /run/user/1000/doc || true";
          ExecStopPost = "${pkgs.psmisc}/bin/killall -9 xdg-document-portal fusermount3";
        };
      };
    };
    settings.Manager = {
      DefaultTimeoutStopSec = "10s";
      DefaultRestartSec = "1s";
    };
    user.extraConfig = "DefaultTimeoutStopSec=5s";
    mounts = [
      {
      	what = "/dev/disk/by-local/nixos";
      	where = "/nix";
      	options = "x-systemd.mount-timeout=1s";
      }
    ];
  };
  # Android & Connectivity
  users.users.nondeus = {
  	isNormalUser = true;
  	hashedPassword = "$6$TC4VPrCqV64Jitm3$2yZL1T8LhyMHM7rU7wLcKxQqhtdhhWrsRSPIOaJ7t4u2ML8pI53kBSpe/KYWx8B7xrEfLMGsKX5xp8.Oo1qTo.";
  	extraGroups = [ "adbusers" "networkmanager" "wheel" "video" "docker" ];
  };
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };
  programs.kdeconnect.enable = true;
  programs.fish.enable = true;
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
    liveRestore = false;
  };
  # Application Support
  services = {
    geoclue2.enable = true;
    scx.enable = true;
    flatpak.enable = true;
    asusd.enable = true;
    supergfxd.enable = true;
    power-profiles-daemon.enable = true;
    logind.settings = {
      Login = {
        KillUserProcesses = true;
      };
    }; 
    greetd = {
      enable = true;
      settings = {
      	default_session = {
      	  command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd 'uwsm start hyprland.desktop'";
      	  user = "greeter";
      	};
      };	
    };
  };
  xdg.portal = {
  	enable = true;
  	extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
  # Snap support is typically handled via appimage or flatpak in pure NixOS  
  environment.systemPackages = with pkgs; [
  	gcc 
  	automake 
  	autoconf 
  	automake 
  	pkg-config
  	binutils 
  	glibc 
  	gdb 
  	cmake 
  	strace 
  	ltrace 
  	gperf 
  	patch 
  	diffutils 
  	findutils 
  	gawk
  	gnugrep 
  	gnutar 
  	gzip
    sbctl
    coreutils
    fish
    cryptsetup
    wireguard-tools
    tor
    git
    pkgs.uwsm
    android-studio
    android-tools
    psmisc
  ];
  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "24.11";
}

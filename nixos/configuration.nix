{ config, pkgs, inputs, lib, ... }: {



  # Kernel & Performance
  boot = {
    initrd.systemd.enable = true;
    kernelModules = [ "nvidia_uvm" "amdgpu" ];
    kernelParams = [
      "nvidia.NVreg_EnableGpuFirmware=1"
      "nvidia_drm.modeset=1"
      "nvidia_drm.fbdev=1"
      "preempt=full"
      "threadirqs"
    ];
    kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
    kernel.sysctl = {
      # Memory Management
      "vm.max_map_count" = 2147483642;
      "vm.swappiness" = 180;
      "vm.page-cluster" = 0;
      "vm.vfs_cache_pressure" = 50;
      # Scheduling
      "kernel.sched_cfs_bandwidth_slice_us" = 3000;
      # Network
      "net.core.netdev_max_backlog" = 16384;
      "net.core.somaxconn" = 8192;
      "net.ipv4.tcp_fastopen" = 3;
      "net.ipv4.tcp_slow_start_after_idle" = 0;
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
    };
    loader = {
      systemd-boot = {
        enable = lib.mkForce false;
        configurationLimit = 3;
      };
      efi.canTouchEfiVariables = true;
    };
    lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
    };
  };

  networking = {
    networkmanager = {
      enable = true;
      wifi.scanRandMacAddress = true;
    };
  };

  systemd = {
    oomd.enable = false;
    tmpfiles.rules = [
      "d /home/nondeus 0700 nondeus users"
      "d /home/nondeus/AppImage 0755 nondeus users"
    ];
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
  };

  users.users.nondeus = {
    isNormalUser = true;
    hashedPasswordFile = "/persist/home/nondeus/.nix-config/password";
    extraGroups = [ "adbusers" "networkmanager" "wheel" "video" "docker" ];
  };

  programs = {
    hyprland = {
      enable = true;
      withUWSM = true;
    };
    appimage = {
      enable = true;
      binfmt = true;
    };
    kdeconnect.enable = true;
    fish.enable = true;
  };

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
    liveRestore = false;
  };

  # Application Support
  services = {
    xserver.videoDrivers = [ "nvidia" "amdgpu" ];
    geoclue2.enable = true;
    scx = {
      enable = true;
      scheduler = "scx_lavd";
    };
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

  environment.systemPackages = with pkgs; [
    sbctl
    cryptsetup
    wireguard-tools
    tor
    uwsm
    android-studio
    android-tools
    appimage-run
  ];

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      substituters = [ "https://hyprland.cachix.org" "https://nix-community.cachix.org" ];
      trusted-public-keys = [ 
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" 
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" 
      ];
      min-free = 536870912; # 512MB
      max-free = 1073741824; # 1GB
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
    optimise.automatic = true;
  };

  nixpkgs = {
    config = {
      allowUnfree = true;
      cudaSupport = true;
    };
  };

  system.stateVersion = "24.11";
}

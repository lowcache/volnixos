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



  # Security & Anonymity
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
  


  # Android & Connectivity
  users.users.nondeus = {
  	isNormalUser = true;
  	hashedPassword = "$6$TC4VPrCqV64Jitm3$2yZL1T8LhyMHM7rU7wLcKxQqhtdhhWrsRSPIOaJ7t4u2ML8pI53kBSpe/KYWx8B7xrEfLMGsKX5xp8.Oo1qTo.";
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

  # Snap support is typically handled via appimage or flatpak in pure NixOS  
  environment.systemPackages = with pkgs; [
  	gcc 
  	automake 
  	autoconf 
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
    fd
    micro
    python3
    uwsm
    android-studio
    android-tools
    psmisc
    appimage-run
  ];
  
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };
    
  nixpkgs = {
    config = {
      allowUnfree = true;
      cudaSupport = true;
    };
  };
  
  system.stateVersion = "24.11";
}

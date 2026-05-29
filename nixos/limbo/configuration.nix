{ config, pkgs, inputs, lib, ... }: {

  # Kernel & Performance (Clean & Standard)
  boot = {
    initrd.systemd.enable = true;
    kernelModules = [ ];
    kernelParams = [ ];
    kernel.sysctl = {
      # Memory Management
      "vm.max_map_count" = 2147483642;
      "vm.swappiness" = 180;
      "vm.page-cluster" = 0;
      "vm.vfs_cache_pressure" = 50;
      # Panic Recovery
      "kernel.panic" = 10;
      "kernel.panic_on_oops" = 1;
      "kernel.sysrq" = 502;
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
        enable = true;
        configurationLimit = 10;
      };
      efi.canTouchEfiVariables = true;
    };
  };

  networking = {
    hostName = "limbo";
    networkmanager = {
      enable = true;
      wifi.scanRandMacAddress = true;
    };
  };

  systemd = {
    oomd.enable = false;
    tmpfiles.rules = [
      "d /home/lowcache 0700 lowcache users"
      "d /home/lowcache/AppImage 0755 lowcache users"
    ];
    settings.Manager = {
      DefaultTimeoutStopSec = "10s";
      DefaultRestartSec = "1s";
    };
    user.extraConfig = "DefaultTimeoutStopSec=5s";
  };

  users = {
    users = {
      root = {
        initialPassword = "root";
      };
      lowcache = {
        isNormalUser = true;
        initialPassword = "nixos";
        extraGroups = [ "adbusers" "networkmanager" "wheel" "video" "docker" ];
      };
    };
  };

  programs = {
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        libgcc.lib
        libxcrypt-legacy
        libx11
        libxcomposite
        libxdamage
        libxext
        libxfixes
        libxrandr
        libxrender
        libxv
        libxcb
        openssl.out
        fuse3
        icu
        nss
        nspr
        atk
        gtk3
        at-spi2-atk
        at-spi2-core
        libdrm
        mesa
        libgbm
        glib
        pango
        cairo
        alsa-lib
        dbus
        curl
        expat
        libvdpau
        libva
        vulkan-loader
        libGL
        wayland
        libxkbcommon
        cups
      ];
    };
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

  virtualisation = {
    docker = {
      enable = true;
      autoPrune.enable = true;
      liveRestore = false;
    };
  };

  # Application Support
  services = {
    # Open WebUI Service
    open-webui = {
      enable = true;
      port = 8080;
      environment = {
        OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
      };
    };

    # Ollama Service
    ollama = {
      enable = true;
    };

    timesyncd.enable = true;
    geoclue2.enable = true;
    flatpak.enable = true;
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
    cryptsetup
    wireguard-tools
    tor
    uwsm
    android-studio
    android-tools
    appimage-run
    vulkan-tools
    libva-utils
    nvd
    gnupg
    ffmpeg
  ];

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      substituters = [
        "https://hyprland.cachix.org"
        "https://nix-community.cachix.org"
        "https://cache.lix.systems"
      ];
      trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.lix.systems:aBnZU3F19808R5N0sczBmsWwI5YI+433R9M2iS2Hcy4="
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
    };
  };

  system.stateVersion = "24.11";

  time.timeZone = "America/Chicago";
}

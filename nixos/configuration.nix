
{ config, pkgs, inputs, lib, ... }: {

  imports = [
    ./vms.nix
  ];

  # Kernel & Performance
  boot = {
    initrd.systemd.enable = true;
    kernelModules = [ "amdgpu" "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
    kernelParams = [
      "nvidia-drm.modeset=1"
      "nvidia.NVreg_EnableGpuFirmware=1"
      #"nvidia.NVreg_PreserveVideoMemoryAllocations=1"
      "preempt=full"
      "threadirqs"
      "sysrq_always_enabled=1"
      # Ryzen CPU & Hybrid GPU Stability Parameters
      "amdgpu.dcdebugmask=0x10"
      "amdgpu.gpu_recovery=1"
      "processor.max_cstate=1"
      #"pcie_port_pm=off"
    ];
    kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
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
        enable = lib.mkForce false;
        configurationLimit = 10;
      };
      efi.canTouchEfiVariables = true;
    };
    lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
    };
  };

  networking = {
    hostName = "infernalnix";
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
      "d /home/lowcache/Storage/ai-generation 0755 lowcache users"
      "d /home/lowcache/Storage/ai-generation/fooocus 0755 lowcache users"
      "d /home/lowcache/Storage/ai-generation/forge 0755 lowcache users"
    ];
    services = {
      #greetd.serviceConfig = {
      #StandardInput = "tty";
      #StandardOutput = "tty";
      #StandardError = "journal";
      #TTYReset = true;
      #TTYHangup = true;
      #TTYDeallocate = true;
      #};
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
      # Run Ollama as your user to avoid permission issues in ~/Storage
      ollama.serviceConfig = {
        User = "lowcache";
        Group = "users";
        ProtectHome = lib.mkForce false;
        Environment = [
          "OLLAMA_ORIGINS=*"
          "OLLAMA_FLASH_ATTENTION=1"
          "OLLAMA_NUM_PARALLEL=1"
          "CUDA_VISIBLE_DEVICES=0"
        ];
      };
      # Inject ffmpeg into open-webui's PATH environment for dynamic user execution
      open-webui.path = [ pkgs.ffmpeg ];
    };
    settings.Manager = {
      DefaultTimeoutStopSec = "10s";
      DefaultRestartSec = "1s";
    };
    user.extraConfig = "DefaultTimeoutStopSec=5s";
  };

  users = {
    users = {
      root = {
        hashedPasswordFile = config.sops.secrets.root_password.path;
      };
      lowcache = {
        isNormalUser = true;
        hashedPasswordFile = config.sops.secrets.user_password.path;
        extraGroups = [ "adbusers" "networkmanager" "wheel" "video" "docker" ];
      };
    };
  };

  sops = {
    defaultSopsFile = ./secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      user_password = {
        neededForUsers = true;
      };
      root_password = {
        neededForUsers = true;
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
        # GPU / Graphics
        libvdpau
        libva
        vulkan-loader
        libGL
        egl-wayland
        wayland
        libxkbcommon
        linuxPackages.nvidia_x11.out
        cudaPackages.cuda_cudart
        cudaPackages.libcublas
        cudaPackages.nccl
        libglvnd
        mesa
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
    oci-containers = {
      backend = "docker";
      containers = {
        "fooocus" = {
          image = "ghcr.io/lllyasviel/fooocus:latest";
          autoStart = false;
          ports = [ "7865:7865" ];
          volumes = [ "/home/lowcache/Storage/ai-generation/fooocus:/content/data" ];
          environment = {
            CMDARGS = "--listen";
            DATADIR = "/content/data";
            config_path = "/content/data/config.txt";
            path_checkpoints = "/content/data/models/checkpoints/";
            path_loras = "/content/data/models/loras/";
            path_outputs = "/content/data/outputs/";
          };
          extraOptions = [ "--device" "nvidia.com/gpu=0" ];
        };
        "forge" = {
          image = "ghcr.io/ai-dock/stable-diffusion-webui-forge:latest-cuda";
          autoStart = false;
          ports = [ "7866:17860" ];
          volumes = [ "/home/lowcache/Storage/ai-generation/forge:/workspace" ];
          environment = {
            # AI-Dock Specific Vars
            BASE_PORT = "17860";
            WORKSPACE = "/workspace";
            # WebUI Specific Vars
            FORGE_ARGS = "--listen --port 17860";
          };
          extraOptions = [ "--device" "nvidia.com/gpu=0" ];
        };
      };
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
      package = pkgs.ollama-cuda;
      home = "/home/lowcache";
      models = "/home/lowcache/Storage/ollama/models";
    };

    timesyncd.enable = true;
    xserver.videoDrivers = [ "nvidia" "amdgpu" ];
    geoclue2.enable = true;
    scx = {
      enable = false;
      scheduler = "scx_bpfland";
    };
    flatpak.enable = true;
    asusd.enable = true;
    supergfxd.enable = false;
    power-profiles-daemon.enable = false;
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
    vulkan-tools
    libva-utils
    nvd
    nvtopPackages.nvidia
    nvidia-vaapi-driver
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
        "https://cuda-maintainers.cachix.org"
      ];
      trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.lix.systems:aBnZU3F19808R5N0sczBmsWwI5YI+433R9M2iS2Hcy4="
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
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

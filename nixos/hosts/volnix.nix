# The volnix instance: machine identity, feature switches, and host-specific
# option values. How each feature WORKS lives in ../modules/; this file says
# what THIS machine IS.
{
  config,
  ...
}:
{
  imports = [
    ../modules
    ../vms.nix
    ../windows-vm.nix
    ../phone-agent
  ];

  networking.hostName = "volnix";
  time.timeZone = "America/Chicago";
  system.stateVersion = "24.11"; # do not bump

  vol = {
    anon-mode.enable = true;

    # NVIDIA (01:00.1) and AMD (66:00.1) HDMI audio sit on `pro-audio`, which
    # publishes one sink per PCM and buries the two outputs actually in use.
    # Realtek ALC256 (66:00.6) is the analog card and stays live.
    audio = {
      enable = true;
      parkedCards = [
        "alsa_card.pci-0000_01_00.1"
        "alsa_card.pci-0000_66_00.1"
      ];
    };

    # External 2 TB Seagate BUP Slim, bound by serial so it fires in any port
    # and never for another USB disk. Partition labels: RESCUE / MODELS / VOLBAK.
    backup = {
      enable = true;
      driveSerial = "00000000NAEA54PH";
      passwordFile = config.sops.secrets.restic_password.path;

      # Two sources, two devices. /persist carries the machine (including
      # ~/.nix-config); ~/Storage is the second NVMe. The mkOutOfStoreSymlinks
      # from /persist into Storage are stored AS symlinks, so nothing is
      # captured twice by listing both.
      paths = [
        "/persist"
        "/home/lowcache/Storage"
      ];

      exclude = [
        "/persist/swapfile" # 17G of nothing
        "/persist/lost+found"
        "/persist/var/lib/docker" # re-pullable images
        "/persist/var/lib/waydroid" # re-downloadable system/vendor img
        "/persist/home/lowcache/.local/share/waydroid"
        "/home/lowcache/Storage/.cache" # 30G, XDG_CACHE_HOME target
        "/home/lowcache/Storage/tmp" # 23G, the TMPDIR scratch volume
        "/home/lowcache/Storage/libvirt" # Windows VM disks, reinstallable
        "/home/lowcache/Storage/lost+found"
        # Weights go to the MODELS partition instead — see models.mirrors.
        # fooocus/outputs is deliberately NOT excluded: that is artwork, and
        # ~/Pictures/fromAi/outputs symlinks into it.
        "/home/lowcache/Storage/ollama"
        "/home/lowcache/Storage/ai-generation/fooocus/models"
        "/home/lowcache/Storage/ai-generation/forge/models"
        "**/node_modules"
        "**/__pycache__"
        "**/.venv"
      ];

      models = {
        enable = true;
        mirrors = {
          ollama = "/home/lowcache/Storage/ollama";
          fooocus-models = "/home/lowcache/Storage/ai-generation/fooocus/models";
          forge-models = "/home/lowcache/Storage/ai-generation/forge/models";
        };
      };
    };

    ai-stack = {
      ollama.enable = true;
      ollama.exposeToTailscaleVm = true;
      open-webui.enable = true;
    };
  };

  # Phone agent (S26 Ultra MCP integration, Phase 8). Bearer token is the
  # laptop's sops-materialized copy of the phone's token (matches the phone's
  # ~/.config/phone-agent/token). phoneTailscaleIP is stable per node key.
  phone-agent = {
    enable = true;
    phoneTailscaleIP = "100.101.229.9";
    tokenFile = config.sops.secrets.phone_agent_token.path;
  };
}

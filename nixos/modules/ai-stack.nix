# Ollama + Open WebUI. The tailscale exposure option couples the interface
# bind and the firewall exception so they cannot drift apart.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  cfg = config.vol.ai-stack;
  ollamaDir = "/home/${username}/Storage/ollama";
in
{
  options.vol.ai-stack = {
    ollama = {
      enable = lib.mkEnableOption "Ollama (CUDA)";

      exposeToTailscaleVm = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Bind 0.0.0.0 AND open 11434 only on vm-tailscale, so the tailscale
          MicroVM guest can DNAT tailnet :11434 to the host for the phone agent.
          WAN stays closed; loopback consumers (open-webui) keep working.
        '';
      };

      tailnetClients = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Tailnet IPs allowed to reach 11434 through vm-tailscale. The guest only
          DNATs, so the peer's own 100.x address is what the host firewall sees.
        '';
      };
    };

    open-webui.enable = lib.mkEnableOption "Open WebUI fronting local Ollama";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.ollama.enable {
      # Runs as your user so ~/Storage/ollama stays yours, but sees only that
      # directory: the rest of /home is an empty tmpfs inside the unit.
      services.ollama = {
        enable = true;
        package = pkgs.ollama-cuda;
        home = ollamaDir;
        modelsDir = "${ollamaDir}/models";
        host = lib.mkIf cfg.ollama.exposeToTailscaleVm "0.0.0.0";
      };

      systemd.services.ollama.serviceConfig = {
        User = username;
        Group = "users";
        # Upstream sets ProtectHome = true; tmpfs + BindPaths exposes only ollamaDir.
        ProtectHome = lib.mkForce "tmpfs";
        BindPaths = [ ollamaDir ];
        # No OLLAMA_ORIGINS: `*` let any web page drive the API through the
        # browser. The default admits local origins; nothing here needs more.
        Environment = [
          "OLLAMA_FLASH_ATTENTION=1"
          "OLLAMA_NUM_PARALLEL=1"
          "CUDA_VISIBLE_DEVICES=0"
          "OLLAMA_KEEP_ALIVE=5m"
        ];
      };
    })

    (lib.mkIf cfg.ollama.exposeToTailscaleVm {
      # Reach Ollama (bound per services.ollama.host) only via the tailscale
      # MicroVM guest, and only from tailnetClients: the guest DNATs every
      # tailnet peer, so the interface alone would admit the whole tailnet.
      networking.firewall.extraCommands = lib.concatMapStrings (ip: ''
        iptables -A nixos-fw -i vm-tailscale -s ${ip} -p tcp --dport 11434 -j nixos-fw-accept
      '') cfg.ollama.tailnetClients;
    })

    (lib.mkIf cfg.open-webui.enable {
      # Open WebUI Service
      services.open-webui = {
        enable = true;
        port = 8080;
        environment = {
          OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
        };
      };
      # Inject ffmpeg into open-webui's PATH environment for dynamic user execution
      systemd.services.open-webui.path = [ pkgs.ffmpeg ];
    })
  ];
}

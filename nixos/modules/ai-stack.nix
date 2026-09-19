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
in
{
  options.vol.ai-stack = {
    ollama.enable = lib.mkEnableOption "Ollama (CUDA)";

    ollama.exposeToTailscaleVm = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Bind 0.0.0.0 AND open 11434 only on vm-tailscale, so the tailscale
        MicroVM guest can DNAT tailnet :11434 to the host for the phone agent.
        WAN stays closed; loopback consumers (open-webui) keep working.
      '';
    };

    open-webui.enable = lib.mkEnableOption "Open WebUI fronting local Ollama";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.ollama.enable {
      # Run Ollama as your user to avoid permission issues in ~/Storage
      services.ollama = {
        enable = true;
        package = pkgs.ollama-cuda;
        home = "/home/${username}";
        modelsDir = "/home/${username}/Storage/ollama/models";
        host = lib.mkIf cfg.ollama.exposeToTailscaleVm "0.0.0.0";
      };

      systemd.services.ollama.serviceConfig = {
        User = username;
        Group = "users";
        ProtectHome = lib.mkForce false;
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
      # Reach Ollama (bound per services.ollama.host) only from the tailscale
      # MicroVM guest, which DNATs tailnet :11434 → the host for the phone
      # agent. Interface-scoped: WAN stays closed, loopback is exempt.
      networking.firewall.interfaces."vm-tailscale".allowedTCPPorts = [ 11434 ];
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

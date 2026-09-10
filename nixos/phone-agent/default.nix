{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.phone-agent;
in
{
  imports = [
    # ./mcp-gateway.nix intentionally removed (2026-08-24). It existed only to
    # ship a gateway-peer.example.yaml and an unconditional warning telling the
    # operator to register phone-agent as an mcp-gateway backend. That example
    # used a stale schema (transport:/url:/namespace: are not valid mcp-gateway
    # 3.3.2 keys) and the gateway route failed its auth test. phone-agent is
    # deliberately kept as a standalone MCP server, not fronted by the gateway,
    # so there is nothing to register and no warning to emit.
    ./ingest-sync.nix
    ./ingest-watcher.nix
    ./proximity.nix
    ./network-routing.nix
    ./push.nix
  ];

  options.phone-agent = {
    enable = lib.mkEnableOption "Phone agent (Galaxy S26 Ultra MCP integration)";

    phoneTailscaleIP = lib.mkOption {
      type = lib.types.str;
      default = "100.101.229.9";
      description = "Tailscale IP of the phone MCP server (from the Tailscale Android app).";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8462;
    };
    tokenFile = lib.mkOption {
      # str, not path: a sops runtime secret path must NOT be copied into the
      # world-readable nix store (types.path would coerce a path literal in).
      type = lib.types.str;
      example = "config.sops.secrets.phone_agent_token.path";
      description = "Path to the bearer token file (sops-nix secret; never world-readable).";
    };
    ollamaHost = lib.mkOption {
      type = lib.types.str;
      default = "volnix";
      description = "Hostname the phone uses to reach this laptop's Ollama (documentation only).";
    };
    ingestDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/lowcache/ingest";
      description = "Laptop-side ingest directory that mirrors staged phone output.";
    };

    enableIngestSync = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    enableIngestWatcher = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    enableProximityLock = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Lock the laptop when the phone leaves the desk (lock only — no auto-unlock).";
    };
    enableNetworkRouting = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.tokenFile != null;
        message = "phone-agent.tokenFile must be set (sops-nix secret path).";
      }
    ];

    environment.systemPackages =
      let
        rawScript = pkgs.writeShellScriptBin "phone-agent-raw" ''
          if [ $# -lt 1 ]; then
            echo "Usage: phone-agent <tool-name> [arguments-json]"
            echo "  phone-agent phone.system.ping"
            echo "  phone-agent phone.npu.transcribe '{\"audio_path\":\"/tmp/test.wav\"}'"
            exit 1
          fi
          ${./scripts/phone-mcp-call.sh} "$@" | ${pkgs.jq}/bin/jq 'if (.result.isError // false) then {error: .result.content[0].text} elif .result then (.result.content[0].text | fromjson) else . end'
        '';
      in
      [
        (pkgs.runCommand "phone-agent" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
          mkdir -p $out/bin
          makeWrapper ${rawScript}/bin/phone-agent-raw $out/bin/phone-agent \
            --prefix PATH : ${
              lib.makeBinPath [
                pkgs.curl
                pkgs.coreutils
                pkgs.bash
              ]
            } \
            --set PHONE_IP "${cfg.phoneTailscaleIP}" \
            --set PHONE_PORT "${toString cfg.port}" \
            --set PHONE_TOKEN_FILE "${toString cfg.tokenFile}"
        '')
      ];
  };
}

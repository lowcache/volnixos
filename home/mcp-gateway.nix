# mcp-gateway, the shared MCP aggregation layer. gateway.yaml (persisted
# ~/.config/mcp-gateway) expands ${GITHUB_TOKEN}/${GITHUB_PERSONAL_ACCESS_TOKEN}
# and ${TB_AUTH_TOKEN}; all are read from sops at start, never stored.
{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  start = pkgs.writeShellApplication {
    name = "mcp-gateway-start";
    text = ''
      GITHUB_TOKEN=$(< ${osConfig.sops.secrets.gh_token.path})
      export GITHUB_TOKEN GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_TOKEN"
      TB_AUTH_TOKEN=$(< ${osConfig.sops.secrets.tb_auth_token.path})
      export TB_AUTH_TOKEN
      exec ${lib.getExe pkgs.mcp-gateway} serve -c "$HOME/.config/mcp-gateway/gateway.yaml"
    '';
  };
in
{
  systemd.user.services.mcp-gateway = {
    Unit = {
      Description = "Universal MCP Gateway";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = lib.getExe start;
      Restart = "always";
      RestartSec = 10;
      # Backends are spawned by name (npx, uvx, mcp-* servers).
      Environment = [
        "PATH=/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin:/nix/var/nix/profiles/default/bin"
      ];
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Reclaim the paths the old hand-written unit and its enable link occupied.
  xdg.configFile = {
    "systemd/user/mcp-gateway.service".force = true;
    "systemd/user/default.target.wants/mcp-gateway.service".force = true;
  };
}

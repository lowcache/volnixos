# tb-bridge: localhost proxy between the Thunderbird AI Bridge add-on (WebSocket
# :7701) and tb / tb-mcp (HTTP :7700). Stateless; requires the sops tb_auth_token.
{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  start = pkgs.writeShellApplication {
    name = "tb-bridge-start";
    text = ''
      TB_AUTH_TOKEN=$(< ${osConfig.sops.secrets.tb_auth_token.path})
      export TB_AUTH_TOKEN
      exec ${lib.getExe pkgs.thunderbird-cli-bridge}
    '';
  };
in
{
  systemd.user.services.tb-bridge = {
    Unit = {
      Description = "Thunderbird CLI bridge";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.getExe start;
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}

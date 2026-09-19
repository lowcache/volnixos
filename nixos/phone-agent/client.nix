# The phone MCP client, configured once. Every phone-agent unit reaches the
# phone through `call`, so the address and token are declared in one place.
{
  lib,
  pkgs,
  cfg,
}:
{
  url = "http://${cfg.phoneTailscaleIP}:${toString cfg.port}";
  call = pkgs.writeShellScript "phone-call" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.curl
        pkgs.coreutils
      ]
    }:$PATH
    export PHONE_IP=${cfg.phoneTailscaleIP} PHONE_PORT=${toString cfg.port}
    export PHONE_TOKEN_FILE=${toString cfg.tokenFile}
    exec ${pkgs.bash}/bin/bash ${./scripts/phone-mcp-call.sh} "$@"
  '';
}

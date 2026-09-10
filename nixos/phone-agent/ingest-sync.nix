{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.phone-agent;
  syncScript = pkgs.writeShellScript "phone-ingest-sync" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.curl
        pkgs.coreutils
        pkgs.bash
      ]
    }:$PATH
    export PHONE_IP=${cfg.phoneTailscaleIP} PHONE_PORT=${toString cfg.port}
    export PHONE_TOKEN_FILE=${toString cfg.tokenFile}
    call=${./scripts/phone-mcp-call.sh}
    dest="${cfg.ingestDir}/staged"; mkdir -p "$dest"

    # Skip silently if the phone is unreachable.
    curl -sf --max-time 3 "http://$PHONE_IP:$PHONE_PORT/health" >/dev/null || exit 0

    listing=$("$call" phone.ingest.list '{"since":null,"limit":50}')
    echo "$listing" | ${pkgs.jq}/bin/jq -c '.result.content[0].text | fromjson | .files[]?' | while read -r f; do
      name=$(echo "$f" | ${pkgs.jq}/bin/jq -r .name)
      want=$(echo "$f" | ${pkgs.jq}/bin/jq -r .sha256)
      [ -e "$dest/$name" ] && continue
      # The fetch carries the file itself; size, not reachability, decides how
      # long it takes. Reachability was already settled by the health check.
      payload=$(PHONE_TIMEOUT=''${PHONE_FETCH_TIMEOUT:-300} "$call" phone.ingest.fetch "{\"name\":\"$name\",\"delete_after\":true}")
      echo "$payload" | ${pkgs.jq}/bin/jq -r '.result.content[0].text | fromjson | .content_b64' | base64 -d > "$dest/.tmp.$name"
      got=$(sha256sum "$dest/.tmp.$name" | cut -d' ' -f1)
      if [ "$got" = "$want" ]; then mv "$dest/.tmp.$name" "$dest/$name";
      else rm -f "$dest/.tmp.$name"; echo "sha mismatch for $name" >&2; fi
    done
  '';
in
{
  config = lib.mkIf (cfg.enable && cfg.enableIngestSync) {
    systemd.user.services.phone-ingest-sync = {
      description = "Pull staged files from the phone agent (MCP ingest.list/fetch)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${syncScript}";
      };
    };
    systemd.user.timers.phone-ingest-sync = {
      description = "Periodic phone ingest sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "2min";
      };
    };
  };
}

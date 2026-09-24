{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.phone-agent;
  client = import ./client.nix { inherit lib pkgs cfg; };
  syncScript = pkgs.writeShellScript "phone-ingest-sync" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.curl
        pkgs.coreutils
        pkgs.jq
      ]
    }:$PATH
    call=${client.call}
    dest="${cfg.ingestDir}/staged"; mkdir -p "$dest"

    # Skip silently if the phone is unreachable.
    curl -sf --max-time 3 "${client.url}/health" >/dev/null || exit 0

    # The fetch carries the file itself; size, not reachability, decides how
    # long it takes. Reachability was already settled by the health check.
    fetch() { PHONE_TIMEOUT=''${PHONE_FETCH_TIMEOUT:-300} "$call" phone.ingest.fetch "{\"name\":\"$1\",\"delete_after\":$2}"; }
    # Tool errors arrive as HTTP 200 with {"error": ...}; only a real payload has sha256.
    retire() { fetch "$1" true | jq -e '.result.content[0].text | fromjson | .sha256' >/dev/null; }

    listing=$("$call" phone.ingest.list '{"since":null,"limit":50}')
    files=$(echo "$listing" | jq -c '.result.content[0].text | fromjson | .files[]?')

    # A failed file is counted, not fatal, so it cannot strand the rest of the
    # batch; the unit still exits non-zero so the failure stays visible.
    failed=0
    while read -r f; do
      [ -n "$f" ] || continue
      name=$(echo "$f" | jq -r .name)
      want=$(echo "$f" | jq -r .sha256)
      if [ -e "$dest/$name" ]; then
        # Verified on an earlier run whose retire failed. A different hash is a
        # new file reusing the name: leave the phone's copy alone.
        if [ "$(sha256sum "$dest/$name" | cut -d' ' -f1)" != "$want" ]; then
          echo "name collision for $name; left on phone" >&2
        elif ! retire "$name"; then
          echo "retire failed for $name" >&2; failed=$((failed + 1))
        fi
        continue
      fi
      # Retire only after the hash checks out: retiring on the first fetch lost
      # the file whenever that transfer failed. Retiring sends it a second time.
      if ! fetch "$name" false | jq -er '.result.content[0].text | fromjson | .content_b64' | base64 -d > "$dest/.tmp.$name"; then
        rm -f "$dest/.tmp.$name"; echo "fetch failed for $name" >&2; failed=$((failed + 1)); continue
      fi
      if [ "$(sha256sum "$dest/.tmp.$name" | cut -d' ' -f1)" != "$want" ]; then
        rm -f "$dest/.tmp.$name"; echo "sha mismatch for $name" >&2; failed=$((failed + 1)); continue
      fi
      mv "$dest/.tmp.$name" "$dest/$name"
      retire "$name" || { echo "retire failed for $name" >&2; failed=$((failed + 1)); }
    done <<< "$files"
    [ "$failed" -eq 0 ] || { echo "$failed file(s) failed; will retry next run" >&2; exit 1; }
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
      unitConfig.ConditionUser = cfg.user;
    };
    systemd.user.timers.phone-ingest-sync = {
      description = "Periodic phone ingest sync";
      unitConfig.ConditionUser = cfg.user;
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "2min";
      };
    };
  };
}

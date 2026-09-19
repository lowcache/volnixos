{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.phone-agent;
  client = import ./client.nix { inherit lib pkgs cfg; };
  daemon = pkgs.writeShellScriptBin "phone-proximity-daemon" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.curl
        pkgs.coreutils
        pkgs.niri
      ]
    }:$PATH
    call=${client.call}
    log() { ${pkgs.util-linux}/bin/logger -t phone-proximity "$1"; }
    PREV=""
    while true; do
      curl -sf --max-time 3 "${client.url}/health" >/dev/null || { sleep ${toString cfg.proximityIntervalSec}; continue; }
      R=$("$call" phone.sensor.read_imu '{"sample_count":10}' 2>/dev/null || echo '{}')
      STATE=$(echo "$R" | ${pkgs.jq}/bin/jq -r '(try (.result.content[0].text | fromjson | .inference) catch null) // "unknown"')
      case "$STATE" in
        walking|in_pocket)
          if [ "$PREV" = "on_desk" ] || [ "$PREV" = "stationary" ]; then
            command -v niri >/dev/null && niri msg action lock-screen
            log "LOCK: $PREV -> $STATE"
          fi ;;
      esac
      ${lib.optionalString cfg.allowUnlock ''
        # EXPERIMENTAL and disabled by default. There is no safe programmatic
        # unlock; this block intentionally does nothing but log intent.
        case "$STATE" in on_desk|stationary)
          [ "$PREV" = "walking" ] || [ "$PREV" = "in_pocket" ] && log "UNLOCK-INTENT (no-op): $PREV -> $STATE" ;;
        esac
      ''}
      PREV="$STATE"; sleep ${toString cfg.proximityIntervalSec}
    done
  '';
in
{
  options.phone-agent = {
    proximityIntervalSec = lib.mkOption {
      type = lib.types.int;
      default = 5;
    };
    allowUnlock = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "EXPERIMENTAL: no safe programmatic unlock exists; leaving this on only logs intent.";
    };
  };
  config = lib.mkIf (cfg.enable && cfg.enableProximityLock) {
    systemd.user.services.phone-proximity-daemon = {
      description = "Phone proximity-based laptop lock (lock only)";
      serviceConfig = {
        ExecStart = "${daemon}/bin/phone-proximity-daemon";
        Restart = "on-failure";
        RestartSec = 10;
      };
      wantedBy = [ "default.target" ];
    };
  };
}

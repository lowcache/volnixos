{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.phone-agent;
  client = import ./client.nix { inherit lib pkgs cfg; };
  script = pkgs.writeShellScriptBin "phone-network-routing" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}:$PATH
    call=${client.call}
    R=$("$call" phone.sensor.read_modem '{}' 2>/dev/null || echo '{}')
    SSID=$(echo "$R" | ${pkgs.jq}/bin/jq -r '(try (.result.content[0].text | fromjson | .ssid) catch null) // "unknown"')
    case "$SSID" in
      "HomeWiFi"|"MyHomeNetwork") PROFILE=home ;;
      "CoffeeShop_WiFi"|"University_WiFi") PROFILE=untrusted ;;
      *) PROFILE=secure ;;
    esac
    dir=/run/user/$(id -u)/phone-agent; mkdir -p "$dir"
    echo "$PROFILE" > "$dir/network-profile"
    # [CEILING]: profile file + optional hook only; net-gate microvm wiring TBD.
    systemctl --user start "phone-network-profile@$PROFILE.service" 2>/dev/null || true
  '';
in
{
  config = lib.mkIf (cfg.enable && cfg.enableNetworkRouting) {
    systemd.user.services.phone-network-routing = {
      description = "Derive network routing profile from phone modem state";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${script}/bin/phone-network-routing";
      };
    };
  };
}

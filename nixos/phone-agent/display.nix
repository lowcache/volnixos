{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.phone-agent;
  # Must match the niri window rule in dots/niri/config.kdl (title + output).
  output = "HDMI-A-1";
  title = "phone-display";
  daemon = pkgs.writeShellApplication {
    name = "phone-display";
    runtimeInputs = [
      pkgs.android-tools
      pkgs.scrcpy
      pkgs.niri
      pkgs.jq
      pkgs.coreutils
    ];
    bashOptions = [ ];
    text = ''
      while true; do
        adb wait-for-usb-device
        # USB on this phone flaps; only act on a link that survives a few seconds.
        sleep 3
        adb -d get-state >/dev/null 2>&1 || continue
        if niri msg --json outputs | jq -e 'has("${output}")' >/dev/null; then
          rc=0
          scrcpy -d --window-title=${title} ${lib.escapeShellArgs cfg.displayArgs} || rc=$?
          # 0 = window closed by hand: stay off until the next plug. Else retry.
          [ "$rc" -eq 0 ] || { sleep 3; continue; }
        fi
        adb wait-for-usb-disconnect
      done
    '';
  };
in
{
  options.phone-agent = {
    enableDisplay = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show a phone desktop (DeX) on ${output} via scrcpy while the phone is on USB.";
    };
    displayArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--new-display=1920x1080/240"
        "--stay-awake"
      ];
      description = ''
        Extra scrcpy arguments. The default virtual display gets Samsung DeX; to hand it to
        another window manager add "--no-vd-system-decorations" and "--start-app=<package>".
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.enableDisplay) {
    systemd.user.services.phone-display = {
      description = "Phone desktop on ${output} while the phone is on USB";
      serviceConfig = {
        ExecStart = "${daemon}/bin/phone-display";
        # The phone-side server can outlive a killed client and keep DeX's display alive.
        ExecStopPost = "-${pkgs.android-tools}/bin/adb -d shell pkill -f com.genymobile.scrcpy.Server";
        Restart = "on-failure";
        RestartSec = 10;
      };
      unitConfig.ConditionUser = cfg.user;
      # Needs WAYLAND_DISPLAY/NIRI_SOCKET, exported once the compositor is up.
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
    };
  };
}

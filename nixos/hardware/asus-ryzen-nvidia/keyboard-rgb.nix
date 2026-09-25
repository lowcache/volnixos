# TUF keyboard RGB, written straight to the kernel's asus-wmi interface.
#
# WHY NOT asusd. rog-aura 6.5.0 registers exactly one mode (Static) for the
# "ASUS TUF Gaming A16" product family, so `asusctl aura effect breathe` and
# friends return success and change nothing -- verified by sweeping all twelve
# asusctl effects and watching current_mode never leave Static. The EC itself
# does more than that: writing /sys/class/leds/asus::kbd_backlight/kbd_rgb_mode
# directly gets modes 0-3 working and 4-7 doing nothing. So this bypasses the
# daemon rather than configuring it; services.asusd.auraConfig cannot express a
# mode asusd does not believe exists.
#
# Mode names follow the usual asus-wmi mapping. 0/1/2 were confirmed by eye;
# 3 fires but which effect it actually is was never pinned down.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.asus.keyboardRgb;

  led = "/sys/class/leds/asus::kbd_backlight/kbd_rgb_mode";

  modeIds = {
    static = 0;
    breathe = 1;
    colour-cycle = 2;
    rainbow = 3;
  };
  speedIds = {
    low = 0;
    med = 1;
    high = 2;
  };

  # kbd_rgb_mode_index reports the field order: cmd mode red green blue speed.
  # cmd=1 persists into the EC so the mode survives a cold boot on its own;
  # the units below exist because asusd re-asserts Static over the top.
  apply = pkgs.writeShellScript "asus-keyboard-rgb" ''
    c='${cfg.colour}'
    printf '%d %d %d %d %d %d\n' \
      ${if cfg.persistToEc then "1" else "0"} \
      ${toString modeIds.${cfg.mode}} \
      $((16#''${c:0:2})) $((16#''${c:2:2})) $((16#''${c:4:2})) \
      ${toString speedIds.${cfg.speed}} \
      > ${led}
  '';

  unit = {
    description = "ASUS TUF keyboard RGB mode (asusd only drives Static here)";
    # Ordered after asusd because asusd writes Static on startup and would
    # otherwise land last.
    after = [ "asusd.service" ];
    wants = [ "asusd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = apply;
    };
  };
in
{
  options.hardware.asus.keyboardRgb = {
    enable = lib.mkEnableOption "TUF keyboard RGB effects via asus-wmi";

    mode = lib.mkOption {
      type = lib.types.enum (lib.attrNames modeIds);
      default = "colour-cycle";
      description = "Effect the EC runs. Modes 4-7 are rejected by this controller.";
    };

    colour = lib.mkOption {
      type = lib.types.strMatching "[0-9a-fA-F]{6}";
      default = "ff7a00";
      description = "RRGGBB, no leading '#'. Ignored by modes that generate their own colours.";
    };

    speed = lib.mkOption {
      type = lib.types.enum (lib.attrNames speedIds);
      default = "med";
      description = "Effect speed for the animated modes.";
    };

    persistToEc = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Write with cmd=1 so the EC keeps the mode across a power cycle. Set
        false to apply it for this boot only and leave firmware state alone.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.asus-keyboard-rgb = unit // {
      wantedBy = [ "multi-user.target" ];
    };

    # Resume re-initialises the LED controller, so the mode has to be
    # rewritten on the way out of sleep. After= on the sleep targets is what
    # orders this to resume rather than suspend.
    systemd.services.asus-keyboard-rgb-resume = unit // {
      after = unit.after ++ [
        "suspend.target"
        "hibernate.target"
        "hybrid-sleep.target"
      ];
      wantedBy = [
        "suspend.target"
        "hibernate.target"
        "hybrid-sleep.target"
      ];
    };
  };
}

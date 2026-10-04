# /persist inside a LUKS2 container. /boot and /nix stay plaintext; the root is
# tmpfs, so /persist is the only place machine state and secrets live at rest.
# The container is created by ~/Storage/luks-migration (live-USB procedure),
# with its UUID pinned in advance so this config can be built before it exists.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.vol.persistLuks;
  gate = cfg.stickGate;
  keyFile = "/run/cryptsetup-keys.d/cryptpersist.key";
  cryptUnit = "systemd-cryptsetup@cryptpersist.service";

  chordgate = pkgs.runCommandCC "chordgate" { } ''
    cp ${./chordgate}/*.c .
    $CC -O2 -Wall -Wextra -Wno-unused-function -o test test.c
    ./test
    mkdir -p $out/bin
    $CC -O2 -Wall -Wextra -o $out/bin/chordgate chordgate.c
  '';
in
{
  options.vol.persistLuks = {
    enable = lib.mkEnableOption "LUKS2 encryption of the /persist partition";
    uuid = lib.mkOption {
      type = lib.types.str;
      description = "UUID of the LUKS2 header (fixed at `cryptsetup luksFormat --uuid`).";
    };

    # Stick gate: unlock key = 64-byte blob on a USB stick ‖ a held-modifier key
    # chord read from evdev in the initrd. Any failure falls through to the prompt.
    stickGate = {
      enable = lib.mkEnableOption "USB-stick blob + key-chord unlock of /persist";
      device = lib.mkOption {
        type = lib.types.str;
        description = "Stable /dev/disk/by-id path of the key stick.";
      };
      offset = lib.mkOption {
        type = lib.types.ints.unsigned;
        description = "Byte offset of the blob on the stick.";
      };
      stickWait = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 10;
        description = "Seconds to wait for the stick before falling back to the prompt.";
      };
      timeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 60;
        description = "Seconds to wait for the chord.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = chordgate;
        readOnly = true;
        description = "chordgate build, exposed for the enrollment scripts.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        boot.initrd.luks.devices.cryptpersist = {
          device = "/dev/disk/by-uuid/${cfg.uuid}";
          # TRIM leaks which blocks are in use, not their contents.
          allowDiscards = true;
          bypassWorkqueues = true;
        };
        fileSystems."/persist".device = lib.mkForce "/dev/mapper/cryptpersist";
      }

      (lib.mkIf gate.enable {
        boot.initrd = {
          availableKernelModules = [
            "usb_storage"
            "uas"
          ];
          kernelModules = [ "evdev" ];
          systemd = {
            storePaths = [ gate.package ];
            # keyFile is unset, so systemd-cryptsetup auto-loads ${keyFile} if present.
            services.stick-gate = {
              description = "Stick gate: USB blob + key chord for /persist";
              wantedBy = [ cryptUnit ];
              before = [ cryptUnit ];
              after = [ "systemd-udevd.service" ];
              unitConfig.DefaultDependencies = false;
              serviceConfig = {
                Type = "oneshot";
                TimeoutStartSec = gate.stickWait + gate.timeout + 15;
                ExecStart = lib.escapeShellArgs [
                  "${gate.package}/bin/chordgate"
                  "boot"
                  "--device"
                  gate.device
                  "--offset"
                  (toString gate.offset)
                  "--out"
                  keyFile
                  "--stick-wait"
                  (toString gate.stickWait)
                  "--timeout"
                  (toString gate.timeout)
                ];
              };
            };
            # /run survives switch-root and auto-discovered keyfiles are never erased.
            services.stick-gate-wipe = {
              description = "Stick gate: erase the /persist key file";
              wantedBy = [ "initrd.target" ];
              after = [ cryptUnit ];
              before = [
                "initrd.target"
                "initrd-switch-root.target"
              ];
              unitConfig.DefaultDependencies = false;
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${gate.package}/bin/chordgate wipe ${keyFile}";
              };
            };
          };
        };
      })
    ]
  );
}

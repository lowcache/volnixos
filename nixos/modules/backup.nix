# External-drive backup. A 2 TB USB disk (Seagate BUP Slim) that lives in a
# drawer rather than in the machine: plugging it in IS the trigger, and nothing
# here ever runs on a timer.
#
# Three partitions, addressed by LABEL so USB port order and /dev/sd? naming
# never matter:
#   RESCUE  FAT32  NixOS installer ISO — this module does not touch it
#   MODELS  ext4   rsync mirror of the weights restic deliberately skips
#   VOLBAK  ext4   the restic repository
#
# No LUKS anywhere. restic encrypts its own repository (data AND metadata), and
# model weights are not secret. That keeps the plug-in path free of an unlock
# step and /persist free of a keyfile that would be stolen alongside the drive.
#
# The hazard this guards hardest: ~/Storage is a SEPARATE NVMe, and therefore a
# mount point. If it fails to mount, the directory still exists and is empty —
# an unguarded run would record a snapshot of nothing and then prune the real
# ones on the next pass. Hence RequiresMountsFor on the restic unit plus an
# explicit mountpoint assertion in the script below. Same reasoning for the
# repo mount: without it, restic would happily initialize a fresh repository on
# the tmpfs root and report success.
{
  config,
  lib,
  pkgs,
  utils,
  username,
  ...
}:
let
  cfg = config.vol.backup;

  repoMount = "/mnt/backup";
  modelsMount = "/mnt/models";

  repoMountUnit = utils.escapeSystemdPath repoMount + ".mount";
  modelsMountUnit = utils.escapeSystemdPath modelsMount + ".mount";

  # Mirrors are declared dest-name -> source-dir rather than as a bare list so
  # two sources that share a basename cannot silently collide in one directory.
  mirrorPairs = lib.mapAttrsToList (dest: src: { inherit dest src; }) cfg.models.mirrors;

  # Root -> user-session notification. Every failure path here is non-fatal:
  # a backup must not fail because nobody was logged in to be told about it.
  notifyFn = ''
    notify() {
      ${lib.optionalString (!cfg.notify) "return 0"}
      local urgency="$1" title="$2" body="$3" uid
      uid=$(${pkgs.coreutils}/bin/id -u ${username} 2>/dev/null) || return 0
      [ -S "/run/user/$uid/bus" ] || return 0
      ${pkgs.util-linux}/bin/runuser -u ${username} -- \
        ${pkgs.coreutils}/bin/env \
          DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
          XDG_RUNTIME_DIR="/run/user/$uid" \
        ${pkgs.libnotify}/bin/notify-send -a "backup" -u "$urgency" "$title" "$body" \
        || true
    }
  '';

  backupScript = pkgs.writeShellScript "vol-backup" ''
    set -euo pipefail
    ${notifyFn}

    # Never write into a directory that only looks like the drive.
    ${pkgs.util-linux}/bin/mountpoint -q ${repoMount} || {
      echo "vol-backup: ${repoMount} is not a mountpoint — refusing to run" >&2
      exit 1
    }

    stamp="$STATE_DIRECTORY/last-success"
    now=$(${pkgs.coreutils}/bin/date +%s)

    if [ -f "$stamp" ]; then
      age=$(( now - $(${pkgs.coreutils}/bin/stat -c %Y "$stamp") ))
      if [ "$age" -lt ${toString (cfg.cooldownHours * 3600)} ]; then
        notify low "Backup skipped" "Last run $(( age / 3600 ))h ago (cooldown ${toString cfg.cooldownHours}h)"
        exit 0
      fi
    fi

    notify low "Backup started" "Snapshotting to ${repoMount}"

    # The restic module owns HOW to back up (repo, password, excludes, prune).
    # This unit owns WHEN, and what happens either side of it.
    ${pkgs.systemd}/bin/systemctl start --wait restic-backups-${cfg.resticName}.service

    ${lib.optionalString (mirrorPairs != [ ]) ''
      if ${pkgs.util-linux}/bin/mountpoint -q ${modelsMount}; then
        ${lib.concatMapStringsSep "\n" (m: ''
          if [ -d "${m.src}" ]; then
            echo "vol-backup: mirroring ${m.src} -> ${modelsMount}/${m.dest}"
            ${pkgs.coreutils}/bin/mkdir -p "${modelsMount}/${m.dest}"
            ${pkgs.rsync}/bin/rsync -aH --delete --no-inc-recursive \
              "${m.src}/" "${modelsMount}/${m.dest}/"
          else
            echo "vol-backup: mirror source ${m.src} absent, skipping" >&2
          fi
        '') mirrorPairs}
      else
        echo "vol-backup: ${modelsMount} not mounted, skipping model mirror" >&2
      fi
    ''}

    # Integrity is checked on a slower clock than the backup itself: reading a
    # subset of the pack files is the only thing that finds bit-rot before a
    # restore does, but it is far too slow to do on every plug-in.
    check_stamp="$STATE_DIRECTORY/last-check"
    do_check=1
    if [ -f "$check_stamp" ]; then
      check_age=$(( now - $(${pkgs.coreutils}/bin/stat -c %Y "$check_stamp") ))
      [ "$check_age" -lt ${toString (cfg.checkIntervalDays * 86400)} ] && do_check=0
    fi
    if [ "$do_check" = 1 ]; then
      notify low "Backup verifying" "restic check --read-data-subset=${cfg.checkSubset}"
      RESTIC_REPOSITORY="${cfg.repository}" \
      RESTIC_PASSWORD_FILE="${cfg.passwordFile}" \
        ${pkgs.restic}/bin/restic check --read-data-subset=${cfg.checkSubset}
      ${pkgs.coreutils}/bin/touch "$check_stamp"
    fi

    ${pkgs.coreutils}/bin/touch "$stamp"
    notify normal "Backup complete" "$(${pkgs.coreutils}/bin/df -h ${repoMount} | ${pkgs.gawk}/bin/awk 'NR==2 {print $4 " free on the drive"}')"
  '';

  # Runs whether the backup succeeded, failed, or was skipped, so the drive is
  # always released rather than left mounted after a failure.
  teardownScript = pkgs.writeShellScript "vol-backup-teardown" ''
    set -uo pipefail
    ${notifyFn}

    result="''${SERVICE_RESULT:-success}"

    ${pkgs.coreutils}/bin/sync
    ${pkgs.systemd}/bin/systemctl stop ${repoMountUnit} ${modelsMountUnit} || true

    ${lib.optionalString cfg.powerOffWhenDone ''
      part=$(${pkgs.util-linux}/bin/findfs LABEL=${cfg.repoLabel} 2>/dev/null || true)
      if [ -n "$part" ]; then
        pk=$(${pkgs.util-linux}/bin/lsblk -no pkname "$part" 2>/dev/null || true)
        [ -n "$pk" ] && ${pkgs.udisks2}/bin/udisksctl power-off -b "/dev/$pk" || true
      fi
    ''}

    if [ "$result" = "success" ]; then
      notify normal "Drive safe to remove" "Unmounted${lib.optionalString cfg.powerOffWhenDone " and powered down"}."
    else
      notify critical "Backup FAILED" "$result — journalctl -u vol-backup.service"
    fi
  '';
in
{
  options.vol.backup = {
    enable = lib.mkEnableOption "plug-triggered external-drive backup (restic)";

    driveSerial = lib.mkOption {
      type = lib.types.str;
      example = "00000000NAEA54PH";
      description = ''
        ID_SERIAL_SHORT of the USB disk, from
        `udevadm info --query=property --name=/dev/sdX`. Binding the trigger to
        the serial rather than to a device node means it fires for THIS drive in
        any port, and never for some other USB disk that happens to be sda.
      '';
    };

    repoLabel = lib.mkOption {
      type = lib.types.str;
      default = "VOLBAK";
      description = "Filesystem label of the partition holding the restic repository.";
    };

    modelsLabel = lib.mkOption {
      type = lib.types.str;
      default = "MODELS";
      description = "Filesystem label of the cold-dump partition for model weights.";
    };

    resticName = lib.mkOption {
      type = lib.types.str;
      default = "volnix";
      description = "Name of the services.restic.backups entry this module creates.";
    };

    repository = lib.mkOption {
      type = lib.types.str;
      default = "${repoMount}/restic";
      description = "Path of the restic repository on the mounted drive.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        File holding the restic repository password. Set this to a sops secret
        path from the host file; the module deliberately does not reach into
        `config.sops` itself, so how the secret is provisioned stays a host
        concern.
      '';
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Directories restic snapshots.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "restic exclude patterns.";
    };

    pruneOpts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 12"
        "--keep-yearly 3"
      ];
      description = "Retention policy passed to `restic forget --prune`.";
    };

    cooldownHours = lib.mkOption {
      type = lib.types.int;
      default = 12;
      description = ''
        Skip the run if a backup already succeeded this recently. Without it,
        unplugging and replugging four times means four full passes.
        A manual `systemctl start vol-backup.service` obeys this too; use
        `--force` semantics by removing /var/lib/vol-backup/last-success.
      '';
    };

    checkIntervalDays = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "How often to run `restic check` with real data reads.";
    };

    checkSubset = lib.mkOption {
      type = lib.types.str;
      default = "5%";
      description = "Argument to `restic check --read-data-subset`.";
    };

    powerOffWhenDone = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Unmount and spin the drive down when finished, so "safe to remove" is a
        fact rather than a guess. Pulls in udisks2, which issues SYNCHRONIZE
        CACHE and STOP UNIT rather than just dropping the mount.
      '';
    };

    notify = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Send desktop notifications to ${username}'s session.";
    };

    models = {
      enable = lib.mkEnableOption "rsync mirror of model weights to the MODELS partition";
      mirrors = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = {
          ollama = "/home/lowcache/Storage/ollama";
        };
        description = ''
          Destination directory name on the MODELS partition -> source path.
          Mirrored with `rsync --delete`, so the drive tracks the source
          exactly. These paths belong in `exclude` as well: mirroring them AND
          snapshotting them would store the same weights twice.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.paths != [ ];
        message = "vol.backup.paths is empty — restic would create a repository and snapshot nothing.";
      }
      {
        assertion = cfg.models.enable -> cfg.models.mirrors != { };
        message = "vol.backup.models.enable is set but no mirrors are declared.";
      }
    ];

    # The backup state directory must outlive the tmpfs root, or the cooldown
    # and check clocks reset on every boot and both stop meaning anything.
    environment.persistence."/persist".directories = [ "/var/lib/vol-backup" ];

    services = {
      # udisksctl issues SYNCHRONIZE CACHE and STOP UNIT rather than merely
      # dropping the mount, which is the difference between "unmounted" and
      # "actually safe to unplug".
      udisks2.enable = lib.mkIf cfg.powerOffWhenDone true;

      # Fires on the repo partition specifically: the drive only becomes
      # interesting once the filesystem we intend to write to has been probed.
      # ID_SERIAL_SHORT propagates from the USB disk down to its partitions, so
      # matching it here binds the trigger to this drive rather than to a
      # device node that another disk could take.
      udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_SERIAL_SHORT}=="${cfg.driveSerial}", ENV{ID_FS_LABEL}=="${cfg.repoLabel}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="vol-backup.service"
      '';

      restic.backups.${cfg.resticName} = {
        inherit (cfg)
          repository
          passwordFile
          paths
          exclude
          pruneOpts
          ;
        initialize = true;
        # No timer at all: udev or `make backup` are the only two ways in.
        timerConfig = null;
        inhibitsSleep = true;
        # Puts `restic-${cfg.resticName}` on PATH with repo and password already
        # set, for interactive snapshots/mount/restore without re-typing either.
        createWrapper = true;
        # Verification runs on its own clock from the orchestrator, not here.
        runCheck = false;
        extraBackupArgs = [ "--exclude-caches" ];
      };
    };

    systemd = {
      # No wantedBy: these are noauto by construction and start only because
      # something Requires them. They are deliberately absent from fileSystems,
      # so a missing drive can never delay or fail a boot.
      mounts = [
        {
          what = "/dev/disk/by-label/${cfg.repoLabel}";
          where = repoMount;
          type = "ext4";
          options = "noatime";
        }
      ]
      ++ lib.optional cfg.models.enable {
        what = "/dev/disk/by-label/${cfg.modelsLabel}";
        where = modelsMount;
        type = "ext4";
        options = "noatime";
      };

      services = {
        "restic-backups-${cfg.resticName}" = {
          # Both of these are correctness, not politeness: an unmounted source
          # is an empty directory, and an empty snapshot followed by a prune is
          # indistinguishable from data loss.
          unitConfig.RequiresMountsFor = [ repoMount ] ++ cfg.paths;
          serviceConfig = {
            Nice = 19;
            IOSchedulingClass = "idle";
          };
        };

        vol-backup = {
          description = "External-drive backup (plug-triggered)";
          # Wants, not Requires, for BOTH mounts — deliberately. Requires
          # propagates in reverse: the teardown's `systemctl stop` on the mount
          # would then be asking systemd to stop the very service issuing it,
          # and the stop job can queue behind the service's own. The safety
          # Requires would buy is already bought by the script's `mountpoint -q`
          # assertion, which fails loudly and, unlike a dependency failure,
          # says why. After is what actually matters here: without it the rsync
          # races the mount and the mirror is skipped silently.
          wants = [ repoMountUnit ] ++ lib.optional cfg.models.enable modelsMountUnit;
          after = [ repoMountUnit ] ++ lib.optional cfg.models.enable modelsMountUnit;
          serviceConfig = {
            Type = "oneshot";
            StateDirectory = "vol-backup";
            ExecStart = backupScript;
            ExecStopPost = teardownScript;
            Nice = 19;
            IOSchedulingClass = "idle";
            TimeoutStartSec = "12h";
          };
        };
      };
    };
  };
}

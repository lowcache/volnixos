# External backup drive

Plug-triggered restic backups to a 2 TB Seagate BUP Slim
(`ID_SERIAL_SHORT=00000000NAEA54PH`). Configured by `nixos/modules/backup.nix`,
switched on in `nixos/hosts/volnix.nix` under `vol.backup`.

Plugging the drive in is the only automatic trigger. There is no timer.

## Layout

| Part | Size | Label | FS | Purpose |
|------|------|-------|----|---------|
| 1 | 8 GiB | `RESCUE` | FAT32 | bootable NixOS installer (see below) |
| 2 | 500 GiB | `MODELS` | ext4 | rsync mirror of model weights |
| 3 | ~1355 GiB | `VOLBAK` | ext4 | restic repository |

Everything is addressed by **filesystem label**, never by `/dev/sd?`, so port
order does not matter. `mkfs` sets those labels — sfdisk's `name=` sets the GPT
partition name, which is a different field and is *not* what the udev rule and
mount units match on.

No LUKS: restic encrypts its own repository, data and metadata both, and model
weights are not secret. That keeps the plug-in path free of an unlock step and
`/persist` free of a keyfile that would be stolen along with the drive.

## One-time setup

### 1. Repo password

Already generated and stored as the sops secret `restic_password`. Read it with:

    make sops-view | grep restic_password

**Put it in a password manager now.** It is the only key to every snapshot;
sops-nix validates it at *build* time, so a missing key fails `make build`
rather than waiting until activation.

### 2. Switch

    make switch

### 3. Partition the drive — DESTRUCTIVE

Wipes everything on the disk. Confirm the device first; `sda` is not stable
across reboots, which is exactly why nothing else here uses it.

    lsblk -o NAME,SIZE,TRAN,MODEL,SERIAL /dev/sda   # expect: BUP Slim, 1.8T

    sudo wipefs -a /dev/sda
    printf '%s\n' \
      'label: gpt' \
      'size=8GiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=rescue' \
      'size=500GiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=models' \
      'type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=volbak' \
      | sudo sfdisk /dev/sda

`sfdisk` rather than `sgdisk` because it ships with util-linux and is therefore
always present — `gptfdisk`, `parted`, and `partprobe` are not installed on this
host. Type GUIDs are written out in full rather than as `uefi`/`linux` aliases,
whose availability varies by util-linux version. The last line carries no
`size=`, meaning "the rest of the disk". sfdisk re-reads the partition table
itself, so no `partprobe` step is needed. The `printf` pipe is used instead of
a heredoc so the same command works in fish (this machine's login shell) and in
bash (what a live-USB recovery session will drop you into).

### 4. Filesystems

`-m 0` drops ext4's 5% root reserve. That reserve exists to keep a *root*
filesystem writable under pressure and is pure waste on a backup disk — it is
about 92 GiB across these two partitions.

    sudo mkfs.vfat -F32 -n RESCUE /dev/sda1
    sudo mkfs.ext4 -m 0 -L MODELS /dev/sda2
    sudo mkfs.ext4 -m 0 -L VOLBAK /dev/sda3

### 5. First run

Unplug and replug. The udev rule fires, both partitions mount, restic
initializes the repository, and the first snapshot runs — roughly 240 GiB, so
expect a few hours over USB. Watch it:

    journalctl -u vol-backup.service -f

## Daily use

Plug it in. That is the whole procedure. A notification reports start, finish,
and "safe to remove"; the drive unmounts and spins down on its own.

| Command | Does |
|---------|------|
| `make backup` | run now (obeys the 12 h cooldown) |
| `make backup-force` | run now regardless of cooldown |
| `make backup-mount` | mount the repo for manual restic work |
| `make backup-umount` | unmount and power down |

Replugging four times does not mean four backups: a run inside
`vol.backup.cooldownHours` of the last success exits early. Every 30 days a run
also does `restic check --read-data-subset=5%`, which is the only thing that
finds bit-rot before a restore does.

## What is and is not backed up

Sources are `/persist` and `/home/lowcache/Storage` — two separate NVMe drives.
The `mkOutOfStoreSymlink`s pointing from `/persist` into `Storage` are stored as
symlinks, so listing both captures each byte once.

Excluded: the swapfile, `Storage/.cache` (30 G), `Storage/tmp` (23 G), docker and
waydroid images, `Storage/libvirt`, `node_modules`, `__pycache__`, `.venv`, and
the model weights (which go to `MODELS` instead). `fooocus/outputs` is
deliberately **not** excluded — that is artwork, and `~/Pictures/fromAi/outputs`
symlinks into it.

Not backed up anywhere: `/nix`, which is reproducible from the flake.

## Restoring

From this machine:

    make backup-mount
    restic-volnix snapshots
    restic-volnix restore latest --target /mnt/restore

`restic-volnix` is a generated wrapper with the repository and password already
set. From a live USB, where that wrapper does not exist, supply both by hand:

    mkdir -p /mnt/backup && mount /dev/disk/by-label/VOLBAK /mnt/backup
    restic -r /mnt/backup/restic snapshots        # prompts for the password

To browse rather than bulk-restore, `restic mount` exposes every snapshot as a
FUSE tree you can `cp` out of.

## Rescue partition

`RESCUE` is not touched by any of the above; populate it separately or leave it
empty. Note that `dd`-ing an installer ISO onto a *partition* does not produce a
UEFI-bootable result — hybrid ISOs expect to own the whole disk.

The route that does work is GRUB loopback: install GRUB for `x86_64-efi` onto
the FAT32 partition, drop the `.iso` on it as a file, and add a menu entry
passing `findiso=/path/to.iso`. NixOS's stage-1 handles that parameter
(`nixos/modules/system/boot/stage-1-init.sh`, `findiso=*`), and `iso-image.nix`
generates the matching entry from its own `iso_path` variable.

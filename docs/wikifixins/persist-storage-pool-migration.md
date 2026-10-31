# /persist + Storage → single LVM pool (migration plan)

Status: **design, not executed.** Reinstall-class change. Nothing here touches disks until the pre-flight gates pass. Layout decided (2026-10-29): **single LV** — one encrypted `/persist`, `~/Storage` as a subdir. Two-LV variant was considered and rejected (wanted shared free space + encrypt-everything over an unencrypted-Storage split).

## Goal

Fold the two 512 GB NVMe drives into one capacity pool so `/persist` and `~/Storage`
stop being separate fixed partitions on separate disks. `/boot` and `/nix` stay
exactly where they are. Net usable persist pool ≈ **746 GB** (277 + 469), shared.

Accepted trade-off (decided with the user): the pool has **no redundancy** — either
NVMe dying loses the pool, restored from the external backup. Same unrecoverable blast
radius as today given the backup; RAID0-style availability, not RAID0 striping. ext4 is
the filesystem (btrfs/bcachefs deliberately rejected: no self-heal without a mirror we
aren't buying, and SMART + restic + Nix already cover the dominant risks).

## Final architecture (recommended: single LV)

```
nvme0 KIOXIA  ├ p1 BOOT (vfat ESP)   ── unchanged
              ├ p2 NIX  (ext4 199G)  ── unchanged  ← Nix store survives; rebuild is fast
              └ p3 ───────────────┐ (plaintext LVM PV)
                                   ├─ VG vgpersist ─ LV lvpersist (~746G) ─ LUKS cryptpersist ─ ext4 PERSIST ─┬─ /persist
nvme1 WD      └ p1 ───────────────┘ (plaintext LVM PV)                                                        └─ /persist/storage ─(bind)─ ~/Storage
```

- **LVM under a single LUKS.** PVs are plaintext (LVM metadata exposes *layout*, never
  data); the one LUKS container rides on the LV. This keeps **one unlock** and reuses the
  existing `persist-luks.nix` machinery verbatim — `boot.initrd.services.lvm.enable` is
  already `true`, so the VG activates in stage-1 before cryptsetup, and the LUKS header is
  found by-uuid on the LV exactly as it is on the partition today. Mapper name stays
  `cryptpersist`, so the stickGate keyfile path is unchanged.
- **`~/Storage` becomes a bind-mount of `/persist/storage`.** Every config reference is to
  the *path* `~/Storage/...` (home/persist.nix, home/default.nix TMPDIR/caches/GD_*,
  shell.nix, windows-vm.nix libvirt tree, anon-box `/out` virtiofs) — none name the device.
  Keep the path valid and all of them work untouched.

## Layout decision: single LV (DECIDED 2026-10-29)

One ext4 under one LUKS on one LV; `~/Storage` = `/persist/storage` subdir. Fully shared
free space, everything encrypted at rest. Side effects accepted: the anon-box `/out`
volume and the Windows-VM disk images become encrypted (minor VM-image perf cost) — the
"unencrypted volume" notes in `CLAUDE.md`/`windows-vm.nix` go stale and must be updated
(see post-migration section). Two-LV (separate plaintext `lvstorage`) was considered and
rejected: shared free space + encrypt-everything beat keeping an unencrypted scratch split.

## Device map (all destructive ops key off by-id, never sda/nvmeX)

| Role | by-id | Fate |
|---|---|---|
| System+persist (KIOXIA) | `nvme-KBG40ZNV512G_KIOXIA_Z0SPDF48Q9D2` | keep `-part1`/`-part2`; wipe+repurpose `-part3` as PV |
| Storage (WD SN5000S) | `nvme-WD_PC_SN5000S_SDEQNSJ-512G-1002_25210B804867` | wipe whole disk → one `-part1` PV |
| Backup (Seagate 2 TB USB) | label `VOLBAK` (restic) / `MODELS` | staging target, 1.2 TB free |

## Pre-flight gates (all must pass before any wipe)

0a. **SMART** — DONE, PASS: WD at 2% used, 100% spare, 0 media-integrity errors, 210 h.
    Seagate 2TB backup drive also SMART-PASSED 2026-10-30 (0 pending/offline/CRC; 8 old reallocated).
0b. **Backup verified (restic, not a hand-rolled rsync)** — DONE 2026-10-30. The existing `vol.backup`
   restic repo on `VOLBAK` already snapshots `[ /persist, /home/lowcache/Storage ]` minus throwaway
   excludes. Latest snapshot `7f678a5e` (2026-10-30) holds both paths, ~122 GiB / 1.23M files,
   10-snapshot chain. Structural `restic check` clean; **full `restic check --read-data` is the final
   gate** (`~/Storage/tmp/verify-backup-full.sh`, ~3h). The separate plain-rsync pre-image is **dropped**:
   the restic repo is multi-snapshot + check-clean and the restore is a 3-liner (step 6), which outweighs
   a second ~3h copy on a ~12 MB/s drive.
0c. **Keys off-box:** confirm Bitwarden has the sbctl Secure Boot keys, the sops host key
   `/persist/etc/ssh/ssh_host_ed25519_key`, **and the restic repo password** (sops `restic_password`,
   needed for the live-USB restore since sops is unavailable there — capture plaintext BEFORE the wipe).
   These are the only things not reproducible from the repo.
0d. **Do not reuse/clear the VOLBAK repo or prune it until the new system is verified booting.**

### Seagate 2TB operating notes (this drive specifically)
- BOT mode forced by `usb-storage.quirks=0bc2:ac19:u` (live) + kernel IGNORE_UAS; **never force UAS back**
  (bridge corrupts under sustained UAS write). Ceiling ~10-15 MB/s.
- Plug-in auto-triggers `vol-backup.service`, whose teardown powers the drive off. To work on the drive
  manually (inspect/restore), `systemctl mask vol-backup.service` first, and keep a light I/O heartbeat
  running so firmware standby doesn't drop it. Address it by **by-label/VOLBAK** or ID_FS_UUID
  `965cca42-99f0-4b1a-becf-5024d644ffc6` — the serial/by-id changes with the driver.

## Offline procedure (NixOS live USB, by-id throughout)

1. Boot the live USB **with `copytoram`** (append it to the boot entry's kernel cmdline, or write the
   ISO so it's set). This copies the live system into RAM so the SD/USB boot medium can be removed —
   necessary because the SD reader and the 2 TB backup cannot both occupy the fast USB port at once.
   Once booted: eject the SD reader, plug in the 2 TB, then
   `systemctl start mnt-backup.mount` (or `mount /dev/disk/by-label/VOLBAK /mnt/backup`). Confirm 0b.
   Keep a light I/O heartbeat on the drive during long operations (BOT-mode idle-standby).
2. Wipe only what changes (leaves KIOXIA p1/p2 intact):
   ```
   wipefs -a /dev/disk/by-id/nvme-KBG40ZNV512G_KIOXIA_Z0SPDF48Q9D2-part3
   sgdisk --zap-all /dev/disk/by-id/nvme-WD_PC_SN5000S_SDEQNSJ-512G-1002_25210B804867
   ```
3. New single partition on the WD (whole disk, type 8e00 Linux LVM):
   ```
   sgdisk -n1:0:0 -t1:8e00 /dev/disk/by-id/nvme-WD_PC_SN5000S_SDEQNSJ-512G-1002_25210B804867
   ```
4. PVs + VG + LV (linear concat spans the unequal sizes with no waste):
   ```
   pvcreate /dev/disk/by-id/nvme-KBG40ZNV512G_KIOXIA_Z0SPDF48Q9D2-part3
   pvcreate /dev/disk/by-id/nvme-WD_PC_SN5000S_SDEQNSJ-512G-1002_25210B804867-part1
   vgcreate vgpersist /dev/disk/by-id/nvme-KBG40ZNV512G_KIOXIA_Z0SPDF48Q9D2-part3 \
                      /dev/disk/by-id/nvme-WD_PC_SN5000S_SDEQNSJ-512G-1002_25210B804867-part1
   lvcreate -l 100%FREE -n lvpersist vgpersist
   ```
5. LUKS2 on the LV with a **recorded new UUID** (this value goes into the config):
   ```
   cryptsetup luksFormat --type luks2 --uuid <NEW_UUID> /dev/vgpersist/lvpersist   # passphrase slot
   cryptsetup open /dev/vgpersist/lvpersist cryptpersist
   mkfs.ext4 -L PERSIST /dev/mapper/cryptpersist
   ```
6. Restore from the restic repo (NOT rsync — see 0b). In the live USB, bring up restic and point it
   at the repo on the mounted drive; password comes from the Bitwarden-stashed `restic_password` (0c):
   ```
   mount /dev/mapper/cryptpersist /mnt/persist
   nix-shell -p restic
   export RESTIC_REPOSITORY=/mnt/backup/restic
   export RESTIC_PASSWORD='<from Bitwarden>'     # do not echo; paste into the var
   restic snapshots                              # sanity: newest covers /persist + Storage
   ```
   The snapshot stores absolute paths (`/persist`, `/home/lowcache/Storage`). Map them to the new
   single-pool layout (old /persist → pool root; old ~/Storage → /persist/storage):
   ```
   # /persist lands exactly at the pool root because target=/mnt and the pool is mounted at /mnt/persist:
   restic restore latest --target /mnt --include /persist           # ~3h: reads ~X GiB from the slow USB
   # ~/Storage keep-set → /persist/storage, via a small pool-local move (restic has no path-rewrite):
   restic restore latest --target /mnt/persist/.restore-stage --include /home/lowcache/Storage
   mkdir -p /mnt/persist/storage
   ( shopt -s dotglob; mv /mnt/persist/.restore-stage/home/lowcache/Storage/* /mnt/persist/storage/ )
   rm -rf /mnt/persist/.restore-stage
   ```
   Caveat — the restic excludes drop the big items (`Storage/libvirt`, `ollama`, `ai-generation/*/models`,
   `.cache`, `tmp`, docker/waydroid state, swapfile). Model weights are separately mirrored to the MODELS
   partition (restore those by plain copy if wanted). **Windows-VM images under `Storage/libvirt` are NOT
   in either backup** — confirm that's an accepted loss before the wipe, or copy them to MODELS/VOLBAK first.
7. Rebuild the installed system's initrd/bootloader with the new UUID (store on p2 is
   intact, so this is fast — no re-download). Edit the config changes below first, then:
   ```
   mount /dev/disk/by-label/NIX  /mnt/persist/nix   # or mount at the enter root as appropriate
   mount /dev/disk/by-label/BOOT /mnt/persist/boot
   nixos-enter --root /mnt/persist -c 'nixos-rebuild boot --flake /persist/path/to/.nix-config#volnix'
   ```
   (Exact mount topology for `nixos-enter` depends on the impermanence layout — assemble
   `/persist`, bind the repo, ensure `/nix` and `/boot` are visible. Verify the generated
   initrd references `<NEW_UUID>` and the LV before rebooting.)
8. **TPM2 re-enroll** (the fiddliest step — the recovery/passphrase slot from step 5 is the
   safety net throughout):
   ```
   systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/vgpersist/lvpersist   # + PIN
   ```
   PCR7 binds to Secure Boot state; since it's the same machine with the same enrolled SB
   keys, the PCR value is stable. If enrolment from the live USB is unreliable, boot once on
   the passphrase slot and enroll from the running system. Keep `fallbackToPassword`
   reachable during migration (it is currently `false` — temporarily relax if needed, then
   restore). **Verify an unlock actually works before touching the backups.**

## Nix config changes (small — the pool is mostly off-disk work)

1. `nixos/hosts/volnix.nix` — `vol.persistLuks.uuid = "<NEW_UUID>";`
2. `nixos/hardware-configuration.nix` — replace the `~/Storage` by-label mount with a bind:
   ```nix
   "/home/${username}/Storage" = {
     device = "/persist/storage";
     fsType = "none";
     options = [ "bind" "nosuid" "nodev" ];
     depends = [ "/persist" ];
   };
   ```
   `/persist` entry is unchanged (by-label `PERSIST`; `persist-luks.nix` still `mkForce`s
   the `cryptpersist` mapper).
3. Companion: add `pkgs.smartmontools` to `environment.systemPackages` (smartd runs but the
   CLI wasn't exposed — needed for SMART pre-flights like 0a).
4. `persist-luks.nix` logic: **no change** — LUKS still found by-uuid, mapper still
   `cryptpersist`, initrd LVM already enabled. Only the pinned UUID moves.

## First boot & verify

- Unlock succeeds (TPM2+PIN, or passphrase fallback).
- `lsblk`: `vgpersist/lvpersist → cryptpersist → ext4 /persist` ≈ 746 G.
- `~/Storage` resolves via the bind; `df` shows the unified pool; a `storage`
  `mkOutOfStoreSymlink` target (e.g. `~/Storage/tmp`) is writable.
- `make check` passes; Windows VM + anon-box `/out` reach their `~/Storage` paths.
- Only after all green: TPM2 enrolled, then the 2 TB pre-image may be retired.

## Rollback

Guaranteed by the untouched 2 TB pre-image + Bitwarden keys: worst case is a clean
reinstall from the repo (`nixos-install`, cache-fast) + `rsync` restore of `/persist` —
~1–2 h. The old single-LUKS-on-partition layout is *not* preserved (p3 is repurposed), so
rollback is forward (reinstall), not a revert. Hence gate 0d.

## Post-migration doc updates

- Root `CLAUDE.md`: note Storage is folded into the LUKS pool; the anon-box `/out` volume
  and Windows-VM images are now **encrypted at rest** (the "unencrypted volume" note is
  stale after this). Update the MicroVM/anon and windows-vm descriptions.
- `nixos/windows-vm.nix` header: "separate physical disk" → "subdir of the pooled /persist".
- `.memory/inbox/`: dated note recording the layout change and the new LUKS UUID rationale.
```

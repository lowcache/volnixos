{ pkgs, ... }:

# Self-contained QEMU/KVM + libvirt stack for running a Windows 11 guest.
# Kept separate from the microvm.nix (Linux) setup in vms.nix on purpose:
# Windows 11 needs full QEMU with UEFI (OVMF/Secure Boot) and an emulated
# TPM 2.0 (swtpm), neither of which the cloud-hypervisor microVM path provides.
#
# Module-merge notes (why this file can stand alone):
#   - users.users.<name>.extraGroups merges with the main user definition.
#
# Storage: the whole libvirt tree (VM definitions, nvram, swtpm state AND the
# heavy disk images in images/) is bind-mounted onto the dedicated Storage NVMe
# (/home/lowcache/Storage, a separate physical disk from /nix and /persist).
# That keeps VM disk I/O off the system drive and survives the tmpfs root,
# since Storage is itself persistent. The bind goes through the /var/lib/libvirt
# path, so the 0700 home dir does not block the libvirt-qemu user.
#
# Remove the single `./windows-vm.nix` import from nixos/hosts/volnix.nix to fully
# back this out; nothing else here touches existing config.

{
  virtualisation.libvirtd = {
    enable = true;
    onBoot = "ignore"; # don't auto-start guests at boot
    onShutdown = "shutdown";
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true; # emulated TPM 2.0 (Win11 requirement)
      # OVMF UEFI firmware (incl. Secure Boot variants) ships by default now;
      # the old qemu.ovmf submodule was removed upstream.
    };
  };

  # virt-manager GUI to create/run the VM.
  programs.virt-manager.enable = true;
  programs.dconf.enable = true; # virt-manager stores settings in dconf

  # SPICE USB redirection (handy if the assessment needs a USB device/webcam).
  virtualisation.spiceUSBRedirection.enable = true;

  users.users.lowcache.extraGroups = [
    "libvirtd"
    "kvm"
  ];

  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer
    spice-gtk
    virtio-win # virtio driver ISO for the guest (storage/net/balloon)
    swtpm
  ];

  # Park the entire libvirt tree on the dedicated Storage NVMe. tmpfiles makes
  # sure the backing dir exists and is root-owned (libvirtd manages subdir perms
  # itself); the bind mount waits for the Storage filesystem and won't wedge boot
  # if it is ever absent (nofail).
  systemd.tmpfiles.rules = [
    "d /home/lowcache/Storage/libvirt 0755 root root -"
  ];

  fileSystems."/var/lib/libvirt" = {
    device = "/home/lowcache/Storage/libvirt";
    fsType = "none";
    options = [
      "bind"
      "x-systemd.requires-mounts-for=/home/lowcache/Storage"
      "nofail"
    ];
  };
}

# System-level program toggles that don't belong to a single feature module.
{
  config,
  pkgs,
  username,
  ...
}:
{
  programs = {
    # `make switch-detached` runs nixos-rebuild as root; nix's git fetcher
    # refuses the lowcache-owned repo without a safe.directory whitelist
    # (fails with "getting the HEAD of the Git tree ... exit code 254").
    git = {
      enable = true;
      config.safe.directory = [
        "/persist/home/${username}/.nix-config"
        "/home/${username}/.nix-config"
      ];
    };
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        libgcc.lib
        libxcrypt-legacy
        libx11
        libxcomposite
        libxdamage
        libxext
        libxfixes
        libxrandr
        libxrender
        libxv
        libxcb
        openssl.out
        fuse3
        icu
        nss
        nspr
        atk
        gtk3
        at-spi2-atk
        at-spi2-core
        libdrm
        mesa
        libgbm
        glib
        pango
        cairo
        alsa-lib
        dbus
        curl
        expat
        # GPU / Graphics
        libvdpau
        libva
        vulkan-loader
        libGL
        egl-wayland
        wayland
        libxkbcommon
        # The driver built for the running (CachyOS) kernel, not stock linuxPackages.
        config.hardware.nvidia.package.out
        cudaPackages.cuda_cudart
        cudaPackages.libcublas
        cudaPackages.nccl
        libglvnd
        cups
      ];
    };
    niri.enable = true;
    appimage = {
      enable = true;
      binfmt = true;
    };
    kdeconnect.enable = true;
    fish.enable = true;
  };
}

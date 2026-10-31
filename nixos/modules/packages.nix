# systemPackages: base utilities and the nix toolbelt.
{
  pkgs,
  ...
}:
{
  environment = {
    systemPackages =
      let
        base-utils = with pkgs; [
          sbctl
          cryptsetup
          smartmontools
          wireguard-tools
          uwsm
          android-studio
          android-tools
          appimage-run
          vulkan-tools
          libva-utils
          bazaar
          nvtopPackages.nvidia
          nvidia-vaapi-driver
          ffmpeg
          adwaita-icon-theme
          hicolor-icon-theme
          weylus
          # system-level so polkitd sees its action (allow_gui keeps DISPLAY);
          # run as user, not sudo: it self-elevates via pkexec
          gparted
        ];
        nix-utils = with pkgs; [
          statix
          vulnix
          deadnix
          nix-diff
          nix-init
          manix
          nixos-option
          nixos-shell
          styx
          tix
          nixmate
          optnix
          nvd
          searchix
          nurl
          autoflake
          flake-edit
          fh
          flake-checker
        ];
      in
      base-utils ++ nix-utils;
  };
}

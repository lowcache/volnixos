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
          wireguard-tools
          tor
          uwsm
          android-studio
          android-tools
          appimage-run
          vulkan-tools
          libva-utils
          gnupg
          bazaar
          nvtopPackages.nvidia
          nvidia-vaapi-driver
          ffmpeg
          adwaita-icon-theme
          hicolor-icon-theme
          weylus
        ];
        nix-utils = with pkgs; [
          nh
          statix
          vulnix
          deadnix
          nix-diff
          nix-init
          manix
          nixfmt
          nixos-option
          nixos-shell
          styx
          tix
          nixmate
          optnix
          nix-index
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

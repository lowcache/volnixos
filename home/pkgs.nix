{ config, pkgs, lib, inputs, ... }:

{
  home = {
    packages =
      let
        basedevel = with pkgs; [
          gcc
          automake
          autoconf
          pkg-config
          binutils
          glibc
          gdb
          cmake
          gnumake
          strace
          ltrace
          gperf
          patch
          diffutils
          findutils
          gawk
          gnugrep
          gnutar
          gzip
          coreutils
          go
          dart-sass
          python3
          glib
          nodejs
        ];
        quickshell = with pkgs; [
          inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
          qt6.qtwayland
          qt6.qtsvg
          qt6.qt5compat
          qt6.qtdeclarative
          qt6.qtpositioning
          qt6.qtmultimedia
          qt6.qtquicktimeline
          qt6.qtimageformats
          qt6.qtvirtualkeyboard
          qt6.qtsensors
          qt6.qttools
          qt6.qttranslations
          qt6.qtwebsockets
          qt6.qtshadertools
          qt6.qtscxml
          kdePackages.kirigami.unwrapped
          kdePackages.kirigami-addons
          kdePackages.breeze-icons
          kdePackages.qqc2-desktop-style
          kdePackages.syntax-highlighting
          kdePackages.dolphin
          bibata-cursors
          bibata-cursors-translucent
        ];
        krita-wrapped = pkgs.symlinkJoin {
          name = "krita";
          paths = [ pkgs.krita ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/krita \
              --set QT_QPA_PLATFORM xcb
          '';
        };
        hyprland = with pkgs; [
          hypridle
          hyprlock
          hyprcursor
          hyprland-qt-support
          pamixer
          pavucontrol
          xwayland
          awww
          waypaper
          hyprpaper
          adw-gtk3
          cliphist
          hyprpicker
          libnotify
          fuzzel
          kitty
          krita-plugin-gmic
          krita-wrapped
          imagemagick
          spacedrive
          papirus-icon-theme
          gsettings-desktop-schemas
          vscodium
          gedit
          cava
          swappy
          wl-clipboard
          grim
          slurp
          matugen
          networkmanagerapplet
          spotify
        ];
        typography = with pkgs; [
          material-symbols
          nerd-fonts.symbols-only
          nerd-fonts.jetbrains-mono
          nerd-fonts.ubuntu-sans
          nerd-fonts.sauce-code-pro
          nerd-fonts.intone-mono
          nerd-fonts.martian-mono
          nerd-fonts.roboto-mono
          nerd-fonts.anonymice
          nerd-fonts.hack
          nerd-fonts.hurmit
          nerd-fonts.hasklug
          nerd-fonts.geist-mono
          nerd-fonts.commit-mono
          nerd-fonts.code-new-roman
          nerd-fonts.blex-mono
          nerd-fonts.envy-code-r
          nerd-fonts.victor-mono
          nerd-fonts.recursive-mono
          nerd-fonts.departure-mono
          nerd-fonts.zed-mono
          nerd-fonts.atkynson-mono
        ];
        terminal = with pkgs; [
          fish
          git
          gh
          gh-s
          ghdorker
          ghfetch
          ghgrab
          fzf
          eza
          tgpt
          hdrop
          bat
          gnupg
          gpg-tui
          ripgrep-all
          flatpak
          feh
          fd
          jq
          bc
          tor
          micro
          cryptsetup
          htop
          bat-extras.batgrep
          psmisc
          direnv
          playerctl
          brightnessctl
          socat
          gawk
          acpi
          upower
          ddcutil
          clinfo
          git-lfs
          nil
          android-tools
          nixpkgs-fmt
          spotatui
          inputs.infernal-init.packages.${pkgs.stdenv.hostPlatform.system}.default
        ];
        nixified-ai = with pkgs; [
          mcp-nixos
          mcp-gateway
          github-mcp-server
          markitdown-mcp
          playwright-mcp
          codex
          claude-code
          claude-code-router
          gemini-cli
          github-copilot-cli
          rtk
          pkgs.llm-agents.claude-plugins
        ];
      in
      nixified-ai ++ terminal ++ typography ++ hyprland ++ quickshell ++ basedevel;
  };
}

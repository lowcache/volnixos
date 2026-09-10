{ pkgs, inputs, ... }: {

  home = {
    packages =
      let
        # POSIX/toolchain basics (coreutils, findutils, gawk, make, python3,
        # nodejs, go, …) now come from home/common/packages.nix, which the
        # nix-on-droid config shares. Only host-bound build tooling is left here.
        baseDev = with pkgs; [
          gcc
          automake
          autoconf
          pkg-config
          binutils
          glibc
          gdb
          cmake
          progress
          cpufrequtils
          strace
          ltrace
          gperf
          go
          nodejs
          dart-sass
          glib
          gtk3
          gtk4
          dconf
        ];
        # TODO
        # FIXME
        # Krita Wrapper was a fix under Hyprland the switch to Niri has made this redundant (see comment below) GMIC crashes are prevalent more krita research needed
        # POC: QT_QPA_PLATFORM wayland is already set under home-Manager default.nix
        # SOLUTION1: removal of this wrapper place krita: niriDesktop = with pkgs; [ krita ... ];
        # SOLUTION2: keep krita wrapper and remove postBuild = '' wrapProgram $out/bin/krita --set QT_QPA_PLATFORM wayland '';
        # G'MIC plugin crashes krita with SIGSEGV on first right-click/stylus-press in the
        # filter tree: FiltersView::onCustomContextMenu calls deleteLater() on a context-menu
        # pointer that is still nullptr (bug present upstream through gmic-qt master, 2026-07).
        # Null-guard patch until fixed upstream; drop when nixpkgs ships a fixed version.
        krita-plugin-gmic-patched = pkgs.krita-plugin-gmic.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ../overrides/gmic-qt-filtersview-nullptr-contextmenu.patch ];
        });
        krita-wrapped = pkgs.symlinkJoin {
          name = "krita";
          # pkgs.krita is itself a symlinkJoin of krita-unwrapped + binaryPlugins
          # (default [ krita-plugin-gmic ]); override that input so the *patched* gmic
          # is the single copy bundled inside the wrapper. Listing a standalone
          # krita-plugin-gmic alongside would put a second, conflicting krita_gmic_qt.so
          # in the home-manager profile and break buildEnv.
          paths = [ (pkgs.krita.override { krita-plugin-gmic = krita-plugin-gmic-patched; }) ];
          nativeBuildInputs = [ pkgs.makeWrapper ];
          # Krita runs native Wayland under niri (better stylus/tablet support).
          # The former xcb (XWayland) fallback existed only for Hyprland + hybrid-GPU
          # canvas freezes (decision #4); Hyprland is gone, so Wayland is unconditional.
          postBuild = ''
            wrapProgram $out/bin/krita \
              --set QT_QPA_PLATFORM wayland
          '';
        };
        # Vanilla Discord with the moonlight client mod injected (nixpkgs override).
        # Runs alongside GoofCord as a separate client/launcher.
        discord-moonlight = pkgs.discord.override { withMoonlight = true; };
        niriDesktop = with pkgs; [
          hyprpicker # wlroots screen color picker (niri Mod+Shift+C)
          # niri utils
          nirius
          nirimon
          pamixer
          pavucontrol
          xwayland
          xwayland-satellite # dependency for X11 apps under niri
          awww # swww wrapper/replacement
          waypaper
          thunderbird
          bitwarden-desktop
          # rbw shells out to a pinentry binary and ships none; programs.rbw
          # does not pull one in either. Qt variant because the agent gets
          # triggered from GUI contexts (browser extension, desktop client)
          # where a curses prompt has no terminal to draw in.
          pinentry-qt
          adw-gtk3
          cliphist
          libnotify
          fuzzel
          kitty
          krita-wrapped
          gimp-with-plugins
          imagemagick
          papirus-icon-theme
          gsettings-desktop-schemas
          vscodium
          pulsar
          gedit
          geany
          file-roller
          cava
          swappy
          wl-clipboard
          grim
          slurp
          matugen
          networkmanagerapplet
          spotify
          goofcord # privacy-focused Discord client (Vencord/Equicord/Shelter at runtime)
          discord-moonlight
          floorp-bin # Firefox-fork backup browser
          pkgs.caja-with-extensions
          ayugram-desktop
          vial
          nemo-with-extensions
          thunar
          thunar-archive-plugin
          thunar-volman
          thunar-vcs-plugin
          thunar-media-tags-plugin
          thunar-shares-plugin
          thunar-dropbox-plugin
        ];
        monoTypography = with pkgs; [
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
        # The portable half of this set (fish, git, gh, fzf, eza, bat, ripgrep,
        # fd, jq, micro, htop, lazygit, nil, nixfmt, sops, …) moved to
        # home/common/packages.nix. What remains needs a desktop session,
        # host hardware, or an x86_64-only source.
        termUi = with pkgs; [
          gvfs
          gh-s
          ghdorker
          ghfetch
          ghgrab
          tgpt
          hdrop
          gpg-tui
          ripgrep-all
          pandoc # backend for micro's `preview` plugin (see home/common/tools.nix)
          flatpak
          feh
          tor
          cryptsetup
          playerctl
          brightnessctl
          gawk
          acpi
          upower
          ddcutil
          clinfo
          android-tools
          inputs.volinit.packages.${pkgs.stdenv.hostPlatform.system}.default
        ];
        nixAi = with pkgs; [
          antigravity-cli
          mcp-nixos
          mcp-gateway
          github-mcp-server
          markitdown-mcp
          playwright-mcp
          context7-mcp
          # sequential-thinking removed 2026-08-24: unused, and it collides with
          # mcp-server-filesystem in buildEnv (both are packaged from the same
          # @modelcontextprotocol/servers monorepo and each ships dist/lib.js).
          # Dropping it lets filesystem in at normal priority, no lib.lowPrio needed.
          mcp-server-filesystem
          open-websearch
          mcp-server-fetch
          llmfit
          rtk
          claude-code
          pkgs.llm-agents.ccstatusline
          claude-code-router
          #gemini-cli
          #github-copilot-cli
          #codex
          pkgs.llm-agents.claude-plugins
          pkgs.llm-agents.opencode
          pkgs.llm-agents.zaly
          pkgs.llm-agents.cc-switch-cli
          pkgs.llm-agents.parallel-cli
          pkgs.llm-agents.toon
          pkgs.llm-agents.happy-coder
        ];
        andronix = with pkgs; [
          scrcpy
          qtscrcpy
          dumpyara
          dcnnt
          better-adb-sync
          apktool
          apksigner
          flying-carpet
          #genymotion
          # waydroid itself comes from virtualisation.waydroid.enable
          # (nixos/configuration.nix). Do NOT add it here: waydroid-nftables
          # ships its own `waydroid` binary, and the HM profile shadows
          # /run/current-system on PATH, so the CLI and the container service
          # end up different builds. This host's iptables is xtables-nft-multi
          # already, so the plain package's rules land in nftables regardless.
          # If waydroid networking ever misbehaves, set
          # `virtualisation.waydroid.package = pkgs.waydroid-nftables;` rather
          # than reinstating a user-profile copy.
          apksigcopier
          apkeditor
          avbroot
          bytecode-viewer
          fastlane
          imgpatchtools
          jnitrace
          mvt
          otadump
          payload-dumper-go
          payload_dumper
          #1snapdragon-profiler #requires tarball from qualcomm
          trueseeing
          universal-android-debloater
          objection
          frida-tools
        ];
      in
      andronix ++ nixAi ++ termUi ++ monoTypography ++ niriDesktop ++ baseDev;
  };
}

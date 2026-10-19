{ pkgs, lib, ... }: {

  home = {
    packages =
      let
        # POSIX/toolchain basics (coreutils, findutils, gawk, make, python3,
        # nodejs, go, …) now come from home/common/packages.nix, which the
        # nix-on-droid config shares. Only host-bound build tooling is left here.
        baseDev = with pkgs; [
          nixd # Claude Code's nix-lsp plugin execs it; host-only, so not in common/
          bubblewrap # Claude Code's Bash sandbox; its wrapper adds bwrap only to its own PATH, not to child agents
          gcc
          automake
          autoconf
          pkg-config
          binutils
          gdb
          cmake
          progress
          cpufrequtils
          # 0.7.91's demangle tests fail on nixpkgs c59305b's toolchain (15/245,
          # all ltrace.minor/demangle). Drop the override once Hydra caches ltrace.
          (ltrace.overrideAttrs { doCheck = false; })
          gperf
          go
          nodejs
          dart-sass
          glib
        ];
        # G'MIC crashes Krita (SIGSEGV) on the first right-click/stylus press in the
        # filter tree: FiltersView::onCustomContextMenu deleteLater()s a null
        # pointer (upstream through gmic-qt master, 2026-07). Drop the patch when
        # nixpkgs ships a fix. Overridden INSIDE pkgs.krita (a symlinkJoin over
        # binaryPlugins) so the patched copy is the only krita_gmic_qt.so.
        krita-patched = pkgs.krita.override {
          krita-plugin-gmic = pkgs.krita-plugin-gmic.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ../overrides/gmic-qt-filtersview-nullptr-contextmenu.patch ];
          });
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
          krita-patched
          gimp-with-plugins
          imagemagick
          papirus-icon-theme
          gsettings-desktop-schemas
          vscodium
          zed-editor
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
          caja-with-extensions
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
          nerd-fonts.monaspace
          nerd-fonts.roboto-mono
          nerd-fonts.anonymice
          nerd-fonts.googlesanscode
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
          feh
          tor
          # The Noctalia cursor plugin imports win2xcur/wand from PATH's python3
          # (Windows pack import, previews); hiPrio shadows common/'s bare python3.
          (lib.hiPrio (
            python3.withPackages (ps: [
              ps.wand
              (ps.toPythonModule win2xcur)
            ])
          ))
          zenity
          playerctl
          brightnessctl
          gawk
          acpi
          ddcutil
          clinfo
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
          claude-code-tweaked # tweakcc patches, pkgs/claude-code-tweaked
          pkgs.llm-agents.omo-ai
          pkgs.llm-agents.oh-my-opencode
          pkgs.llm-agents.claude-desktop
          pkgs.llm-agents.ccstatusline
          claude-code-router
          pkgs.llm-agents.claude-plugins
          pkgs.llm-agents.cc-switch-cli
          pkgs.llm-agents.opencode
          # Testrunners
          pkgs.llm-agents.freebuff
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
          # (nixos/modules/containers.nix). Do NOT add it here: waydroid-nftables
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

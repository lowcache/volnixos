{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  # We define the entire set of session variables once in this let block.
  sessionVariables =
    let
      qtDependencies = with pkgs; [
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
      ];
    in
    {
      QML2_IMPORT_PATH = pkgs.lib.concatMapStringsSep ":" (
        pkg: "${pkg}/lib/qt-6/qml:${pkg}/lib/qml"
      ) qtDependencies;
      QML_IMPORT_PATH = pkgs.lib.concatMapStringsSep ":" (
        pkg: "${pkg}/lib/qt-6/qml:${pkg}/lib/qml"
      ) qtDependencies;
      QT_PLUGIN_PATH = pkgs.lib.concatMapStringsSep ":" (
        pkg: "${pkg}/lib/qt-6/plugins:${pkg}/lib/plugins"
      ) qtDependencies;
      # Wayland session vars. XDG_CURRENT_DESKTOP / XDG_SESSION_DESKTOP are deliberately
      # NOT hardcoded here: the niri session self-declares its identity
      # (`niri-session` exports XDG_CURRENT_DESKTOP=niri itself).
      XDG_SESSION_TYPE = "wayland";
      # redundant? QT_QPA_PLATFORM is hardcoded under the krita wrapper in pkgs.nix line ~45
      QT_QPA_PLATFORM = "wayland";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      GDK_BACKEND = "wayland,x11";
      SDL_VIDEODRIVER = "wayland";
      CLUTTER_BACKEND = "wayland";
      # Force GTK apps and Chromium to use XDG Desktop Portal for file choosers
      GTK_USE_PORTAL = "1";
      # Wayland support for Electron/Chromium
      NIXOS_OZONE_WL = "1";
      # Keep scratch + caches OFF the 4G tmpfs root: redirect to the roomy ~/Storage
      # volume at the environment level so it holds for every session process (shells,
      # tools, the Claude Code harness) without depending on per-action discipline.
      # XDG_CACHE_HOME is set canonically via xdg.cacheHome in persist.nix (setting it
      # here would conflict with home-manager's xdg module). It is honored by pip,
      # llmfit, etc.
      TMPDIR = "${config.home.homeDirectory}/Storage/tmp";
      PIP_CACHE_DIR = "${config.home.homeDirectory}/Storage/.cache/pip";
      CLAUDE_CODE_TMPDIR = "${config.home.homeDirectory}/Storage/tmp/claude";
      # nvidia specific (commented out to render on the integrated AMD GPU)
      # LIBVA_DRIVER_NAME = "nvidia";
      # GBM_BACKEND = "nvidia-drm";
      # __NV_PRIME_RENDER_OFFLOAD = "1";
      # __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      # __VK_LAYER_NV_optimus = "NVIDIA_only";
    };

in
{

  imports = [
    ./persist.nix
    ./pkgs.nix
    ./scripts.nix
    ./shell.nix
    inputs.memd.homeManagerModules.default
  ];

  # Bitwarden CLI. settings is deliberately NOT set: the Home Manager module
  # writes ~/.config/rbw/config.json as a read-only store symlink whenever
  # settings != null (modules/programs/rbw.nix:101), which makes `rbw config
  # set` fail — and that is the only way to change email or pinentry. Configure
  # it once imperatively instead; ~/.config/rbw is persisted (see persist.nix).
  # rbw also needs a pinentry binary and pulls none in: see pinentry-qt in
  # pkgs.nix.
  programs.rbw.enable = true;

  services.memd = {
    enable = true;
    installClaudeHooks = true;
    sweep.interval = "30min";
  };

  home = {
    username = "lowcache";
    homeDirectory = "/home/lowcache";
    stateVersion = "24.11";
    enableNixpkgsReleaseCheck = false;
    inherit sessionVariables;
    # Ensure the redirected scratch/cache roots exist before anything writes to them.
    # krita-swap: Krita mmaps a tile swap file (kritarc maxSwapSize=10240, so up
    # to 10G) at its own `swaplocation` key and does NOT read $TMPDIR, so the
    # stock /tmp default put it on the 4G tmpfs root — where a full tmpfs leaves
    # the mapped page unbackable and Krita dies with SIGBUS rather than SIGSEGV.
    # kritarc now points here; this dir must exist or that fix silently regresses.
    # Storage/thunderbird is not scratch: it is the mkOutOfStoreSymlink target
    # for ~/.thunderbird (see home/persist.nix). A symlink pointing at a missing
    # directory is worse than no symlink, since Thunderbird's own mkdir fails
    # through a dangling link, so the target is created here.
    activation.ensureScratchDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "$HOME/Storage/tmp/claude" "$HOME/Storage/.cache/pip" \
        "$HOME/Storage/tmp/krita-swap" "$HOME/Storage/thunderbird"
    '';
    pointerCursor = {
      enable = true;
      package = pkgs.bibata-cursors-translucent;
      name = "Bibata-Modern-Translucent";
      size = 24;
      gtk.enable = true;
      x11.enable = true;
    };
  };
  manual.json.enable = true;
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    gtk4 = {
      theme = null;
    };
  };

  systemd = {
    user = {
      inherit sessionVariables;
    };
  };

  xdg = {
    configFile = {
      # ~/.local/bin holds user scripts (memd, agent-scaffold, tether, claude shims).
      # The graphical session's PATH comes from the systemd --user manager — niri runs
      # under systemd --user (launched via uwsm) — which reads
      # ~/.config/environment.d/. Unlike systemd.user.sessionVariables (no var
      # expansion → would clobber PATH), environment.d expands ${PATH}, so we PREPEND.
      # This makes ~/.local/bin reachable session-wide, compositor-agnostic: e.g. the
      # memd / agent-scaffold Claude Code hooks resolve in GUI-launched sessions (a
      # /cc launch) the same as in a terminal. Takes effect on next login.
      "environment.d/10-local-bin.conf".text = "PATH=\${HOME}/.local/bin:\${PATH}\n";

      # niri portal routing override. The niri-shipped niri-portals.conf routes the
      # FileChooser interface to "default=gnome;gtk" (gnome first), but
      # xdg-desktop-portal-gnome 50.x advertises FileChooser in its .portal metadata
      # yet does NOT export org.freedesktop.impl.portal.FileChooser at runtime, so
      # every file dialog (Brave downloads, virt-manager ISO picker, GTK Save-As)
      # silently failed with "No such interface ... FileChooser". A user-scoped
      # config takes precedence over /etc and pins FileChooser to the gtk backend,
      # which actually implements it. The other routes mirror the niri defaults.
      "xdg-desktop-portal/niri-portals.conf".text = ''
        [preferred]
        default=gnome;gtk
        org.freedesktop.impl.portal.Access=gtk
        org.freedesktop.impl.portal.Notification=gtk
        org.freedesktop.impl.portal.Secret=gnome-keyring
        org.freedesktop.impl.portal.FileChooser=gtk
      '';
    };

    desktopEntries = {
      antigravity = {
        name = "Antigravity";
        comment = "Antigravity Gemini Desktop Application";
        exec = "${config.home.homeDirectory}/.local/bin/antigravity";
        icon = "system-run";
        type = "Application";
        categories = [
          "Utility"
          "Development"
        ];
        mimeType = [ "x-scheme-handler/Antigravity" ];
      };
      antigravity-ide = {
        name = "Antigravity-IDE";
        comment = "Antigravity Desktop Integrated Development Environment";
        exec = "${config.home.homeDirectory}/.local/bin/antigravity-ide";
        icon = "${config.home.homeDirectory}/.local/share/Antigravity IDE/resources/app/resources/linux/code.png";
        type = "Application";
        categories = [
          "Development"
          "IDE"
        ];
      };
    };
  };
}

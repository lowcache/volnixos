{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  # Shared by home.sessionVariables and systemd.user.sessionVariables.
  sessionVariables = {
    # XDG_CURRENT_DESKTOP is deliberately unset: niri-session exports it.
    XDG_SESSION_TYPE = "wayland";
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
    # Scratch and caches off the 4G tmpfs root, for every session process.
    # XDG_CACHE_HOME comes from xdg.cacheHome (persist.nix); setting it here conflicts.
    TMPDIR = "${config.home.homeDirectory}/Storage/tmp";
    PIP_CACHE_DIR = "${config.home.homeDirectory}/Storage/.cache/pip";
    CLAUDE_CODE_TMPDIR = "${config.home.homeDirectory}/Storage/tmp/claude";
    # No NVIDIA render vars: the session renders on the AMD iGPU (use `nvrun`).
  };

in
{

  imports = [
    ./persist.nix
    ./pkgs.nix
    ./scripts.nix
    ./ci-poll.nix
    ./mcp-gateway.nix
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

  # Registers the vault only. Vault settings are left null for the same reason
  # as rbw: non-null makes .obsidian/*.json read-only store symlinks and every
  # in-app settings change fails. The vault itself lives in persisted ~/Documents.
  programs.obsidian = {
    enable = true;
    vaults.brain.target = "Documents/Brain";
  };

  services.memd = {
    enable = true;
    installClaudeHooks = true;
    sweep.interval = "30min";
  };

  home = {
    stateVersion = "24.11";
    enableNixpkgsReleaseCheck = false;
    inherit sessionVariables;
    # Targets that must exist before use. krita-swap: kritarc's swaplocation (up to
    # 10G mmapped; on the tmpfs root a full disk SIGBUSes Krita). thunderbird: the
    # ~/.thunderbird link target, which Thunderbird can't mkdir through.
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
      # ~/.local/bin holds user scripts (memd, tether, claude shims).
      # The graphical session's PATH comes from the systemd --user manager — niri runs
      # under systemd --user (launched via uwsm) — which reads
      # ~/.config/environment.d/. Unlike systemd.user.sessionVariables (no var
      # expansion → would clobber PATH), environment.d expands ${PATH}, so we PREPEND.
      # This makes ~/.local/bin reachable session-wide, compositor-agnostic: e.g. the
      # memd Claude Code hooks resolve in GUI-launched sessions (a
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
      # mimeApps owns this; force reclaims the runtime-written copy on the tmpfs root.
      "mimeapps.list".force = true;
    };

    # ~/.config/mimeapps.list sat unpersisted on tmpfs: every boot Thunderbird lost
    # default-client status, re-prompted, and dropped another userapp-*.desktop
    # into the persisted ~/.local/share/applications. Declared here instead.
    mimeApps = {
      enable = true;
      defaultApplications = {
        "x-scheme-handler/mailto" = "thunderbird.desktop";
        "x-scheme-handler/mid" = "thunderbird.desktop";
        "message/rfc822" = "thunderbird.desktop";
        "x-scheme-handler/net.thunderbird" = "thunderbird.desktop";
        # Previously written at runtime; kept so the read-only file does not drop them.
        "x-scheme-handler/bitwarden" = "bitwarden.desktop";
        "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
        "image/png" = "feh.desktop";
      };
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

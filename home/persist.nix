{ config, ... }: {

  xdg = {
    enable = true;
    # Move the XDG cache root off the 4G tmpfs onto the roomy ~/Storage volume.
    # This sets XDG_CACHE_HOME session-wide, so pip/llmfit/etc. all
    # cache to Storage by default instead of filling root (see home/default.nix).
    cacheHome = "${config.home.homeDirectory}/Storage/.cache";
    configFile = {
      # Color engine (apply_theme.py + themes/) for the niri/Noctalia session.
      "color-engine".source =
        config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/color-engine";
      # niri + Noctalia v5. Live-edit symlinks; Home Manager writes no files here
      # (see home/noctalia.nix), so no collision.
      "niri".source =
        config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/niri";
      "noctalia".source =
        config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/noctalia";
      "kitty".source =
        config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/kitty";
      "fastfetch".source =
        config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/fastfetch";
      "cava".source =
        config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/cava";
      "fuzzel".source =
        config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/fuzzel";
      "wlogout".source =
        config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/wlogout";
      # force: Noctalia natively themes starship and replaces this symlink with a
      # real file (its [palettes.noctalia] block), which made HM refuse to clobber
      # and failed the switch. force lets HM reclaim the symlink each activation.
      "starship.toml" = {
        source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/starship/starship.toml";
        force = true;
      };
      "kritarc".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Storage/krita-master/kritarc";
      "kritadisplayrc".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Storage/krita-master/kritadisplayrc";
    };
  };

  home = {
    file = {
      ".local/share/krita".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Storage/krita-master/krita";
      "Pictures/fromAi/outputs".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Storage/ai-generation/fooocus/outputs";
      # Android Studio SDK and AVD root. Both grow to multiple GB — the SDK
      # alone was 1.4G and helped fill the 4G tmpfs root to 100% on 2026-08-21 —
      # and both are re-downloadable, so they belong on the Storage volume
      # rather than /persist. ~/.android/avd is where emulator disk images land.
      "Android".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Storage/Android";
      ".android".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Storage/.android";
      # Thunderbird's profile root on Linux is ~/.thunderbird, NOT
      # ~/.config/thunderbird: profiles.ini, account setup, filters, and the
      # local mail stores all live here. Unpersisted it does not survive the
      # tmpfs wipe and Thunderbird comes up factory-new every boot. Mail stores
      # are the growth risk (IMAP caches grow without bound), so this goes to
      # the Storage volume rather than the /persist list — and it must be one
      # or the other, never both: impermanence bind-mounts refuse a non-canonical
      # target, so a path cannot be a symlink AND a persisted directory.
      # The Thunderbird cache already lands on Storage via XDG_CACHE_HOME.
      ".thunderbird".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Storage/thunderbird";
      # Non-hidden alias of the repo: antigravity (agy) rejects hidden paths as
      # workspace folders but does not resolve symlinks, mitigatef with workdir
      # ~/volnix to get full workspace registration.
      "volnix" = {
        source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config";
        force = true;
      };
      # Compat symlink for the imperative user profile. nix normally creates this
      # lazily; on tmpfs root it vanishes each boot, so pin it declaratively at the
      # persisted generation store (see ".local/state/nix/profiles" below). Stable
      # target `profiles/profile` always resolves to the current generation, so
      # `nix-env -iA nixos.<pkg>` binaries land on PATH via ~/.nix-profile/bin.
      ".nix-profile" = {
        source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/nix/profiles/profile";
        force = true;
      };
    };
    persistence."/persist" = {
      directories =
        let
          dotfiles = [
            ".npm"
            ".cargo"
            ".rustup"
            ".ssh"
            ".ollama"
            ".gnupg"
            ".claude"
            ".codex"
            ".gemini"
            ".nix-config"
            ".vscode-oss"
            ".antigravity"
            ".antigravity-ide"
            ".solc-select"
            ".foundry"
            ".ZAP"
            ".java"
            # mcp-gateway runtime state, NOT config (~/.config/mcp-gateway is
            # persisted separately). Holds oauth/ with the dynamically-registered
            # client_id and refresh tokens for remote backends like Cloudflare.
            # Unpersisted it is wiped with the tmpfs root and every reboot forces
            # a fresh browser authorization. Also holds transparency logs and
            # identity grants.
            ".mcp-gateway"
          ];
          config = [
            ".config/dconf"
            ".config/VSCodium"
            ".config/Antigravity"
            ".config/Antigravity IDE"
            ".config/Google"
            ".config/BraveSoftware"
            ".config/micro"
            # Spotify prefs plus the Users/ blob holding the logged-in session.
            # 32K and it does not grow, so it belongs here rather than on
            # Storage; the 6.4G audio cache already goes to ~/Storage/.cache
            # because the client honours XDG_CACHE_HOME. Without this, every
            # boot starts logged out.
            ".config/spotify"
            ".config/mcp-gateway"
            ".config/systemd/user"
            ".config/sops"
            ".config/memd"
            # rbw's imperative config (email, base_url, device_id) and the
            # desktop client's session. Unpersisted, both are wiped with the
            # tmpfs root and every boot starts logged out — which is exactly
            # the friction that kills password-manager adoption.
            ".config/rbw"
            ".config/Bitwarden"
          ];
          # Note: with XDG_CACHE_HOME redirected to ~/Storage/.cache (see home/default.nix),
          # caches no longer land on the 4G tmpfs by default. These entries remain as a
          # safety net for any app that hardcodes ~/.cache and ignores XDG. ".cache/llmfit"
          # added after it (an XDG-ignoring cache) filled root tmpfs to 100% on 2026-06-16.
          cache = [
            ".cache/pip"
            ".cache/noctalia"
            ".cache/nvidia"
            ".cache/llmfit"
          ];
          local = [
            ".local/share/npm-global"
            ".local/share/go"
            ".local/share/gem"
            ".local/share/fish"
            ".local/share/direnv"
            ".local/share/fonts"
            ".local/share/noctalia"
            ".local/share/keyrings"
            ".local/share/Google"
            ".local/share/flatpak"
            # Android /data for waydroid. The container mounts this as the
            # userdata partition, so every installed app and its data lands
            # here. Unpersisted it sits on the 4G tmpfs root and is both lost
            # on reboot and a refill of the crash we hit 2026-08-21.
            ".local/share/waydroid"
            ".local/share/applications"
            # opencode's session store, backing `tether continue` on the free
            # tiers. Unpersisted, every reboot orphans in-flight delegations:
            # the session id in ~/CodeRepo/tether/sessions survives the tmpfs
            # wipe but the conversation it points at does not.
            ".local/share/opencode"
            ".local/share/Antigravity-x64"
            ".local/share/Antigravity IDE"
            ".local/bin"
            ".local/state/noctalia"
            ".local/state/wireplumber"
            ".local/state/memd"
            # rbw's encrypted vault cache; re-syncable, but re-downloading the
            # whole vault on every boot defeats the agent.
            ".local/share/rbw"
            # Canonical imperative-profile generations. `nix-env -iA nixos.<pkg>`
            # writes profile-N-link + manifest here (XDG state profile). Persisting
            # this dir — NOT the ~/.nix-profile symlink (which is non-canonical and
            # recreated below) — is what makes ad-hoc installs survive the tmpfs wipe.
            ".local/state/nix/profiles"
          ];
          flatpak-var = [
            ".var/app"
          ];
          home-dirs = [
            "CodeRepo"
            "Documents"
            "unDevel"
            "Downloads"
            "Pictures"
            "Projects"
            "AppImage"
            "ZAP-Sessions"
            ".bin"
          ];
        in
        dotfiles ++ config ++ cache ++ local ++ flatpak-var ++ home-dirs;
      # Single files in $HOME that must survive the tmpfs wipe.
      # ~/.claude.json holds Claude Code config/state and lives OUTSIDE ~/.claude.
      files = [
        ".claude.json"
      ];
    };
  };
}

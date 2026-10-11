{ config, lib, ... }:
let
  inherit (config.lib.file) mkOutOfStoreSymlink;
  home = config.home.homeDirectory;
  # Live-edit links into the repo checkout (via /persist, its canonical path).
  dot = path: mkOutOfStoreSymlink "/persist${home}/.nix-config/dots/${path}";
  storage = path: mkOutOfStoreSymlink "${home}/Storage/${path}";
in
{
  xdg = {
    enable = true;
    # XDG_CACHE_HOME off the 4G tmpfs root, session-wide.
    cacheHome = "${home}/Storage/.cache";
    configFile =
      # Color engine for the niri/Noctalia session, then the live-edit dotfile dirs.
      # Home Manager writes no files under these (see home/shell.nix).
      lib.genAttrs
        [
          "color-engine"
          "niri"
          "noctalia"
          "kitty"
          "fastfetch"
          "cava"
          "fuzzel"
          "wlogout"
        ]
        (name: {
          source = dot name;
        })
      // {
        # force: Noctalia themes starship by replacing this link with a real file,
        # which would make HM refuse to clobber it and fail the switch.
        "starship.toml" = {
          source = dot "starship/starship.toml";
          force = true;
        };
        "kritarc".source = storage "krita-master/kritarc";
        "kritadisplayrc".source = storage "krita-master/kritadisplayrc";
      };
  };

  home = {
    file = {
      ".local/share/krita".source = storage "krita-master/krita";
      "Pictures/fromAi/outputs".source = storage "ai-generation/fooocus/outputs";
      # Android SDK and AVDs: multi-GB and re-downloadable, so Storage, not /persist.
      "Android".source = storage "Android";
      ".android".source = storage ".android";
      # Thunderbird's profile root (not ~/.config). Mail stores grow without bound,
      # so Storage rather than /persist; a path can be a symlink OR persisted, never
      # both (impermanence refuses a non-canonical target).
      ".thunderbird".source = storage "thunderbird";
      # Non-hidden alias of the repo: antigravity rejects hidden workspace paths
      # and doesn't resolve symlinks.
      "volnix" = {
        source = mkOutOfStoreSymlink "/persist${home}/.nix-config";
        force = true;
      };
      # Imperative-profile compat link; it would vanish with the tmpfs root. Points
      # at the persisted generations (".local/state/nix/profiles" below).
      ".nix-profile" = {
        source = mkOutOfStoreSymlink "${home}/.local/state/nix/profiles/profile";
        force = true;
      };
      # OmO extensions and MCP servers. force: these replaced hand-made copies.
      ".omo/agent/mcp.json" = {
        source = dot "omo/mcp.json";
        force = true;
      };
      ".omo/agent/extensions/statusline.js" = {
        source = dot "omo/statusline.js";
        force = true;
      };
      ".omo/agent/extensions/memd.js" = {
        source = dot "omo/memd.js";
        force = true;
      };
      ".omo/agent/extensions/rtk.js" = {
        source = dot "omo/rtk.js";
        force = true;
      };
      # claude-companion pulse adapter; it finds pulse-emit beside its real path.
      ".omo/agent/extensions/pulse.js" = {
        source = mkOutOfStoreSymlink "${home}/CodeRepo/noctalia-plugs/noctalia-claude-plugin/hooks/omo-pulse.js";
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
            # mcp-gateway runtime state (OAuth client ids + refresh tokens for remote
            # backends); unpersisted, every reboot forces re-authorization.
            ".mcp-gateway"
            # OmO agent state: auth, sessions, memory repo, extensions.
            ".omo"
          ];
          config = [
            ".config/dconf"
            ".config/VSCodium"
            ".config/Antigravity"
            ".config/Antigravity IDE"
            ".config/Google"
            ".config/BraveSoftware"
            ".config/micro"
            # Prefs + logged-in session (32K); the audio cache follows XDG_CACHE_HOME.
            ".config/spotify"
            ".config/mcp-gateway"
            ".config/systemd/user"
            ".config/sops"
            ".config/memd"
            # rbw's imperative config and the desktop client's session.
            ".config/rbw"
            ".config/Bitwarden"
            # Vault registry, window state, per-vault plugin trust.
            ".config/obsidian"
          ];
          # Safety net for apps that hardcode ~/.cache and ignore XDG_CACHE_HOME.
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
            # waydroid's userdata partition (installed apps and their data).
            ".local/share/waydroid"
            ".local/share/applications"
            # opencode sessions, backing `tether continue`.
            ".local/share/opencode"
            ".local/share/Antigravity-x64"
            ".local/share/Antigravity IDE"
            ".local/bin"
            ".local/state/noctalia"
            ".local/state/wireplumber"
            ".local/state/memd"
            # rbw's encrypted vault cache.
            ".local/share/rbw"
            # nix-env generations (the canonical path; ~/.nix-profile is linked above).
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
      # Claude Code config/state, outside ~/.claude.
      files = [
        ".claude.json"
      ];
    };
  };
}

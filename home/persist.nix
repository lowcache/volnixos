{ config, pkgs, lib, ... }: {

  xdg = {
    enable = true;
    configFile = {
      "quickshell".source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/quickshell/";
      "hypr".source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/hypr";
      "illogical-impulse".source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/illogical-impulse";
      "kitty".source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/kitty";
      "fastfetch".source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/fastfetch";
      "cava".source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/cava";
      "fuzzel".source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/fuzzel";
      "wlogout".source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/wlogout";
      "starship.toml".source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/starship/starship.toml";
      "fonts".source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/priv.bkup/fonts";
      "kritarc".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Storage/krita-master/kritarc";
      "kritadisplayrc".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Storage/krita-master/kritadisplayrc";
    };
  };

  home = {
    file = {
      ".local/share/krita".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Storage/krita-master/krita";
      ".gemini" = {
        source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/dots/gemini";
        force = true;
      };
      "Pictures/fromAi/outputs".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Storage/ai-generation/fooocus/outputs";
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
            ".nix-config"
            ".vscode-oss"
            ".antigravity"
            ".antigravity-ide"
            ".ZAP"
          ];
          config = [
            ".config/dconf"
            ".config/VSCodium"
            ".config/Antigravity"
            ".config/Antigravity IDE"
            ".config/Google"
            ".config/BraveSoftware"
            ".config/micro"
            ".config/mcp-gateway"
            ".config/systemd/user"
          ];
          cache = [
            ".cache/pip"
            ".cache/quickshell"
            ".cache/illogical-impulse"
            ".cache/nvidia"
          ];
          local = [
            ".local/share/npm-global"
            ".local/share/go"
            ".local/share/gem"
            ".local/share/fish"
            ".local/share/direnv"
            ".local/share/fonts"
            ".local/share/quickshell"
            ".local/share/keyrings"
            ".local/share/illogical-impulse"
            ".local/share/Google"
            ".local/share/flatpak"
            ".local/share/applications"
            ".local/share/Antigravity-x64"
            ".local/share/Antigravity IDE"
            ".local/bin"
            ".local/state/quickshell"
            ".local/state/illogical-impulse"
            ".local/state/wireplumber"
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
    };
  };
}

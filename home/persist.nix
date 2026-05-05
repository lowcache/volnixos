{ config, pkgs, lib, ... }: {

  xdg = {
	enable = true; 
    configFile = {
      "quickshell".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/quickshell/";
      "hypr".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/hypr";
      "illogical-impulse".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/illogical-impulse";
      "kitty".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/kitty";
      "fastfetch".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/fastfetch";
      "cava".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/cava";
      "fuzzel".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/fuzzel";
      "wlogout".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/wlogout";
      "starship.toml".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/starship/starship.toml";
    };
  };
  
  home.persistence."/persist" = {
    directories = let
      dotfiles = [
        ".gemini"
	    ".npm"
        ".cargo"
        ".rustup"
        ".ssh"
        ".ollama"
        ".gnupg"
        ".nix-config"
        ".vscode-oss"
        ".ZAP"
      ];
      config = [
        ".config/dconf" 
        ".config/VSCodium"
        ".config/Google"
        ".config/BraveSoftware"
        ".config/Jan"
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
        ".local/share/krita"
        ".local/share/fonts"
        ".local/share/quickshell"
        ".local/share/keyrings"
        ".local/share/illogical-impulse"
        ".local/share/Google"
        ".local/share/flatpak"
        ".local/share/Jan/data"
        ".local/state/quickshell"
        ".local/state/illogical-impulse" 
        ".local/state/wireplumber"
      ];
      flatpak-var = [
        ".var/app"
      ];
      home-dirs = [
        "Files"
        "CodeRep"
        "Documents"
        "unDevel"
        "Downloads"
        "Pictures"
        "Projects"
        "AppImage"
        "ZAP-Sessions"
      ];
    in
      dotfiles ++ config ++ cache ++ local ++ flatpak-var ++ home-dirs;
  };
}

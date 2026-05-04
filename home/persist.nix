{ config, pkgs, lib, ... }: {

  xdg.configFile = {
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

  home.persistence."/persist" = {
    directories = [
      ".gemini"
      ".local/share/npm-global"
      ".npm"
      ".local/share/go"
      ".cargo"
      ".rustup"
      ".local/share/gem"
      ".cache/pip"
      ".local/share/fish"
      ".local/share/direnv"
      ".local/share/krita" # Persist Krita settings & brushes
      ".local/share/fonts"
      ".local/state/quickshell"
      ".local/share/quickshell"
      ".local/share/illogical-impulse"
      ".local/state/illogical-impulse"
      ".cache/quickshell"
      ".cache/illogical-impulse"
      ".local/share/keyrings"
      ".local/state/wireplumber"
      ".config/dconf"
      ".ssh"
      ".gnupg"
      ".nix-config"
      ".vscode-oss"
      ".config/VSCodium"
      ".ollama"
      ".librewolf"
      ".config/Google"
      ".local/share/Google"
      ".local/share/flatpak"
      ".var/app"
      "Files"
      "CodeRep"
      "Documents"
      "unDevel"
      "Downloads"
      "Pictures"
      "Projects"
      ".config/BraveSoftware"
      ".ZAP" # Persistence for ZAP Config/CA [cite: 91]
      "ZAP-Sessions" # Persistence for ZAP Data [cite: 91]
    ];
  };
}

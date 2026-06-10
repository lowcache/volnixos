{ config, pkgs, lib, ... }: {

  imports = [
    ./shell.nix
    ./pkgs.nix
    ./session.nix
    ./persist.nix
    ./browsers.nix
    ./memd.nix
  ];

  home = {
    username = "lowcache";
    homeDirectory = "/home/lowcache";
    stateVersion = "24.11";
    enableNixpkgsReleaseCheck = false;
  };

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
  xdg.desktopEntries = {
    antigravity = {
      name = "Antigravity";
      comment = "Antigravity Gemini Desktop Application";
      exec = "${config.home.homeDirectory}/.local/bin/antigravity";
      icon = "system-run";
      type = "Application";
      categories = [ "Utility" "Development" ];
      mimeType = [ "x-scheme-handler/Antigravity" ];
    };
    antigravity-ide = {
      name = "Antigravity-IDE";
      comment = "Antigravity Desktop Integrated Development Environment";
      exec = "${config.home.homeDirectory}/.local/bin/antigravity-ide";
      icon = "${config.home.homeDirectory}/.local/share/Antigravity IDE/resources/app/resources/linux/code.png";
      type = "Application";
      categories = [ "Development" "IDE" ];
    };
  };
}

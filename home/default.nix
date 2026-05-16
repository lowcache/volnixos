{ config, pkgs, lib, ... }: {

  imports = [
    ./shell.nix
	  ./pkgs.nix
	  ./session.nix
	  ./persist.nix
  ];

  home = {
    username = "nondeus";
    homeDirectory = "/home/nondeus";
    stateVersion = "24.11";
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

}

# Module layer for volnixos hosts. Each file owns one concern; host instances
# (../hosts/<name>.nix) set options and machine values on top.
{
  imports = [
    ./anonymous-mode.nix
    ./ai-stack.nix
    ./audio.nix
    ./backup.nix
    ./boot.nix
    ./containers.nix
    ./desktop.nix
    ./networking.nix
    ./nix-settings.nix
    ./packages.nix
    ./programs.nix
    ./secrets.nix
    ./services.nix
    ./systemd.nix
    ./users.nix
  ];
}

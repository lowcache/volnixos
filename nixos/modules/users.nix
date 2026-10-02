# Human accounts. The anon-mode isolation user lives in anonymous-mode.nix.
{
  config,
  username,
  ...
}:
{
  users = {
    # Root is tmpfs and passwords come from sops, so /etc/passwd is rebuilt
    # from this file every boot anyway; say so, and refuse imperative drift.
    mutableUsers = false;
    users = {
      root = {
        hashedPasswordFile = config.sops.secrets.root_password.path;
      };
      ${username} = {
        isNormalUser = true;
        hashedPasswordFile = config.sops.secrets.user_password.path;
        extraGroups = [
          "adbusers"
          "networkmanager"
          "wheel"
          "video"
          "docker"
          "uinput"
        ];
      };
    };
  };
}

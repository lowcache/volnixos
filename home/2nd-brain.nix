# 2nd Brain desktop glue (plugin: github:lowcache/2nd-brain). Links the plugin's three files into the vault one by one,
# so the plugin folder stays writable for data.json, and provides `brain`: capture (Mod+B), open, and check — the
# sign-off triggers and the nag. Personal settings live in the vault's data.json, never here (this repo is public).
{
  config,
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  vault = config.programs.obsidian.vaults.brain.target;
  plugin = inputs.brain.packages.${pkgs.stdenv.hostPlatform.system}.default;

  brain = pkgs.writeShellApplication {
    name = "brain";
    runtimeInputs = [
      config.programs.obsidian.package
      osConfig.programs.niri.package
      osConfig.systemd.package
      pkgs.coreutils
      pkgs.jq
      pkgs.libnotify
      pkgs.wl-clipboard
    ];
    runtimeEnv.BRAIN_VAULT = "${config.home.homeDirectory}/${vault}";
    text = builtins.readFile ./2nd-brain.sh;
  };
in
{
  home.packages = [ brain ];

  home.file = lib.listToAttrs (
    map
      (f: lib.nameValuePair "${vault}/.obsidian/plugins/2nd-brain/${f}" { source = "${plugin}/${f}"; })
      [
        "main.js"
        "manifest.json"
        "styles.css"
      ]
  );

  # Ticks every 5 min of uptime; a longer wall-clock gap between ticks means login or resume (see 2nd-brain.sh).
  systemd.user.services.brain-check = {
    Unit.Description = "2nd Brain: mark sign-off due and nag";
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe brain} check tick";
    };
  };
  systemd.user.timers.brain-check = {
    Unit.Description = "2nd Brain sign-off check";
    Timer = {
      OnStartupSec = "2min";
      OnUnitActiveSec = "5min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}

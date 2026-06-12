{ config, pkgs, lib, ... }:
let
  memd = pkgs.stdenv.mkDerivation {
    pname = "memd";
    version = "0.1.0";
    src = ../scripts/memd;
    nativeBuildInputs = [ pkgs.python3 ];
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/bin
      install -m755 memd.py $out/bin/memd
      patchShebangs $out/bin/memd
    '';
    meta.description = "Agent-driven project memory curator for AI CLI sessions";
  };
in
{
  home.packages = [ memd ];

  # Global agent tooling on PATH for every project, not just this repo.
  # Out-of-store symlinks (same rationale as dots/: live-editable without a
  # rebuild); the sweep timer keeps using the hermetic store copy above.
  home.file = {
    ".local/bin/memd" = {
      source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/scripts/memd/memd.py";
      force = true;
    };
    ".local/bin/tether" = {
      source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/.model/agent-tether/bin/tether";
      force = true;
    };
    ".local/bin/agent-scaffold" = {
      source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/.nix-config/scripts/agent-scaffold/agent-scaffold";
      force = true;
    };
  };

  # Periodic sweep: catches sessions the hooks missed (antigravity, crashes,
  # other CLIs via .memory/inbox/), prunes oversized files, auto-detects and
  # scaffolds new projects. Hooks handle the hot path at session boundaries.
  systemd.user.services.memd-sweep = {
    Unit.Description = "memd project-memory sweep";
    Service = {
      Type = "oneshot";
      ExecStart = "${memd}/bin/memd sweep";
      # claude lives in ~/.local/bin; git comes from the system profile
      Environment = "PATH=${config.home.homeDirectory}/.local/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin";
      Nice = 10;
    };
  };

  systemd.user.timers.memd-sweep = {
    Unit.Description = "Periodic memd project-memory sweep";
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "30min";
      RandomizedDelaySec = "2min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}

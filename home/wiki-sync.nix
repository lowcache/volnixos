# wiki-sync: a file landing in docs/wikifixins triggers an unattended pass that
# applies pending fixins to the wiki (claude -p, Sonnet), gates on the wiki's
# `make build`, commits, `make deploy`s via wrangler, then fast-forwards main.
# Never pushes. `wiki-sync status | --dry-run | seed` for manual use.
{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  home = config.home.homeDirectory;
  fixinsDir = "${home}/.nix-config/docs/wikifixins";
  wikiDir = "${home}/Code/ORGs/cacheflow/lowcache/hugo.web/wiki.infernalcode";

  wiki-sync = pkgs.writeShellApplication {
    name = "wiki-sync";
    runtimeInputs = [
      pkgs.claude-code-tweaked
      osConfig.nix.package
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.gawk
      pkgs.git
      pkgs.gnugrep
      pkgs.gnumake
      pkgs.jq
      pkgs.libnotify
      pkgs.util-linux
    ];
    runtimeEnv = {
      WIKI_DIR = wikiDir;
      FIXINS_DIR = fixinsDir;
      NIXCFG_DIR = "${home}/.nix-config";
    };
    text = builtins.readFile ./wiki-sync.sh;
  };
in
{
  home.packages = [ wiki-sync ];

  systemd.user.services.wiki-sync = {
    Unit = {
      Description = "Apply docs/wikifixins to the wiki and deploy it";
      ConditionPathIsDirectory = wikiDir;
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe wiki-sync;
      TimeoutStartSec = "45min";
    };
  };

  systemd.user.paths.wiki-sync = {
    Unit.Description = "Watch docs/wikifixins for new or edited notes";
    Path.PathChanged = fixinsDir;
    Install.WantedBy = [ "paths.target" ];
  };
}

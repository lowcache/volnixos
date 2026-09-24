{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.phone-agent;
in
{
  config = lib.mkIf (cfg.enable && cfg.enableIngestWatcher) {
    systemd.user.services.phone-ingest-watcher = {
      description = "Process staged phone-agent files";
      path = [
        pkgs.jq
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${./scripts/ingest-watcher.sh} ${cfg.ingestDir}";
      };
      unitConfig.ConditionUser = cfg.user;
    };
    systemd.user.paths.phone-ingest-watcher = {
      description = "Watch phone-agent staged dir";
      pathConfig = {
        PathExistsGlob = "${cfg.ingestDir}/staged/*.json";
        Unit = "phone-ingest-watcher.service";
      };
      unitConfig.ConditionUser = cfg.user;
      wantedBy = [ "default.target" ];
    };
  };
}

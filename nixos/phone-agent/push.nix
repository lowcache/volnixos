{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.phone-agent;
  serverPy = pkgs.writeText "phone-push-server.py" ''
    import hmac
    import http.server
    import os

    PUSH_DIR = os.environ['PUSH_DIR']
    TOKEN_FILE = os.environ['TOKEN_FILE']
    PORT = int(os.environ['PORT'])
    BIND = os.environ['BIND']

    class AuthHandler(http.server.SimpleHTTPRequestHandler):
        def check_auth(self):
            auth_header = self.headers.get('Authorization')
            if not auth_header or not auth_header.startswith('Bearer '):
                return False
            token = auth_header.split('Bearer ', 1)[1].strip()
            try:
                with open(TOKEN_FILE, 'r') as f:
                    expected_token = f.read().strip()
                # Constant-time: a plain == leaks the token a byte at a time.
                return hmac.compare_digest(token, expected_token)
            except Exception:
                return False

        def translate_path(self, path):
            # SimpleHTTPRequestHandler strips '..' but still follows symlinks
            # out of the tree, so resolve before anything opens it.
            return os.path.realpath(super().translate_path(path))

        def contained(self):
            resolved = self.translate_path(self.path)
            root = os.path.realpath(PUSH_DIR)
            return resolved == root or resolved.startswith(root + os.sep)

        def guard(self):
            if not self.check_auth():
                self.send_error(401, "Unauthorized")
                return False
            # 404, not 403: a symlink pointing out of the tree should not
            # confirm that its target exists.
            if not self.contained():
                self.send_error(404, "File not found")
                return False
            return True

        def do_GET(self):
            if not self.guard():
                return
            super().do_GET()

        def do_HEAD(self):
            if not self.guard():
                return
            super().do_HEAD()

        def list_directory(self, path):
            self.send_error(403, "Directory listing disabled")
            return None

    if __name__ == '__main__':
        os.chdir(PUSH_DIR)
        server_address = (BIND, PORT)
        httpd = http.server.ThreadingHTTPServer(server_address, AuthHandler)
        httpd.serve_forever()
  '';
  daemon = pkgs.writeShellScriptBin "phone-push-server" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
      ]
    }:$PATH
    export PUSH_DIR="${cfg.pushDir}"
    export TOKEN_FILE="${toString cfg.tokenFile}"
    export PORT=${toString cfg.pushPort}
    export BIND="${cfg.pushBindAddr}"

    exec ${pkgs.python3}/bin/python3 ${serverPy}
  '';
in
{
  options.phone-agent = {
    enablePush = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Serve pushDir to the tailnet so the phone can pull files (laptop -> phone).";
    };
    pushDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/lowcache/push";
      description = "The one directory served. Populate it deliberately; nothing else is reachable.";
    };
    pushPort = lib.mkOption {
      type = lib.types.port;
      default = 8463;
      description = "Port on pushBindAddr. Needs a matching forwardPorts entry in vms.nix.";
    };
    pushBindAddr = lib.mkOption {
      type = lib.types.str;
      default = "192.168.101.1";
      description = "The tap address; NEVER 0.0.0.0";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.enablePush) {
    assertions = [
      {
        assertion = cfg.tokenFile != null;
        message = "phone-agent.tokenFile must be set (sops-nix secret path).";
      }
    ];

    systemd.user.tmpfiles.rules = [ "d ${cfg.pushDir} 0700 - - -" ];

    systemd.user.services.phone-push-server = {
      description = "Phone push server (read-only HTTP for phone to pull files)";
      serviceConfig = {
        ExecStart = "${daemon}/bin/phone-push-server";
        Restart = "on-failure";
        RestartSec = 10;
        # This listens on the tap and is reachable from the tailnet, so it gets
        # the same treatment as anything else exposed to a network.
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictAddressFamilies = [ "AF_INET" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        # Read-only: this serves files, it never accepts them.
        ReadOnlyPaths = [ cfg.pushDir ];
      };
      wantedBy = [ "default.target" ];
    };
  };
}

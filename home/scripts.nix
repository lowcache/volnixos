{
  config,
  osConfig,
  pkgs,
  ...
}:
let
  # net-gate addressing comes from the system config (vol.anon-mode in
  # nixos/modules/anonymous-mode.nix), which nixos/vms.nix also reads. Editing it
  # in one place now moves the guest, the host jail, and these wrappers together.
  anon = osConfig.vol.anon-mode;
  torVmIp = anon.torVmAddress;
  torSocksPort = toString anon.socksPort;
  # Fail fast if Tor isn't answering, and say which of the two failure modes it
  # is: a dead VM and a dead tor.service inside a live VM need different fixes,
  # and the old message asserted "arm it with anon-on" for both — which is what
  # masked a tor that had been dead for four days. runtimeShell is bash, so
  # /dev/tcp works; timeout bounds the connect so a black hole can't hang us.
  checkTorInputs = [
    pkgs.coreutils
    pkgs.bash
    pkgs.iputils
  ];
  checkTor = ''
    if ! timeout 2 bash \
        -c ": >/dev/tcp/${torVmIp}/${torSocksPort}" 2>/dev/null; then
      if ping -c1 -W1 ${torVmIp} >/dev/null 2>&1; then
        echo "tor: net-gate is up at ${torVmIp} but nothing listens on ${torSocksPort} —" >&2
        echo "     the guest's tor.service is down. Check: journalctl -u microvm@net-gate" >&2
      else
        echo "tor: net-gate VM unreachable at ${torVmIp} — start it with" >&2
        echo "     'sudo systemctl start microvm@net-gate'." >&2
      fi
      exit 1
    fi
  '';
  # Per-invocation SOCKS credentials. IsolateSOCKSAuth is on by default, so a
  # distinct user:pass gets a distinct circuit — one caller's traffic is not
  # correlated with the next's. The values are throwaway; tor only uses them as
  # an isolation key.
  socksCreds = ''creds="anon$RANDOM$RANDOM:x"'';
in
{
  # Tor per-app proxy wrappers. All route through the net-gate VM's SOCKS5
  # (P5-T1). Each checks VM reachability first. Referenced packages (brave,
  # curl, sudo) are already in the system/home closure — nothing new installed.
  home.packages = [
    # playwright-mcp's nixpkgs wrapper bakes a read-only PLAYWRIGHT_BROWSERS_PATH,
    # then tries to install chrome-for-testing inside it, so no browser launches.
    # Point --executable-path at the driver's own chrome instead: it is already in
    # playwright-mcp's runtime closure (no added size), it sets SSL_CERT_FILE and
    # FONTCONFIG_FILE, and it execs the exact chromium playwright-mcp was built
    # against. The previous loose script globbed all of /nix/store and picked a
    # stale playwright-chromium by sort order.
    (pkgs.writeShellApplication {
      name = "playwright-mcp-nix";
      runtimeInputs = [ pkgs.coreutils ];
      bashOptions = [ ];
      text = ''
        out="''${PLAYWRIGHT_MCP_OUTPUT:-$HOME/Storage/playwright-mcp}"
        mkdir -p "$out"
        exec ${pkgs.playwright-mcp}/bin/playwright-mcp \
          --headless --no-sandbox --isolated \
          --output-dir "$out" \
          --executable-path ${pkgs.playwright-driver.browsers}/chromium-*/chrome-linux64/chrome \
          "$@"
      '';
    })
    (pkgs.writeShellApplication {
      name = "tor-brave";
      runtimeInputs = [
        pkgs.brave
      ]
      ++ checkTorInputs;
      bashOptions = [ ];
      text = ''
        ${checkTor}
        exec brave \
          --proxy-server="socks5://${torVmIp}:${torSocksPort}" \
          --proxy-bypass-list="<-loopback>" \
          --user-data-dir="$HOME/.config/BraveSoftware/Brave-Browser-Tor" \
          "$@"
      '';
    })
    (pkgs.writeShellApplication {
      name = "tor-curl";
      runtimeInputs = [
        pkgs.curl
      ]
      ++ checkTorInputs;
      bashOptions = [ ];
      text = ''
        ${checkTor}
        ${socksCreds}
        exec curl -x "socks5h://$creds@${torVmIp}:${torSocksPort}" "$@"
      '';
    })
    (pkgs.writeShellApplication {
      name = "tor-check";
      runtimeInputs = [
        pkgs.curl
      ]
      ++ checkTorInputs;
      bashOptions = [ ];
      text = ''
        ${checkTor}
        ${socksCreds}
        exec curl -sS --max-time 30 \
          -x "socks5h://$creds@${torVmIp}:${torSocksPort}" \
          ${anon.exitCheckUrl}
      '';
    })
    # anon-run: the user-facing handle on the anonymous workload. All it does is
    # call anon-exec, which the system module owns (nixos/modules/anonymous-mode.nix).
    #
    # That indirection is the point: the confinement properties (loopback denied,
    # IPv6 refused, gateway resolv.conf bound over /etc/resolv.conf, anon.slice,
    # readiness gate) live in exactly one place, so what users run and what
    # anon-selftest proves cannot drift apart.
    #
    # No proxy variables here. Enforcement is the routing jail plus the guest's
    # REDIRECT rules, so the workload does not need to know Tor exists — and an
    # application that ignores proxy settings cannot bypass it. The SOCKS
    # interface stays available deliberately, through tor-curl and tor-brave.
    (pkgs.writeShellApplication {
      name = "anon-run";
      bashOptions = [ ];
      text = ''
        if [ "$#" -eq 0 ]; then
          echo "Usage: anon-run <command> [args...]" >&2
          echo "Arm first: sudo systemctl start anonymous.target" >&2
          exit 64
        fi
        exec /run/wrappers/bin/sudo /run/current-system/sw/bin/anon-exec "$@"
      '';
    })

    # lidkeep — close the lid without suspending, for a bounded window.
    #
    # The problem: HandleLidSwitch is unset everywhere in this repo and in the
    # effective logind config, so it sits on systemd's default of `suspend`.
    # Closing the lid freezes every process. They resume intact — suspend is not
    # a kill — but nothing PROGRESSES while the lid is shut, and anything
    # mid-flight over the network is usually dead by the time it comes back.
    # That is the wrong behaviour when the machine has to be physically carried
    # somewhere while a long job runs.
    #
    # WHY TIMED, AND NOT A PLAIN ON/OFF FLIP. A laptop that never suspends on
    # lid close is a laptop that runs at load inside a closed bag with no
    # airflow. A permanent toggle is one forgotten command away from a thermal
    # problem, so the hold always carries a deadline and releases itself.
    #
    # WHY AN INHIBITOR RATHER THAN services.logind.lidSwitch = "ignore". The
    # declarative option is a system-wide permanent change needing a rebuild to
    # set and another to undo, which is the opposite of a toggle. A logind
    # inhibitor is the mechanism desktops already use for this — niri holds one
    # on handle-power-key on this very machine — it needs no privilege, and it
    # cannot outlive the process holding it.
    #
    # WHY systemd-run RATHER THAN A BARE BACKGROUND PROCESS. systemd owns the
    # lifetime, the unit name is stable so `stop` always finds it, and the lock
    # dies with the unit even if the shell that started it is gone.
    #
    # Note when debugging: the inhibitor takes about a second to appear in
    # `systemd-inhibit --list`. Checking for it immediately after systemd-run
    # returns reports a false absence — that race is not a broken mechanism.
    (pkgs.writeShellApplication {
      name = "lidkeep";
      runtimeInputs = [
        pkgs.systemd
        pkgs.coreutils
      ];
      bashOptions = [ ];
      text = ''
        set -euo pipefail
        UNIT=lidkeep

        held() { [ "$(systemctl --user is-active $UNIT 2>/dev/null)" = active ]; }

        case "''${1-}" in
          stop)
            if held; then
              systemctl --user stop $UNIT
              echo "lidkeep: released. Closing the lid suspends again."
            else
              echo "lidkeep: not held; nothing to release."
            fi
            exit 0
            ;;
          status)
            if held; then
              echo "lidkeep: HELD — the lid will not suspend."
              systemd-inhibit --list 2>/dev/null | grep lidkeep || true
            else
              echo "lidkeep: not held. Closing the lid suspends."
            fi
            exit 0
            ;;
          -h|--help)
            echo "Usage: lidkeep [DURATION]   hold lid-open behaviour (default 30m)"
            echo "       lidkeep stop         release now"
            echo "       lidkeep status       show whether it is held"
            echo "DURATION: 90s, 45m, 2h, or a bare number meaning minutes."
            exit 0
            ;;
        esac

        DUR="''${1-30m}"
        case "$DUR" in
          *s) SEC=''${DUR%s} ;;
          *m) SEC=$(( ''${DUR%m} * 60 )) ;;
          *h) SEC=$(( ''${DUR%h} * 3600 )) ;;
          *[!0-9]*)
            echo "lidkeep: bad duration: $DUR" >&2
            echo "  use 90s, 45m, 2h, or a plain number meaning minutes." >&2
            exit 1
            ;;
          *) SEC=$(( DUR * 60 )) ;;
        esac
        if [ "$SEC" -le 0 ]; then
          echo "lidkeep: duration must be positive." >&2
          exit 1
        fi

        UNTIL=$(date -d "@$(( $(date +%s) + SEC ))" "+%H:%M")

        # Re-arming replaces the current window rather than stacking a second unit.
        if held; then systemctl --user stop $UNIT; fi

        # --quiet drops systemd-run's "Running as unit:" banner, which goes to
        # stderr and would otherwise print above our own message. Errors still show.
        systemd-run --quiet --user --unit=$UNIT --description="lid-switch inhibited until $UNTIL" \
          systemd-inhibit --what=handle-lid-switch --who=lidkeep \
                   --why="held until $UNTIL" --mode=block \
          sleep "$SEC" >/dev/null

        echo "lidkeep: held until $UNTIL. Lid close will NOT suspend until then."
        echo "  The session will also NOT lock — the lock fires on sleep, and"
        echo "  there is no sleep to fire on. Lock by hand if you are carrying it."
        echo "  In a closed bag this runs with no airflow. Release early with:"
        echo "    lidkeep stop"
        if [ "$SEC" -gt 7200 ]; then
          echo "  WARNING: over two hours of no-suspend. Deliberate?" >&2
        fi
      '';
    })
  ];

  # Global agent tooling on PATH for every project, not just this repo.
  # Out-of-store symlinks (same rationale as dots/: live-editable without a
  # rebuild). memd, tether and agent-scaffold each graduated to their own repos
  # under ~/CodeRepo (decision #18 for memd): a single live copy runs
  # everywhere, so there is no store/live drift to reconcile. python3 for the shebang comes from
  # the user profile already on the service PATH below.
  home.file = {
    ".local/bin/tether" = {
      source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/CodeRepo/tether/bin/tether";
      force = true;
    };
    ".local/bin/agent-scaffold" = {
      source = config.lib.file.mkOutOfStoreSymlink "/persist${config.home.homeDirectory}/CodeRepo/agent-scaffold/agent-scaffold";
      force = true;
    };
  };

  # opencode is tether's second worker backend (`tether run -m free|free-big|
  # free-fast`), driving OpenRouter's free tier so bulk work costs no Gemini
  # quota. Declarative because ~/.config is on the tmpfs root: hand-written here
  # it would be gone at the next boot and every free tier would fail closed.
  #
  # small_model matters as much as model. opencode calls a second, cheap model to
  # title sessions, and it defaults to a PAID one -- on this account that returned
  # "requires more credits, or fewer max_tokens" on every run. Pinning it to a
  # free model is what makes an otherwise-free delegation actually free.
  #
  # Both point at OpenCode Zen (opencode/*) rather than OpenRouter: Zen needs no
  # API key and no account, so a bare `opencode` works even where the sops secret
  # is not readable, and it proved the more reliable gateway. The same NVIDIA
  # model returns an empty body through OpenRouter and answers through Zen.
  #
  # The per-tier model chains live in tether itself, not here; this only sets
  # what a bare `opencode` does interactively.
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    model = "opencode/mimo-v2.5-free";
    small_model = "opencode/muse-spark-1.2-contributor-free";
    autoupdate = false; # the store owns the binary; self-update would fight it
    share = "disabled";
    plugin = [ "superpowers@git+https://github.com/obra/superpowers.git" ];
  };
}

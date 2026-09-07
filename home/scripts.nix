{ config, pkgs, ... }:
let
  # Single source of truth for the net-gate Tor VM address. Change here only.
  torVmIp = "192.168.100.2";
  torSocksPort = "9050";
  # Fail fast with a clear message if the Tor VM isn't up. runtimeShell is bash,
  # so /dev/tcp works; timeout bounds the connect so a dead VM can't hang us.
  checkTor = ''
    if ! ${pkgs.coreutils}/bin/timeout 2 ${pkgs.bash}/bin/bash \
        -c ": >/dev/tcp/${torVmIp}/${torSocksPort}" 2>/dev/null; then
      echo "tor: net-gate VM unreachable at ${torVmIp}:${torSocksPort} — arm it with 'sudo systemctl start anonymous.target' (or 'anon-on')." >&2
      exit 1
    fi
  '';
  # --- CI status feed for the prompt -----------------------------------------
  # `make git` spawns ci-poll, which follows the GitHub Actions run for the
  # commit just pushed and keeps ONE line in $XDG_RUNTIME_DIR/volnixos-ci.
  # dots/starship/starship.toml [custom.ci] only cats that file, so the prompt
  # never touches the network -- that is what keeps it inside starship's 500 ms
  # command timeout. Renaming the file means editing both sides.
  ciStateName = "volnixos-ci";

  # Per-step bar weights and expected durations for .github/workflows/build.yml.
  # `w` is the step's share of a 100-point bar (the twelve sum to exactly 100);
  # `s` is how long the step normally takes and drives ONLY the within-step
  # ramp; `l` is the label the prompt shows. w and s are deliberately not the
  # same ratio: `Build volnix toplevel` is measured between 155 s (everything
  # substituted) and 7783 s (cold), so it owns half the bar while `s` tracks the
  # common case. Step names must match the workflow exactly; an unknown name
  # falls back to $dw and its first 16 characters.
  ciWeights = pkgs.writeText "ci-poll-weights.json" (
    builtins.toJSON {
      "Set up job" = {
        w = 0.8;
        s = 1;
        l = "setup";
      };
      "Free disk space" = {
        w = 7.7;
        s = 73;
        l = "disk";
      };
      "Run actions/checkout@v4" = {
        w = 0.8;
        s = 1;
        l = "checkout";
      };
      "Run cachix/install-nix-action@v31" = {
        w = 3.3;
        s = 4;
        l = "install-nix";
      };
      "Run cachix/cachix-action@v16" = {
        w = 5.8;
        s = 7;
        l = "cachix-init";
      };
      "Assert the kernel is a cache hit" = {
        w = 21;
        s = 108;
        l = "kernel-hit";
      };
      "Build volnix toplevel" = {
        w = 51;
        s = 155;
        l = "toplevel";
      };
      "Build MicroVM runners" = {
        w = 3;
        s = 16;
        l = "microvm";
      };
      "Checks (fmt + lint)" = {
        w = 4.2;
        s = 5;
        l = "fmt+lint";
      };
      # cachix-action uploads the new closure in its POST step, so the thing
      # this whole module exists to watch is the second-to-last thing to finish.
      "Post Run cachix/cachix-action@v16" = {
        w = 0.6;
        s = 3;
        l = "cachix-push";
      };
      "Post Run actions/checkout@v4" = {
        w = 0.8;
        s = 1;
        l = "post";
      };
      "Complete job" = {
        w = 1.0;
        s = 1;
        l = "done";
      };
    }
  );

  ciScore = pkgs.writeText "ci-poll.jq" ''
    # One prompt line from a `gh run view` payload.
    #
    #   $tbl   step name -> {w: bar weight, s: expected seconds, l: short label}
    #   $dw    weight and seconds charged to a step the table does not know
    #   $now   epoch seconds, passed in so one poll reads one clock
    #   $knee  fraction of a step's band reached at its expected duration
    #   $cap   fraction of a step's band it can never exceed

    def pad2: tostring | if length < 2 then "0" + . else . end;
    def dur: floor as $s
      | if $s >= 3600 then "\(($s/3600)|floor)h\((($s%3600)/60)|floor|pad2)m"
        else "\(($s/60)|floor)m\(($s%60)|pad2)s" end;
    def wt:  ($tbl[.name].w) // $dw;
    def exp: ($tbl[.name].s) // $dw;
    def lbl: ($tbl[.name].l) // (.name[0:16]);

    # Progress through the RUNNING step, as a fraction of that step's own band.
    # Linear to $knee at the expected duration, then 1 - s/t decay toward $cap.
    # The decay is the point: `Build volnix toplevel` is estimated at 155 s but
    # has run 7783 s cold, and a plain linear ramp pins at the cap two minutes
    # in and then lies for two hours. This one still reads under $cap after a
    # 50x overrun, so a long build can never creep into the next step's share.
    def ramp($t; $s):
      if $t <= 0 then 0
      elif $t <= $s then $knee * ($t / $s)
      else $knee + ($cap - $knee) * (1 - ($s / $t))
      end;

    . as $r
    | [$r.jobs[]?.steps[]?] as $steps
    | (($r.startedAt // $r.createdAt) | fromdate) as $t0
    # Elapsed freezes at updatedAt once the run is terminal; otherwise the
    # lingering result line would keep counting up after the build finished.
    | (if $r.status == "completed" then (($r.updatedAt // $r.startedAt) | fromdate)
       else $now end) as $t1
    | (($t1 - $t0) | dur) as $el
    | ($steps | map(wt) | add // 1) as $total
    | ($steps | map(select(.status == "completed") | wt) | add // 0) as $done
    | ($steps | map(select(.status != "completed")) | .[0]) as $cur
    | (if $cur == null or $cur.startedAt == null then 0
       else ($cur | wt) * ramp($now - ($cur.startedAt | fromdate); ($cur | exp))
       end) as $part
    | ((100 * ($done + $part) / $total) | floor
       | if . > 99 then 99 elif . < 0 then 0 else . end) as $pct
    | if $r.status == "completed" then
        if $r.conclusion == "success" then " ok \($el)"
        elif $r.conclusion == "cancelled" or $r.conclusion == "skipped"
          then " \($r.conclusion) \($el)"
        else ($steps | map(select(.conclusion == "failure")) | .[0]) as $f
          | " \(if $f == null then ($r.conclusion // "failed")
                       else ($f | lbl) end) \($el)"
        end
      elif ($steps | length) == 0 then " queued \($el)"
      else " \($cur | if . == null then "…" else lbl end) \($el) \($pct)%"
      end
  '';
  # The poll loop itself, kept out of the ci-poll wrapper so the wrapper can
  # name it as a systemd-run target without self-reference.
  ciPollLoop = pkgs.writeShellScript "ci-poll-loop" ''
    set -uo pipefail

    GH=${pkgs.gh}/bin/gh
    JQ=${pkgs.jq}/bin/jq
    CAT=${pkgs.coreutils}/bin/cat
    DATE=${pkgs.coreutils}/bin/date
    MV=${pkgs.coreutils}/bin/mv
    SLEEP=${pkgs.coreutils}/bin/sleep
    ID_=${pkgs.coreutils}/bin/id

    REPO="$1"   # owner/name
    SHA="$2"    # commit to follow

    STATE="''${XDG_RUNTIME_DIR:-/run/user/$($ID_ -u)}/${ciStateName}"
    INTERVAL=''${CI_POLL_INTERVAL:-10}   # 10 s -> 360 API calls/h, well under the 5000 cap
    LINGER=''${CI_POLL_LINGER:-120}      # keep the result on screen this long, then clear
    APPEAR=''${CI_POLL_APPEAR:-90}       # give up if no run shows up for the commit

    # The interactive fish session exports GH_TOKEN from /run/secrets/gh_token
    # (home/shell.nix); a systemd --user unit inherits neither that nor any
    # other shell state. Read the sops secret here rather than forwarding the
    # token through systemd-run --setenv, where `systemctl show` would print it.
    if [ -z "''${GH_TOKEN:-}" ] && [ -r /run/secrets/gh_token ]; then
      GH_TOKEN=$($CAT /run/secrets/gh_token); export GH_TOKEN
    fi

    WEIGHTS=$($CAT ${ciWeights})
    T0=$($DATE +%s)

    # Write via rename so starship can never cat a half-written line.
    emit() { printf '%s\n' "$1" > "$STATE.new" && $MV -f "$STATE.new" "$STATE"; }
    # Truncating rather than removing keeps the path stable; `test -s` in the
    # starship module is false either way, so the segment just disappears.
    clear_() { : > "$STATE"; }
    since() {
      local s=$(( $($DATE +%s) - T0 ))
      printf '%dm%02ds' $(( s / 60 )) $(( s % 60 ))
    }

    # Phase 1 -- find the run. A docs-only push matches the workflow's
    # paths-ignore and never starts one, so time out quietly instead of
    # leaving a stuck "queued" in the prompt forever.
    emit " queued 0m00s"
    ID=""
    while :; do
      ID=$($GH run list --repo "$REPO" --commit "$SHA" --limit 1 \
             --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null) || ID=""
      [ -n "$ID" ] && break
      if [ $(( $($DATE +%s) - T0 )) -ge "$APPEAR" ]; then clear_; exit 0; fi
      emit " queued $(since)"
      $SLEEP 5
    done

    # Phase 2 -- poll to completion, then linger so the verdict is readable.
    misses=0
    while :; do
      json=$($GH run view "$ID" --repo "$REPO" \
               --json status,conclusion,startedAt,createdAt,updatedAt,jobs 2>/dev/null) || json=""
      line=""
      if [ -n "$json" ]; then
        line=$(printf '%s' "$json" | $JQ -r \
                 --argjson tbl "$WEIGHTS" --argjson dw 1 \
                 --argjson knee 0.85 --argjson cap 0.9 \
                 --argjson now "$($DATE +%s)" -f ${ciScore} 2>/dev/null) || line=""
      fi

      if [ -n "$line" ]; then
        misses=0
        emit "$line"
        if [ "$(printf '%s' "$json" | $JQ -r '.status')" = completed ]; then
          $SLEEP "$LINGER"; clear_; exit 0
        fi
      else
        # Hold the last good line through a blip; only admit to it if it sticks.
        misses=$(( misses + 1 ))
        [ "$misses" -ge 3 ] && emit " ci unreachable"
      fi
      $SLEEP "$INTERVAL"
    done
  '';
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
    (pkgs.writeShellScriptBin "playwright-mcp-nix" ''
      out="''${PLAYWRIGHT_MCP_OUTPUT:-$HOME/Storage/playwright-mcp}"
      ${pkgs.coreutils}/bin/mkdir -p "$out"
      exec ${pkgs.playwright-mcp}/bin/playwright-mcp \
        --headless --no-sandbox --isolated \
        --output-dir "$out" \
        --executable-path ${pkgs.playwright-driver.browsers}/chromium-*/chrome-linux64/chrome \
        "$@"
    '')
    (pkgs.writeShellScriptBin "tor-brave" ''
      ${checkTor}
      exec ${pkgs.brave}/bin/brave \
        --proxy-server="socks5://${torVmIp}:${torSocksPort}" \
        --proxy-bypass-list="<-loopback>" \
        --user-data-dir="$HOME/.config/BraveSoftware/Brave-Browser-Tor" \
        "$@"
    '')
    (pkgs.writeShellScriptBin "tor-curl" ''
      ${checkTor}
      exec ${pkgs.curl}/bin/curl --socks5-hostname ${torVmIp}:${torSocksPort} "$@"
    '')
    (pkgs.writeShellScriptBin "tor-check" ''
      ${checkTor}
      exec ${pkgs.curl}/bin/curl --socks5-hostname ${torVmIp}:${torSocksPort} \
        https://check.torproject.org/api/ip
    '')
    (pkgs.writeShellScriptBin "anon-run" ''
      ${checkTor}
      if [ "$#" -eq 0 ]; then
        echo "Usage: anon-run <command> [args...]" >&2
        exit 1
      fi
      exec /run/wrappers/bin/sudo -u anon-user ${pkgs.coreutils}/bin/env \
        https_proxy=socks5h://${torVmIp}:${torSocksPort} \
        http_proxy=socks5h://${torVmIp}:${torSocksPort} \
        "$@"
    '')

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
    (pkgs.writeShellScriptBin "lidkeep" ''
      set -euo pipefail
      SYSTEMCTL=${pkgs.systemd}/bin/systemctl
      RUN=${pkgs.systemd}/bin/systemd-run
      INHIBIT=${pkgs.systemd}/bin/systemd-inhibit
      DATE=${pkgs.coreutils}/bin/date
      SLEEP=${pkgs.coreutils}/bin/sleep
      UNIT=lidkeep

      held() { [ "$($SYSTEMCTL --user is-active $UNIT 2>/dev/null)" = active ]; }

      case "''${1-}" in
        stop)
          if held; then
            $SYSTEMCTL --user stop $UNIT
            echo "lidkeep: released. Closing the lid suspends again."
          else
            echo "lidkeep: not held; nothing to release."
          fi
          exit 0
          ;;
        status)
          if held; then
            echo "lidkeep: HELD — the lid will not suspend."
            $INHIBIT --list 2>/dev/null | grep lidkeep || true
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

      UNTIL=$($DATE -d "@$(( $($DATE +%s) + SEC ))" "+%H:%M")

      # Re-arming replaces the current window rather than stacking a second unit.
      if held; then $SYSTEMCTL --user stop $UNIT; fi

      # --quiet drops systemd-run's "Running as unit:" banner, which goes to
      # stderr and would otherwise print above our own message. Errors still show.
      $RUN --quiet --user --unit=$UNIT --description="lid-switch inhibited until $UNTIL" \
        $INHIBIT --what=handle-lid-switch --who=lidkeep \
                 --why="held until $UNTIL" --mode=block \
        $SLEEP "$SEC" >/dev/null

      echo "lidkeep: held until $UNTIL. Lid close will NOT suspend until then."
      echo "  The session will also NOT lock — the lock fires on sleep, and"
      echo "  there is no sleep to fire on. Lock by hand if you are carrying it."
      echo "  In a closed bag this runs with no airflow. Release early with:"
      echo "    lidkeep stop"
      if [ "$SEC" -gt 7200 ]; then
        echo "  WARNING: over two hours of no-suspend. Deliberate?" >&2
      fi
    '')
    # ci-poll -- follow the GitHub Actions run for a commit and feed the prompt.
    #
    # WHY A FILE AND A POLLER, RATHER THAN THE PROMPT ASKING GITHUB DIRECTLY.
    # starship runs a custom module's command on every prompt and kills it at
    # 500 ms. A `gh run view` is a network round trip: it blows that budget on
    # a good day, hangs the prompt on a bad one, and would burn the API rate
    # limit one keystroke at a time. So one background poller does the talking
    # and leaves a single line behind; the prompt only does `test -s` + `cat`
    # against tmpfs, which is why [custom.ci] can never be what makes the shell
    # feel slow.
    #
    # WHY systemd-run RATHER THAN A BACKGROUND JOB. Same reasoning as lidkeep
    # above: systemd owns the lifetime, the unit name is stable so a second
    # `make git` supersedes the first poller instead of racing it for the state
    # file, and the poller outlives the terminal that spawned it.
    (pkgs.writeShellScriptBin "ci-poll" ''
      set -uo pipefail

      GIT=${pkgs.git}/bin/git
      SYSTEMCTL=${pkgs.systemd}/bin/systemctl
      RUN=${pkgs.systemd}/bin/systemd-run
      CAT=${pkgs.coreutils}/bin/cat
      ID_=${pkgs.coreutils}/bin/id
      UNIT=ci-poll

      STATE="''${XDG_RUNTIME_DIR:-/run/user/$($ID_ -u)}/${ciStateName}"

      case "''${1-}" in
        stop)
          $SYSTEMCTL --user stop $UNIT >/dev/null 2>&1 || true
          : > "$STATE"
          echo "ci-poll: stopped; prompt segment cleared."
          exit 0
          ;;
        status)
          if [ -s "$STATE" ]; then $CAT "$STATE"; else echo "ci-poll: idle."; fi
          exit 0
          ;;
        -h|--help)
          echo "Usage: ci-poll [SHA]    follow CI for SHA (default HEAD), detached"
          echo "       ci-poll stop     stop it and clear the prompt segment"
          echo "       ci-poll status   print the line the prompt is showing"
          echo ""
          echo "State file: $STATE"
          echo "Read by dots/starship/starship.toml [custom.ci]."
          echo "Tunables (env, forwarded into the unit):"
          echo "  CI_POLL_INTERVAL=10   seconds between GitHub polls"
          echo "  CI_POLL_LINGER=120    seconds the finished result stays on screen"
          echo "  CI_POLL_APPEAR=90     seconds to wait for a run to show up"
          exit 0
          ;;
      esac

      # Resolve owner/name from origin locally. `gh repo view` would be a
      # network call made before we even know there is a run worth watching.
      url=$($GIT remote get-url origin 2>/dev/null) || {
        echo "ci-poll: not in a git repo with an 'origin' remote." >&2
        exit 1
      }
      repo=''${url#git@github.com:}
      repo=''${repo#ssh://git@github.com/}
      repo=''${repo#https://github.com/}
      repo=''${repo%.git}
      # After the strips a github remote is exactly "owner/name". Anything
      # still carrying a scheme, a host, or extra path segments is not one.
      case "$repo" in
        *:* | *@* | */*/* | */ | /*)
          echo "ci-poll: origin is not a github.com owner/name remote: $url" >&2
          exit 1
          ;;
        */*) ;;
        *)
          echo "ci-poll: origin is not a github.com owner/name remote: $url" >&2
          exit 1
          ;;
      esac

      sha=''${1-$($GIT rev-parse HEAD)}
      short=$($GIT rev-parse --short "$sha")

      # Re-running supersedes the previous poller rather than stacking one.
      $SYSTEMCTL --user stop $UNIT >/dev/null 2>&1 || true

      # systemd-run hands the unit a clean environment, so an exported
      # CI_POLL_* would be read by nobody. Forward the ones that are set.
      setenv=""
      for v in CI_POLL_INTERVAL CI_POLL_LINGER CI_POLL_APPEAR; do
        [ -n "''${!v-}" ] && setenv="$setenv --setenv=$v=''${!v}"
      done

      # shellcheck disable=SC2086 -- $setenv is deliberately word-split
      $RUN --quiet --user --collect --unit=$UNIT $setenv \
        --description="GitHub Actions poll for $repo@$short" \
        ${ciPollLoop} "$repo" "$sha" >/dev/null

      echo "++ ci-poll: following $repo@$short - progress shows in the prompt."
      echo "++ 'ci-poll status' prints it, 'ci-poll stop' cancels it."
    '')
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
  };
}

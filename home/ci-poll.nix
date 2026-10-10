# CI status feed for the prompt: `ci-poll` follows the GitHub Actions run for a
# pushed commit and keeps one line in $XDG_RUNTIME_DIR for starship to cat.
{ lib, pkgs, ... }:
let
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
  ciPollLoop = lib.getExe (
    pkgs.writeShellApplication {
      name = "ci-poll-loop";
      runtimeInputs = [
        pkgs.gh
        pkgs.jq
        pkgs.coreutils
      ];
      bashOptions = [
        "nounset"
        "pipefail"
      ];
      text = ''
        REPO="$1"   # owner/name
        SHA="$2"    # commit to follow

        STATE="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${ciStateName}"
        INTERVAL=''${CI_POLL_INTERVAL:-10}   # 10 s -> 360 API calls/h, well under the 5000 cap
        LINGER=''${CI_POLL_LINGER:-120}      # keep the result on screen this long, then clear
        APPEAR=''${CI_POLL_APPEAR:-90}       # give up if no run shows up for the commit

        # The interactive fish session exports GH_TOKEN from /run/secrets/gh_token
        # (home/shell.nix); a systemd --user unit inherits neither that nor any
        # other shell state. Read the sops secret here rather than forwarding the
        # token through systemd-run --setenv, where `systemctl show` would print it.
        if [ -z "''${GH_TOKEN:-}" ] && [ -r /run/secrets/gh_token ]; then
          GH_TOKEN=$(cat /run/secrets/gh_token); export GH_TOKEN
        fi

        WEIGHTS=$(cat ${ciWeights})
        T0=$(date +%s)

        # Write via rename so starship can never cat a half-written line.
        emit() { printf '%s\n' "$1" > "$STATE.new" && mv -f "$STATE.new" "$STATE"; }
        # Truncating rather than removing keeps the path stable; `test -s` in the
        # starship module is false either way, so the segment just disappears.
        clear_() { : > "$STATE"; }
        since() {
          local s=$(( $(date +%s) - T0 ))
          printf '%dm%02ds' $(( s / 60 )) $(( s % 60 ))
        }

        # Phase 1 -- find the run. A docs-only push matches the workflow's
        # paths-ignore and never starts one, so time out quietly instead of
        # leaving a stuck "queued" in the prompt forever.
        emit " queued 0m00s"
        ID=""
        while :; do
          ID=$(gh run list --repo "$REPO" --commit "$SHA" --limit 1 \
                 --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null) || ID=""
          [ -n "$ID" ] && break
          if [ $(( $(date +%s) - T0 )) -ge "$APPEAR" ]; then clear_; exit 0; fi
          emit " queued $(since)"
          sleep 5
        done

        # Phase 2 -- poll to completion, then linger so the verdict is readable.
        misses=0
        while :; do
          json=$(gh run view "$ID" --repo "$REPO" \
                   --json status,conclusion,startedAt,createdAt,updatedAt,jobs 2>/dev/null) || json=""
          line=""
          if [ -n "$json" ]; then
            line=$(printf '%s' "$json" | jq -r \
                     --argjson tbl "$WEIGHTS" --argjson dw 1 \
                     --argjson knee 0.85 --argjson cap 0.9 \
                     --argjson now "$(date +%s)" -f ${ciScore} 2>/dev/null) || line=""
          fi

          if [ -n "$line" ]; then
            misses=0
            emit "$line"
            if [ "$(printf '%s' "$json" | jq -r '.status')" = completed ]; then
              sleep "$LINGER"; clear_; exit 0
            fi
          else
            # Hold the last good line through a blip; only admit to it if it sticks.
            misses=$(( misses + 1 ))
            [ "$misses" -ge 3 ] && emit " ci unreachable"
          fi
          sleep "$INTERVAL"
        done
      '';
    }
  );
in
{
  home.packages = [
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
    (pkgs.writeShellApplication {
      name = "ci-poll";
      runtimeInputs = [
        pkgs.git
        pkgs.systemd
        pkgs.coreutils
      ];
      bashOptions = [ ];
      text = ''
        set -uo pipefail
        UNIT=ci-poll

        STATE="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${ciStateName}"

        case "''${1-}" in
          stop)
            systemctl --user stop "$UNIT" >/dev/null 2>&1 || true
            : > "$STATE"
            echo "ci-poll: stopped; prompt segment cleared."
            exit 0
            ;;
          status)
            if [ -s "$STATE" ]; then cat "$STATE"; else echo "ci-poll: idle."; fi
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
        url=$(git remote get-url origin 2>/dev/null) || {
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

        sha=''${1-$(git rev-parse HEAD)}
        short=$(git rev-parse --short "$sha")

        # Re-running supersedes the previous poller rather than stacking one.
        systemctl --user stop "$UNIT" >/dev/null 2>&1 || true

        # systemd-run hands the unit a clean environment, so an exported
        # CI_POLL_* would be read by nobody. Forward the ones that are set.
        setenv=()
        for v in CI_POLL_INTERVAL CI_POLL_LINGER CI_POLL_APPEAR; do
          [ -n "''${!v-}" ] && setenv+=("--setenv=$v=''${!v}")
        done

        systemd-run --quiet --user --collect --unit="$UNIT" "''${setenv[@]}" \
          --description="GitHub Actions poll for $repo@$short" \
          ${ciPollLoop} "$repo" "$sha" >/dev/null

        echo "++ ci-poll: following $repo@$short - progress shows in the prompt."
        echo "++ 'ci-poll status' prints it, 'ci-poll stop' cancels it."
      '';
    })
  ];
}

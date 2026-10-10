# Shell tooling for anonymous mode, consumed by ./default.nix.
{
  config,
  lib,
  pkgs,
  cfg,
}:
let

  ip = "${pkgs.iproute2}/bin/ip";
  systemctl = "${config.systemd.package}/bin/systemctl";
  systemdRun = "${config.systemd.package}/bin/systemd-run";
  curl = "${pkgs.curl}/bin/curl";

  table = toString cfg.routingTable;
  priority = toString cfg.rulePriority;
  uidRange = "${toString cfg.uid}-${toString cfg.uid}";

  # Two defaults coexist in the jail's table. The gateway wins while armed; the
  # blackhole is the floor that outlives it, because it hangs off lo rather than
  # the tap and so survives the tap being torn down with the VM.
  gatewayMetric = "100";
  blackholeMetric = "1024";
  socks = "${cfg.torVmAddress}:${toString cfg.socksPort}";

  # Exits 69 unless anon-check has recorded L4; `guard` narrows when it applies.
  requireArmed = who: guard: ''
    if ${guard}[ ! -e ${cfg.readyStamp} ]; then
      echo "${who}: anonymous mode is not armed (no ${cfg.readyStamp}); arm it with: make anon-arm" >&2
      exit 69
    fi
  '';
  # A request through SOCKS to the exit check; success means tor carries traffic.
  socksRequest =
    maxTime:
    "${curl} -sS --max-time ${toString maxTime} --socks5-hostname ${socks} ${cfg.exitCheckUrl} >/dev/null 2>&1";
  # The exit IP from a check.torproject.org/api/ip body on stdin.
  exitIpFromBody = "sed -n 's/.*\"IP\":\"\\([^\"]*\\)\".*/\\1/p'";

  # /24-shaped check only: enough to catch an address that can never be reached
  # through the tap, without pulling a CIDR library into the eval.
  subnetPrefix = lib.concatStringsSep "." (lib.take 3 (lib.splitString "." cfg.torVmSubnet)) + ".";

  # Bounded TCP probe, deliberately one line: it is used as a command in
  # `if ...; then` and `... && exit 0`, which a multi-line string would break.
  probeSocks = "${pkgs.coreutils}/bin/timeout 2 ${pkgs.bash}/bin/bash -c ': >/dev/tcp/${cfg.torVmAddress}/${toString cfg.socksPort}' 2>/dev/null";

  # Installing the jail, idempotently, and then CHECKING THAT IT LANDED.
  #
  # Shared by anon-jail (at boot) and anon-watch (which re-asserts it every
  # tick), because a rule that silently fails to install is a fail-OPEN jail: uid
  # ${toString cfg.uid} falls through to the main table and straight out to the
  # clearnet (networkd once reaped the rule on a tap recreation while the unit
  # reported success). ManageForeignRoutingPolicyRules is off in default.nix; the
  # verification stays anyway: an unverified jail is not a jail.
  jailUp = lib.getExe (
    pkgs.writeShellApplication {
      name = "anon-jail-up";
      runtimeInputs = [ pkgs.gnugrep ];
      bashOptions = [ ];
      text = ''
        set -e

        for fam in "" "-6"; do
          ${ip} $fam rule list \
            | grep -q "uidrange ${uidRange} lookup ${table}" \
            || ${ip} $fam rule add uidrange ${uidRange} table ${table} priority ${priority}
        done

        # The floor of the jail. Installed unconditionally at a worse metric than the
        # gateway, so arming does not remove it and it simply wins again the moment
        # the gateway route goes away. The previous "seal only if nothing owns the
        # default" form left table ${table} EMPTY when the kernel dropped the tap's
        # routes on a VM restart, and an empty table falls through to `main` — i.e.
        # straight to the clearnet. Being on lo is what makes it outlive the tap.
        ${ip} route replace blackhole 0.0.0.0/0 metric ${blackholeMetric} table ${table}
        ${ip} -6 route replace blackhole ::/0 metric ${blackholeMetric} table ${table}

        # Verify. Reporting success over an open jail is the worst failure available
        # to this module, so it is the one thing checked explicitly.
        for fam in "" "-6"; do
          if ! ${ip} $fam rule list \
              | grep -q "uidrange ${uidRange} lookup ${table}"; then
            echo "jail NOT installed: no '$fam' uidrange rule ${uidRange} -> table ${table}." >&2
            echo "uid ${toString cfg.uid} would reach the clearnet; refusing to report success." >&2
            exit 1
          fi
        done
        # Both families: the v6 floor is installed separately above, so it can be
        # missing on its own, and an empty v6 table falls through to `main`.
        for fam in "" "-6"; do
          if ! ${ip} $fam route show table ${table} \
              | grep -qE "^(blackhole )?default"; then
            echo "jail NOT sealed: table ${table} has no '$fam' default route at all." >&2
            exit 1
          fi
        done
      '';
    }
  );

  # THE gateway route, raised and withdrawn as one definition — used by
  # anon-routing's ExecStart/ExecStop, by anon-check when a verification fails,
  # and by anon-selftest's "gateway withdrawn" case.
  #
  # Callers must use THESE and not `systemctl start/stop anon-routing.service`.
  # The unit is not a safe handle on the route: anon-check and anonymous.target
  # both Require= it, and systemd stops a unit whose Requires= target is
  # explicitly stopped. So stopping anon-routing does not withdraw a route — it
  # tears down the whole stack (stamp removed, anon.slice reaped), and starting
  # it again restores only the route, leaving anonymous mode silently disarmed.
  # anon-selftest did exactly that on every run.
  routingUp = lib.getExe (
    pkgs.writeShellApplication {
      name = "anon-routing-up";
      runtimeInputs = [ pkgs.coreutils ];
      bashOptions = [ ];
      text = ''
        # The tap is created by the microvm unit and can lag it slightly.
        for _ in $(seq 1 30); do
          [ -d /sys/class/net/${cfg.tapInterface} ] && break
          sleep 1
        done
        if [ ! -d /sys/class/net/${cfg.tapInterface} ]; then
          echo "${cfg.tapInterface} never appeared — is microvm@net-gate running?" >&2
          exit 1
        fi
        ${ip} route replace ${cfg.torVmSubnet} dev ${cfg.tapInterface} \
          src ${cfg.tapAddress} table ${table}
        ${ip} route replace default via ${cfg.torVmAddress} dev ${cfg.tapInterface} \
          src ${cfg.tapAddress} metric ${gatewayMetric} table ${table}
      '';
    }
  );

  routingDown = lib.getExe (
    pkgs.writeShellApplication {
      name = "anon-routing-down";
      bashOptions = [ ];
      text = ''
        # anon-jail's blackhole floor is always underneath, so dropping the gateway
        # re-seals the table without a gap. Re-assert it first anyway: this must not
        # depend on anon-jail having run more recently than a flush.
        ${ip} route replace blackhole 0.0.0.0/0 metric ${blackholeMetric} table ${table}
        ${ip} route del default via ${cfg.torVmAddress} dev ${cfg.tapInterface} \
          metric ${gatewayMetric} table ${table} 2>/dev/null || true
        ${ip} route del ${cfg.torVmSubnet} dev ${cfg.tapInterface} table ${table} 2>/dev/null || true
      '';
    }
  );

  # The workload's resolver: the gateway, whose nat rules bend :53 into Tor's
  # DNSPort. Bound over /etc/resolv.conf inside anon-exec, so a workload that
  # never heard of Tor still resolves through it.
  anonResolvConf = pkgs.writeText "anon-resolv.conf" ''
    nameserver ${cfg.torVmAddress}
    options timeout:5 attempts:2
  '';

  # THE one definition of what "running as the anonymous workload" means. Both
  # anon-run (home/scripts.nix) and anon-selftest go through this, so the
  # confinement cannot drift between the thing users run and the thing tests
  # prove. Needs root to address the system manager; callers use sudo.
  anonExec = pkgs.writeShellApplication {
    name = "anon-exec";
    bashOptions = [ ];
    text = ''
      probe=0
      if [ "$1" = "--probe" ]; then
        # Used by anon-check/anon-watch, which are what ESTABLISHES readiness and
        # therefore cannot require it. Not for interactive use.
        probe=1
        shift
      fi
      if [ "$#" -eq 0 ]; then
        echo "Usage: anon-exec [--probe] <command> [args...]" >&2
        exit 64
      fi
      ${requireArmed "anon-exec" ''[ "$probe" = 0 ] && ''}
      # --pty when there is a terminal to attach, --pipe when output is captured.
      if [ -t 0 ] && [ -t 1 ]; then
        io=(--pty)
      else
        io=(--pipe --wait)
      fi
      exec ${systemdRun} \
        --slice=anon.slice \
        -p User=anon-user \
        -p Group=nogroup \
        --quiet --collect "''${io[@]}" \
        --working-directory=/tmp \
        --unit="anon-$$" \
        -p IPAddressDeny=localhost \
        -p RestrictAddressFamilies="AF_INET AF_UNIX AF_NETLINK" \
        -p NoNewPrivileges=yes \
        -p PrivateTmp=yes \
        -p ProtectHome=yes \
        -p ProtectSystem=strict \
        -p ProtectKernelTunables=yes \
        -p ProtectControlGroups=yes \
        -p BindReadOnlyPaths=${anonResolvConf}:/etc/resolv.conf \
        -- "$@"
    '';
  };

  # The path probe. Used by anon-check (L4) and anon-watch, and deliberately
  # incapable of leaking:
  #
  #   L4a identity  — the launcher must actually drop privileges: the confined
  #                   process is asked for its own uid. An unverified launcher
  #                   is as dangerous as an unverified jail.
  #   L4b jail      — the kernel's routing decision for the jailed uid, queried
  #                   FROM INSIDE the jail (a root-side `uid` hint has disagreed
  #                   with reality). Sends nothing, so it cannot leak.
  #   L4c exit      — only then a real, unbound request, exactly as a workload
  #                   issues it; safe because L4b just confirmed the route.
  pathProbe = lib.getExe (
    pkgs.writeShellApplication {
      name = "anon-path-probe";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
      ];
      bashOptions = [ ];
      text = ''
        who=$(${anonExec}/bin/anon-exec --probe ${pkgs.coreutils}/bin/id -u 2>/dev/null || true)
        if [ "$who" != "${toString cfg.uid}" ]; then
          echo "L4a FAIL: the launcher ran as uid '$who', not ${toString cfg.uid}." >&2
          echo "          the workload would not be governed by the jail at all." >&2
          exit 1
        fi

        # Queried from INSIDE the jail, not simulated from root with a `uid` hint.
        # Those can disagree: the root-side simulation has returned the tap
        # while the workload's own connection left over the WAN, so this assertion
        # passed over a leaking path. Asking through anon-exec puts the lookup in the
        # same uid/slice context as the traffic it is vouching for.
        decision=$(${anonExec}/bin/anon-exec --probe ${ip} route get ${cfg.probeAddress} 2>/dev/null || true)
        case "$decision" in
          *"dev ${cfg.tapInterface}"*) ;;
          *)
            echo "L4b FAIL: the kernel routes uid ${toString cfg.uid} somewhere other than" >&2
            echo "          ${cfg.tapInterface}: $decision" >&2
            exit 1
            ;;
        esac

        # Unbound, as a workload would issue it (L4b made that safe). -w reports
        # the address the socket left from, which separates "the jail did not apply"
        # from "the gateway mishandled it".
        err=$(mktemp)
        if ! out=$(${anonExec}/bin/anon-exec --probe ${curl} -sS --max-time 30 \
            -w '\nANONMETA local=%{local_ip} remote=%{remote_ip}' \
            ${cfg.exitCheckUrl} 2>"$err"); then
          echo "L4c FAIL: no answer through the enforced path." >&2
          echo "          client said: $(cat "$err")" >&2
          rm -f "$err"
          exit 1
        fi
        rm -f "$err"
        meta=$(printf '%s' "$out" | grep "^ANONMETA" || true)
        body=$(printf '%s' "$out" | grep -v "^ANONMETA")
        case "$body" in
          *'"IsTor":true'*) ;;
          *)
            echo "L4c FAIL: the enforced path answered but NOT via Tor: $body" >&2
            echo "          socket: $meta" >&2
            echo "          local=${cfg.tapAddress} only means the socket took the jail's" >&2
            echo "          source address. It does NOT prove the packets left via" >&2
            echo "          ${cfg.tapInterface}: a masqueraded egress reports the same, because" >&2
            echo "          SNAT happens in POSTROUTING, long after getsockname(). Confirm" >&2
            echo "          with a capture on ${cfg.tapInterface} before blaming the gateway." >&2
            exit 1
            ;;
        esac
        printf '%s' "$body" \
          | ${exitIpFromBody}
      '';
    }
  );

  # HOST SIDE OF THE VSOCK CHANNEL.
  #
  # cloud-hypervisor does NOT use kernel AF_VSOCK on the host. It implements
  # "hybrid vsock": the guest gets a real virtio-vsock device, but the host end
  # is a Unix socket (`--vsock cid=N,socket=notify.vsock`) speaking a small
  # handshake — write "CONNECT <port>\n", read "OK <assigned>\n", then the stream
  # is wired to that port in the guest.
  #
  # So `socat VSOCK-CONNECT:<cid>:<port>` cannot work here no matter what is
  # loaded: there is no kernel transport between this host and the guest. The
  # guest-side VSOCK-LISTEN is correct; only this end had to change.
  #
  # The socket is mode 0700 owned by the microvm user, so callers need root.
  anonVsock = pkgs.writeShellApplication {
    name = "anon-vsock";
    runtimeInputs = [ pkgs.python3 ];
    bashOptions = [ ];
    text = ''
      exec python3 ${pkgs.writeText "anon-vsock.py" (builtins.readFile ./anon-vsock.py)} "$@"
    '';
  };

  # Where cloud-hypervisor puts that socket. microvm.nix runs the VM from its
  # own state directory and passes the socket name relative to it.
  anonBoxVsockUds = "${config.microvm.stateDir}/anon-box/notify.vsock";

  # L5 — THE WORKSTATION'S OWN PATH.
  #
  # L4 proves the HOST's uid-jail path. The workstation is a different client of
  # the same gateway: different source address, different leg, different nat
  # rules. L4 passing says nothing about whether anon-box's traffic is Tor'd, and
  # treating "the gateway is verified" as "the workstation is anonymous" would
  # reintroduce exactly the conflation this module exists to prevent — in a new
  # place, where the old checks cannot see it.
  #
  # Asked of the guest over vsock rather than simulated from here, for the same
  # reason L4b queries the routing decision from inside the jail instead of with
  # a `uid` hint from root: only the machine whose traffic it is can answer.
  workstationProbe = lib.getExe (
    pkgs.writeShellApplication {
      name = "anon-workstation-probe";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gnused
      ];
      bashOptions = [ ];
      text = ''
        out=$(timeout 45 ${anonVsock}/bin/anon-vsock \
          ${anonBoxVsockUds} ${toString cfg.workstation.verifyPort} plain 2>&1) || {
          echo "L5 FAIL: no answer from the workstation on vsock port ${toString cfg.workstation.verifyPort}." >&2
          echo "         is microvm@anon-box running? $out" >&2
          exit 1
        }
        if [ -z "$out" ]; then
          # Empty is NOT non-Tor: silence means the guest told us nothing at all.
          echo "L5 FAIL: the workstation answered with nothing." >&2
          echo "         that is a broken channel or a failed request INSIDE the" >&2
          echo "         guest, not evidence about the gateway. Look at:" >&2
          echo "           journalctl -u microvm@anon-box    # guest console" >&2
          exit 1
        fi
        case "$out" in
          *'"IsTor":true'*) ;;
          *)
            echo "L5 FAIL: the workstation reached the net, but NOT via Tor." >&2
            echo "         it said: $out" >&2
            echo "         suspect the gateway's nat rules for ${cfg.workstation.address}," >&2
            echo "         or its inner leg being unaddressed. The workstation itself" >&2
            echo "         cannot leak to the clearnet — it has no other route — so a" >&2
            echo "         non-Tor answer means the GATEWAY mishandled it." >&2
            exit 1
            ;;
        esac
        printf '%s' "$out" \
          | ${exitIpFromBody}
      '';
    }
  );

  # The workstation handle. Verify-then-enter: an anonymous shell you can open
  # before the path is proven is a shell you will use before the path is proven.
  anonShell = pkgs.writeShellApplication {
    name = "anon-shell";
    runtimeInputs = [ pkgs.coreutils ];
    bashOptions = [ ];
    text = ''
      ${requireArmed "anon-shell" ""}
      if ! ${systemctl} -q is-active microvm@anon-box.service; then
        echo "anon-shell: the workstation is not running." >&2
        echo "            it starts with anonymous.target; check: journalctl -u microvm@anon-box" >&2
        exit 69
      fi
      # The hybrid-vsock socket is mode 0700 owned by the microvm user, so both
      # the probe and the shell relay need root. Re-exec rather than make the
      # caller remember: anon-run already establishes that idiom.
      if [ "$(id -u)" != 0 ]; then
        exec /run/wrappers/bin/sudo "$0" "$@"
      fi
      echo "verifying the workstation's own path (L5)..." >&2
      if ! exit_ip=$(${workstationProbe}); then
        echo "anon-shell: refusing to open a shell on an unverified path." >&2
        exit 1
      fi
      echo "L5 ok — workstation egress via Tor exit $exit_ip" >&2
      # raw mode so job control and curses applications behave inside the guest.
      exec ${anonVsock}/bin/anon-vsock \
        ${anonBoxVsockUds} ${toString cfg.workstation.shellPort} raw
    '';
  };

  # Proves the NEGATIVE paths, which is the half that a working exit IP cannot
  # establish. "It has a Tor IP" says nothing about whether it could also have
  # left another way.
  # anon-selftest's workstation (anon-box) assertions.
  workstationAssertions = ''
    # ---- WORKSTATION (anon-box) ----------------------------------------
    # The positive path is proven by anon-shell's L5 gate. These are the
    # assertions that a working exit IP cannot make: that the isolation the
    # topology claims is actually there.

    # 6. NEGATIVE: the host must hold no address on the workstation bridge.
    #    Everything else about this design rests on host and workstation
    #    sharing no L3. If someone adds an address here the isolation quietly
    #    evaporates and nothing else in the system would notice.
    if ${ip} -br addr show ${cfg.workstation.bridge} 2>/dev/null | grep -qE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/'; then
      bad "the host HAS an address on ${cfg.workstation.bridge} — it must hold none"
    else
      pass "host holds no address on ${cfg.workstation.bridge}"
    fi

    # 7. NEGATIVE: and therefore cannot reach the workstation at all.
    if timeout 4 ping -c1 -W2 ${cfg.workstation.address} >/dev/null 2>&1; then
      bad "the host can REACH the workstation at ${cfg.workstation.address}"
    else
      pass "workstation unreachable from the host (no shared L3)"
    fi

    if ${systemctl} -q is-active microvm@anon-box.service; then
      # 8. POSITIVE: the workstation's own egress is Tor'd (L5).
      if ws_ip=$(${workstationProbe}); then
        pass "workstation egress verified (Tor exit $ws_ip)"
      else
        bad "workstation egress is not verifiably Tor'd (reason above)"
      fi

      # 9. NEGATIVE: exactly ONE default route, pointing at the gateway. A
      #    second default is how a workstation silently acquires a way out
      #    that does not traverse tor.
      # Asked ONCE. Two calls are two separate measurements of a thing that
      # must be judged as one, and they can disagree.
      # -color=never: the vsock shell is a tty, and iproute2 colors addresses
      # there, so "via <addr>" never matched as a literal string.
      gw=$(printf '%s\n' 'ip -color=never route show default; exit' \
        | timeout 20 ${anonVsock}/bin/anon-vsock \
            ${anonBoxVsockUds} ${toString cfg.workstation.shellPort} plain 2>/dev/null \
        | grep "^default" || true)
      routes=$(printf '%s' "$gw" \
        | grep -c "^default" || true)
      if [ "$routes" = 1 ]; then
        case "$gw" in
          *"via ${cfg.workstation.gatewayAddress}"*)
            pass "workstation has exactly one default route, via the gateway" ;;
          *)
            bad "workstation's only default route does NOT point at the gateway: $gw" ;;
        esac
      else
        bad "workstation has $routes default routes (expected exactly 1)"
      fi
    else
      echo "SKIP  workstation assertions (microvm@anon-box is not running)"
    fi
  '';

  anonSelftest = pkgs.writeShellApplication {
    name = "anon-selftest";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.gnugrep
      pkgs.iputils
    ];
    bashOptions = [ ];
    text = ''
      fail=0
      pass() { echo "PASS  $1"; }
      bad() {
        echo "FAIL  $1"
        fail=1
      }

      if [ "$(id -u)" != 0 ]; then
        echo "anon-selftest must run as root (it toggles the gateway route)." >&2
        exit 77
      fi
      ${requireArmed "anon-selftest" ""}

      # 1. POSITIVE: the enforced path reaches the internet, and through Tor.
      if exit_ip=$(${pathProbe}); then
        pass "enforced path verified (uid, jail route, Tor exit $exit_ip)"
      else
        bad "enforced path is not verifiably Tor'd (reason above)"
      fi

      # 2. NEGATIVE: the host's stub resolver must be unreachable, or a
      #    proxy-ignorant application could leak its lookups to the LAN resolver.
      if ${anonExec}/bin/anon-exec --probe ${pkgs.coreutils}/bin/timeout 3 \
          ${pkgs.bash}/bin/bash -c ': >/dev/tcp/127.0.0.53/53' >/dev/null 2>&1; then
        bad "loopback resolver (127.0.0.53:53) is REACHABLE from the workload"
      else
        pass "loopback resolver is unreachable (no sideways DNS)"
      fi

      # 3. NEGATIVE: IPv6 must be refused at the socket, not merely unrouted.
      if ${anonExec}/bin/anon-exec --probe ${curl} -6 -sS --max-time 10 https://example.com >/dev/null 2>&1; then
        bad "IPv6 egress SUCCEEDED from the workload"
      else
        pass "IPv6 egress refused"
      fi

      # 4. NEGATIVE: SO_BINDTODEVICE must not escape the jail. Picking the WAN
      #    device explicitly is the obvious bypass attempt; table ${table} has no
      #    route through it, so the blackhole default must catch it.
      wan=$(${ip} route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p')
      if [ -n "$wan" ]; then
        if ${anonExec}/bin/anon-exec --probe ${curl} -sS --max-time 10 --interface "$wan" \
            https://example.com >/dev/null 2>&1; then
          bad "binding to the WAN device ($wan) ESCAPED the jail"
        else
          pass "binding to the WAN device ($wan) is blackholed"
        fi
      fi

      # 5. NEGATIVE: with the gateway route withdrawn, the workload must have no
      #    connectivity — not fall back to the host's default route. This is the
      #    "gateway down" case, tested at the routing layer so the VM keeps
      #    running. If this script dies here the jail stays SEALED, which is the
      #    safe direction to fail in.
      #
      #    Withdrawn with routingDown, NOT by stopping anon-routing.service:
      #    anon-check and anonymous.target Require= it, so stopping it cascades
      #    into a full disarm (stamp deleted, anon.slice reaped).
      ${routingDown}
      if ${anonExec}/bin/anon-exec --probe ${curl} -sS --max-time 10 https://example.com >/dev/null 2>&1; then
        bad "workload still reached the internet with the gateway route REMOVED"
      else
        pass "gateway route removed => no connectivity (no clearnet fallback)"
      fi
      if ! ${routingUp}; then
        echo "anon-selftest: FAILED TO RESTORE the gateway route." >&2
        echo "               the jail is sealed (blackhole floor), so this is safe," >&2
        echo "               but anonymous mode is now down. Re-arm with:" >&2
        echo "               sudo systemctl restart anonymous.target" >&2
        exit 1
      fi

      ${workstationAssertions}

      if [ "$fail" = 0 ]; then
        echo "anon-selftest: all assertions held."
      else
        echo "anon-selftest: FAILURES above — treat anonymous mode as unsafe." >&2
      fi
      exit "$fail"
    '';
  };
in
{
  inherit
    systemctl
    curl
    socks
    socksRequest
    subnetPrefix
    probeSocks
    jailUp
    routingUp
    routingDown
    anonExec
    pathProbe
    anonVsock
    anonShell
    anonSelftest
    ;
}

# brain: 2nd Brain desktop glue, built by home/2nd-brain.nix (BRAIN_VAULT set there).
#   brain capture        Mod+B: focus Obsidian, open the capture box with a copied link prefilled
#   brain open           focus Obsidian on the home view (the nag's Open action)
#   brain check [tick]   timer: mark sign-off due on login/resume or 8 h since the last sign-off; nag every 20 min
#   brain check idle     Noctalia resume_command after 90 min idle: mark due and nag now
#   brain nag <text>     one notification, run detached by check

state="${XDG_STATE_HOME:-$HOME/.local/state}/2nd-brain"
gate="$BRAIN_VAULT/.brain/gate.json"

# niri doesn't let Obsidian raise itself when handed a URI, so focus it first.
focus_obsidian() {
  local id
  id=$(niri msg -j windows | jq -r 'first(.[] | select(.app_id == "md.obsidian.Obsidian") | .id) // empty')
  if [ -n "$id" ]; then niri msg action focus-window --id "$id"; fi
}

check() {
  local mode=$1 now signed=0 since=0 due last lastnag body
  mkdir -p "$state"
  now=$(date +%s)
  if [ -f "$gate" ]; then
    signed=$(jq -r '(.signedAt // 0) / 1000 | floor' "$gate")
    since=$(jq -r '(.since // 0) / 1000 | floor' "$gate")
  fi
  due=$(cat "$state/due" 2>/dev/null || echo 0)
  # Due = a trigger fired after the last sign-off; signing off in Obsidian clears it.
  mark() {
    if [ "$due" -le "$signed" ]; then
      due=$now
      echo "$now" >"$state/due"
    fi
  }
  if [ "$mode" = idle ]; then
    mark
    rm -f "$state/last-nag"
  else
    # The timer counts uptime only, so a long wall-clock gap means the machine slept or the user was logged out.
    # state is not persisted: after a reboot last-run is missing, which counts as login.
    last=$(cat "$state/last-run" 2>/dev/null || echo 0)
    if [ $((now - last)) -gt 1800 ]; then mark; fi
    if [ "$since" -gt 0 ] && [ $((now - since)) -ge 28800 ]; then mark; fi
    echo "$now" >"$state/last-run"
  fi
  [ "$due" -gt "$signed" ] || return 0
  lastnag=$(cat "$state/last-nag" 2>/dev/null || echo 0)
  [ $((now - lastnag)) -ge 1170 ] || return 0
  echo "$now" >"$state/last-nag"
  body=$(jq -r '.blockers // [] | join(" · ")' "$gate" 2>/dev/null || true)
  # Detached so a notification left open never blocks the next tick.
  systemd-run --user --collect --quiet --unit="brain-nag-$now" -- "$0" nag "${body:-Open the 2nd Brain to review this session.}"
}

case "${1:-}" in
  capture)
    # Wayland gives the clipboard only to the focused client, so the link is read here. Only a single http(s) link is
    # passed: anything else (e.g. a copied password) never reaches the URI or Obsidian's log.
    u=$(wl-paste -n 2>/dev/null | head -c 2048 || true)
    q=""
    case "$u" in
      *[[:space:]]*) ;;
      http://* | https://*) q="?url=$(printf %s "$u" | jq -sRr @uri)" ;;
    esac
    focus_obsidian
    exec obsidian "obsidian://brain-capture$q"
    ;;
  open)
    focus_obsidian
    exec obsidian "obsidian://brain-home"
    ;;
  check) check "${2:-tick}" ;;
  nag)
    # Ends before the next nag even if the notification is left open.
    action=$(timeout 19m notify-send -a "2nd Brain" -A open="Open 2nd Brain" --wait "Sign-off due" "${2:-}" || true)
    if [ "$action" = open ]; then exec "$0" open; fi
    ;;
  *)
    echo "usage: brain capture | open | check [tick|idle] | nag <text>" >&2
    exit 2
    ;;
esac

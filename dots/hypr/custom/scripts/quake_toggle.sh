#!/usr/bin/env bash
TARGET_MON="eDP-2"
MON_INFO=$(hyprctl monitors -j)
TARGET_DATA=$(echo "$MON_INFO" | jq -r --arg name "$TARGET_MON" ".[] | select(.name == \$name)")
[ -z "$TARGET_DATA" ] && TARGET_DATA=$(echo "$MON_INFO" | jq -r ".[] | select(.id == 0)")

MON_X=$(echo "$TARGET_DATA" | jq ".x")
MON_Y=$(echo "$TARGET_DATA" | jq ".y")

# Top position (Monitor Relative)
TOP_X=$((MON_X + 10))
TOP_Y=$((MON_Y + 37))

# Find the window
WINDOW=$(hyprctl clients -j | jq -r ".[] | select(.class == \"quake\")")

if [ -z "$WINDOW" ]; then
    # Not running, launch it once
    hyprctl dispatch exec "[workspace special:quake] /usr/bin/kitty --class quake"
    exit 0
fi

ADDR=$(echo "$WINDOW" | jq -r ".address")
WORKSPACE=$(echo "$WINDOW" | jq -r ".workspace.name")

if [[ "$WORKSPACE" == "special:quake" ]]; then
    # Show it: Bring to current workspace and position it
    hyprctl dispatch movetoworkspacesilent 1,address:$ADDR
    hyprctl dispatch focuswindow address:$ADDR
    hyprctl dispatch movewindowpixel exact $TOP_X $TOP_Y,address:$ADDR
else
    # Hide it: Move back to special workspace
    hyprctl dispatch movetoworkspacesilent special:quake,address:$ADDR
fi

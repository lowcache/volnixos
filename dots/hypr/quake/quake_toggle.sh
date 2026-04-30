#!/usr/bin/env bash
# Log file for debugging
LOG_FILE="/tmp/quake_toggle.log"
exec 2>>"$LOG_FILE"
echo "--- $(date) ---" >> "$LOG_FILE"

# Target Monitor Name (Focused)
MON_INFO=$(hyprctl monitors -j)
TARGET_DATA=$(echo "$MON_INFO" | jq -r ".[] | select(.focused == true)")

# Fallback to ID 0 if focus fails
[ -z "$TARGET_DATA" ] && TARGET_DATA=$(echo "$MON_INFO" | jq -r ".[] | select(.id == 0)")

if [ -z "$TARGET_DATA" ]; then
    echo "Error: Could not find monitor data" >> "$LOG_FILE"
    exit 1
fi

# Monitor absolute coordinates and size
MON_X=$(echo "$TARGET_DATA" | jq ".x")
MON_Y=$(echo "$TARGET_DATA" | jq ".y")
MON_W=$(echo "$TARGET_DATA" | jq ".width")
MON_H=$(echo "$TARGET_DATA" | jq ".height")

# Hyprland reserved space: [top, bottom, left, right]
RES_TOP=$(echo "$TARGET_DATA" | jq ".reserved[0]")
RES_BOT=$(echo "$TARGET_DATA" | jq ".reserved[1]")
RES_LFT=$(echo "$TARGET_DATA" | jq ".reserved[2]")
RES_RGT=$(echo "$TARGET_DATA" | jq ".reserved[3]")

# Viewable area (absolute)
VIEW_X=$((MON_X + RES_LFT))
VIEW_Y=$((MON_Y + RES_TOP))
VIEW_W=$((MON_W - RES_LFT - RES_RGT))
VIEW_H=$((MON_H - RES_TOP - RES_BOT))

# Quake states (absolute)
# TOP
TOP_X=$((VIEW_X + 10))
TOP_Y=$((VIEW_Y + 10))
TOP_W=$((VIEW_W - 20))
TOP_H=500

# BOTTOM
BOT_X=$((VIEW_X + 10))
BOT_Y=$((VIEW_Y + VIEW_H - 510))
BOT_W=$((VIEW_W - 20))
BOT_H=500

# FULL
FULL_X=$VIEW_X
FULL_Y=$VIEW_Y
FULL_W=$VIEW_W
FULL_H=$VIEW_H

# Get window info
WINDOW=$(hyprctl clients -j | jq -r ".[] | select(.class == \"quake\")")

if [ -z "$WINDOW" ]; then
    echo "Quake terminal not found, launching..." >> "$LOG_FILE"
    # Not running, launch it
    hyprctl dispatch exec "[workspace special:quake] uwsm app -- kitty --single-instance --class quake"
    exit 0
fi

ADDR=$(echo "$WINDOW" | jq -r ".address")
CUR_WORKSPACE=$(echo "$WINDOW" | jq -r ".workspace.name")
ACTIVE_WORKSPACE=$(hyprctl activeworkspace -j | jq -r ".name")
CUR_H=$(echo "$WINDOW" | jq -r ".size[1]")
CUR_Y=$(echo "$WINDOW" | jq -r ".at[1]")

echo "Quake found at $ADDR on workspace $CUR_WORKSPACE. Active is $ACTIVE_WORKSPACE." >> "$LOG_FILE"

ACTION=$1

case $ACTION in
    "full")
        # If height is large, we assume it's currently "full"
        if [ "$CUR_H" -gt 800 ]; then
            # Currently Full, restore to Top
            hyprctl dispatch movewindowpixel exact $TOP_X $TOP_Y,address:$ADDR
            hyprctl dispatch resizewindowpixel exact $TOP_W $TOP_H,address:$ADDR
        else
            # Currently Top or Bottom, make Full
            hyprctl dispatch resizewindowpixel exact $FULL_W $FULL_H,address:$ADDR
            hyprctl dispatch movewindowpixel exact $FULL_X $FULL_Y,address:$ADDR
        fi
        ;;
    "move")
        MIDPOINT=$((VIEW_Y + VIEW_H / 2))
        if [ "$CUR_Y" -lt "$MIDPOINT" ]; then
            # Currently in top half, move to Bottom
            hyprctl dispatch movewindowpixel exact $BOT_X $BOT_Y,address:$ADDR
            hyprctl dispatch resizewindowpixel exact $BOT_W $BOT_H,address:$ADDR
        else
            # Currently in bottom half, move to Top
            hyprctl dispatch movewindowpixel exact $TOP_X $TOP_Y,address:$ADDR
            hyprctl dispatch resizewindowpixel exact $TOP_W $TOP_H,address:$ADDR
        fi
        ;;
    *)
        # Default: Toggle visibility (Show/Hide)
        if [ "$CUR_WORKSPACE" == "$ACTIVE_WORKSPACE" ]; then
            # Visible here, hide it
            echo "Hiding quake terminal..." >> "$LOG_FILE"
            hyprctl dispatch movetoworkspacesilent special:quake,address:$ADDR
        else
            # Hidden, bring it here
            echo "Showing quake terminal on $ACTIVE_WORKSPACE..." >> "$LOG_FILE"
            hyprctl dispatch movetoworkspacesilent "$ACTIVE_WORKSPACE",address:$ADDR
            hyprctl dispatch focuswindow address:$ADDR
            
            # Always ensure it is positioned at TOP when first shown on this monitor
            hyprctl dispatch movewindowpixel exact $TOP_X $TOP_Y,address:$ADDR
            hyprctl dispatch resizewindowpixel exact $TOP_W $TOP_H,address:$ADDR
        fi
        ;;
esac

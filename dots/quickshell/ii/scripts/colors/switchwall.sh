#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"
terminalscheme="$SCRIPT_DIR/terminal/scheme-base.json"

handle_kde_material_you_colors() {
    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then return; fi
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_qt_apps=$(jq -r '.appearance.wallpaperTheming.enableQtApps' "$SHELL_CONFIG_FILE")
        if [ "$enable_qt_apps" == "false" ]; then return; fi
    fi
    local kde_scheme_variant="scheme-tonal-spot"
    "$XDG_CONFIG_HOME"/matugen/templates/kde/kde-material-you-colors-wrapper.sh --scheme-variant "$kde_scheme_variant" || true
}

pre_process() {
    local mode_flag="$1"
    if [[ "$mode_flag" == "dark" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    elif [[ "$mode_flag" == "light" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
    fi
    mkdir -p "$CACHE_DIR"/user/generated
}

    ~/.config/illogical-impulse/scripts/apply_theme.py petrified_spittoon
post_process() {
    handle_kde_material_you_colors > /dev/null 2>&1 &
    "$SCRIPT_DIR/code/material-code-set-color.sh" > /dev/null 2>&1 &
}

is_video() {
    local extension="${1##*.}"
    [[ "$extension" == "mp4" || "$extension" == "webm" || "$extension" == "mkv" || "$extension" == "avi" || "$extension" == "mov" ]] && return 0 || return 1
}

set_per_monitor_wallpaper_path() {
    local monitor="$1"
    local path="$2"
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        jq --arg monitor "$monitor" --arg path "$path" '.background.perMonitorWallpaper[$monitor] = $path' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    fi
}

set_wallpaper_path() {
    local path="$1"
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        jq --arg path "$path" '.background.wallpaperPath = $path' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    fi
}

switch() {
    imgpath="$1"; mode_flag="$2"; type_flag="$3"; color_flag="$4"; color="$5"; monitor_flag="$6"

    # Screen info for transition
    read scale screenx screeny screensizey < <(hyprctl monitors -j | jq '.[] | select(.focused) | .scale, .x, .y, .height' | xargs)
    cursorposx=$(hyprctl cursorpos -j | jq '.x' 2>/dev/null || echo 960)
    cursorposx=$(bc <<< "scale=0; ($cursorposx - $screenx) * $scale / 1")
    cursorposy=$(hyprctl cursorpos -j | jq '.y' 2>/dev/null || echo 540)
    cursorposy=$(bc <<< "scale=0; ($cursorposy - $screeny) * $scale / 1")
    cursorposy_inverted=$((screensizey - cursorposy))

    if [[ "$color_flag" == "1" ]]; then
        matugen_args=(color hex "$color")
    else
        if [[ -z "$imgpath" ]]; then exit 0; fi
        pkill -f -9 mpvpaper || true

        if is_video "$imgpath"; then
            if [[ -n "$monitor_flag" ]]; then
                set_per_monitor_wallpaper_path "$monitor_flag" "$imgpath"
                awww img -o "$monitor_flag" "$imgpath" --transition-type grow --transition-pos "$cursorposx,$cursorposy_inverted" &
                mpvpaper -o "no-audio loop" "$monitor_flag" "$imgpath" &
            else
                set_wallpaper_path "$imgpath"
                for monitor in $(hyprctl monitors -j | jq -r '.[] | .name'); do
                    mpvpaper -o "no-audio loop" "$monitor" "$imgpath" &
                done
            fi
            matugen_args=(image "$imgpath")
        else
            if [[ -n "$monitor_flag" ]]; then
                set_per_monitor_wallpaper_path "$monitor_flag" "$imgpath"
                awww img -o "$monitor_flag" "$imgpath" --transition-type grow --transition-pos "$cursorposx,$cursorposy_inverted" &
            else
                set_wallpaper_path "$imgpath"
                awww img "$imgpath" --transition-type grow --transition-pos "$cursorposx,$cursorposy_inverted" &
            fi
            matugen_args=(image "$imgpath")
        fi
    fi

    if [[ -z "$mode_flag" ]]; then
        if command -v gsettings >/dev/null 2>&1; then
            mode_flag=$(gsettings get org.gnome.desktop.interface color-scheme | tr -d "'" | cut -d- -f2)
        else
            mode_flag="dark"
        fi
    fi
    
    matugen_cmd=(matugen)
    [[ -n "$mode_flag" ]] && matugen_cmd+=(--mode "$mode_flag")
    [[ -n "$type_flag" && "$type_flag" != "auto" ]] && matugen_cmd+=(--type "$type_flag")
    "${matugen_cmd[@]}" "${matugen_args[@]}"

    pre_process "$mode_flag"
    
    # Material colors for python script
    VENV_PATH=$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)
    if [ -d "$VENV_PATH" ]; then
        source "$VENV_PATH/bin/activate"
        python3 "$SCRIPT_DIR/generate_colors_material.py" --path "$imgpath" --mode "$mode_flag" \
            > "$STATE_DIR"/user/generated/material_colors.scss
        "$SCRIPT_DIR"/applycolor.sh
        deactivate
    else
        echo "Warning: Virtual environment not found at $VENV_PATH. Skipping material colors generation via python."
        # Fallback: if material_colors.scss doesn't exist, we might have issues. 
        # But matugen already applied some themes.
    fi

    ~/.config/illogical-impulse/scripts/apply_theme.py petrified_spittoon
    post_process
}

main() {
    imgpath=""; mode_flag=""; type_flag=""; monitor_flag=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode) mode_flag="$2"; shift 2 ;;
            --type) type_flag="$2"; shift 2 ;;
            --monitor) monitor_flag="$2"; shift 2 ;;
            --image) imgpath="$2"; shift 2 ;;
            --noswitch) imgpath=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE"); shift ;;
            *) imgpath="$1"; shift ;;
        esac
    done
    switch "$imgpath" "$mode_flag" "$type_flag" "" "" "$monitor_flag"
}

main "$@"

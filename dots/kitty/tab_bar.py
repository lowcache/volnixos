# ~/.config/kitty/tab_bar.py
import datetime
import json
import subprocess
from collections import defaultdict

from kitty.boss import get_boss
from kitty.fast_data_types import Screen, add_timer, get_options
from kitty.tab_bar import (
    DrawData,
    ExtraData,
    Formatter,
    TabBarData,
    as_rgb,
    draw_attributed_string,
    draw_title,
)
from kitty.utils import color_as_int

opts = get_options()

# --- Configuration ---
# You can change these to match your theme
ICON_FG = as_rgb(0xEBD39D) # cream
ICON_BG = as_rgb(0x111314) # basalt_dim
ACTIVE_FG = as_rgb(0x111314) # basalt
ACTIVE_BG = as_rgb(0xAAD71E) # coral
INACTIVE_FG = as_rgb(0xD9AB77) # sage
INACTIVE_BG = as_rgb(0x111314) # basalt_deep

# Separators - WezTerm "Pill" Style
LEFT_SEP = ""
RIGHT_SEP = ""
SOFT_SEP = "│"

# Icons
ICON_ARCH = " " # Arch Linux Logo
ICON_CLOCK = " "
ICON_CALENDAR = " "
ICON_BATTERY_CHARGING = ""
ICON_BATTERY_DISCHARGING = ""
ICON_BELL = "ﳝ "
ICON_MAXIMIZED = " "

# Limits
MAX_TITLE_LEN = 25
REFRESH_TIME = 1

def _draw_icon(screen: Screen, index: int) -> int:
    """Draws the Arch Linux icon at the far left."""
    if index != 1:
        return 0
    
    fg, bg = screen.cursor.fg, screen.cursor.bg
    screen.cursor.fg = as_rgb(0x4E7DA8) # slate_blue
    screen.cursor.bg = 0 # Transparent background
    screen.draw(f" {ICON_ARCH} ")
    screen.cursor.fg, screen.cursor.bg = fg, bg
    return screen.cursor.x

def _get_battery_info():
    try:
        with open("/sys/class/power_supply/BAT0/status", "r") as f:
            status = f.read().strip()
        with open("/sys/class/power_supply/BAT0/capacity", "r") as f:
            percent = int(f.read().strip())
        
        icon = ICON_BATTERY_CHARGING if status != "Discharging" else ICON_BATTERY_DISCHARGING
        
        # Color logic based on percentage
        if percent < 20:
            color = as_rgb(color_as_int(opts.color1)) # Red
        elif percent < 50:
            color = as_rgb(color_as_int(opts.color3)) # Yellow
        else:
            color = as_rgb(color_as_int(opts.color2)) # Green
            
        return color, f"{icon} {percent}%"
    except FileNotFoundError:
        return 0, ""

def _draw_right_status(screen: Screen, is_last: bool) -> int:
    if not is_last:
        return 0
    
    # Get Data
    now = datetime.datetime.now()
    date_str = now.strftime("%d %b")
    time_str = now.strftime("%H:%M")
    bat_color, bat_str = _get_battery_info()

    # Calculate width
    # We add padding spaces to the calculation
    status_str = f" {bat_str}  {ICON_CALENDAR}{date_str}  {ICON_CLOCK}{time_str} "
    
    # Reset formatting
    draw_attributed_string(Formatter.reset, screen)
    
    # Move cursor to the right
    screen.cursor.x = screen.columns - len(status_str) - 2 # -2 for safety margin
    
    # Draw Battery
    if bat_str:
        screen.cursor.fg = bat_color
        screen.draw(f"{bat_str} ")

    # Draw Date
    screen.cursor.fg = as_rgb(color_as_int(opts.color4))
    screen.draw(f" {ICON_CALENDAR}{date_str} ")

    # Draw Time
    screen.cursor.fg = as_rgb(color_as_int(opts.color15))
    screen.draw(f" {ICON_CLOCK}{time_str} ")
    
    return screen.cursor.x

def _draw_title(draw_data: DrawData, screen: Screen, tab: TabBarData, index: int) -> int:
    # 1. Setup Colors based on State
    if tab.is_active:
        tab_bg = ACTIVE_BG
        tab_fg = ACTIVE_FG
        sep_fg = ACTIVE_BG
    else:
        tab_bg = INACTIVE_BG
        tab_fg = INACTIVE_FG
        sep_fg = INACTIVE_BG

    # 2. Draw Left Separator
    screen.cursor.bg = 0 # Transparent background for the curve
    screen.cursor.fg = sep_fg
    screen.draw(LEFT_SEP)

    # 3. Draw Title Content
    screen.cursor.bg = tab_bg
    screen.cursor.fg = tab_fg
    
    # Add indicators
    title = tab.title
    if tab.needs_attention:
        screen.cursor.fg = as_rgb(color_as_int(opts.color1)) # Red alert
        screen.draw(f" {ICON_BELL}")
        screen.cursor.fg = tab_fg
    
    if tab.layout_name == "stack":
        screen.draw(f" {ICON_MAXIMIZED}")

    # Smart Truncation
    if len(title) > MAX_TITLE_LEN:
        # Keep start and end: "dev...project"
        part_len = (MAX_TITLE_LEN - 3) // 2
        title = f"{title[:part_len]}…{title[-part_len:]}"
    
    screen.draw(f" {title} ")

    # 4. Draw Right Separator
    screen.cursor.bg = 0
    screen.cursor.fg = sep_fg
    screen.draw(RIGHT_SEP)
    screen.draw(" ") # Margin between tabs

    return screen.cursor.x

def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_title_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    
    # Initialize timer on first run
    global timer_id
    if timer_id is None:
        timer_id = add_timer(_redraw_tab_bar, REFRESH_TIME, True)

    _draw_icon(screen, index)
    _draw_title(draw_data, screen, tab, index)
    
    if is_last:
         _draw_right_status(screen, is_last)
         
    return screen.cursor.x

def _redraw_tab_bar(timer_id):
    tm = get_boss().active_tab_manager
    if tm is not None:
        tm.mark_tab_bar_dirty()

timer_id = None

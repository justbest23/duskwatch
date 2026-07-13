# lib-config.sh - shared config loader and org.kde.ScreenBrightness helpers,
# sourced by the brightness scripts.
EVENING_HOUR=19
EVENING_MINUTE=0
MORNING_HOUR=7
MORNING_MINUTE=0
DIMMED_PCT=30
NORMAL_PCT=100
DIMMED_TEMP=4000
NORMAL_TEMP=6500
DISPLAYS=""
FADE_DURATION=1200
FADE_STYLE=smooth
FADE_STEP_MINUTES=5
SNAP_DURATION=10
ONTIME_WINDOW=300
FULLSCREEN_BRIGHTNESS_SCOPE=active-screen

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/duskwatch/duskwatch.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source <(grep -E '^[A-Z_][A-Za-z0-9_]*=' "$CONFIG_FILE")
fi

# Runtime override state (day/night/schedule), separate from duskwatch.conf
# since it's set by the tray widgets rather than hand-edited - see
# set-mode.sh. Defaults to "schedule" (pure time-of-day behavior) if unset.
STATE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/duskwatch/state"
get_mode() {
    local mode
    mode=$(grep '^MODE=' "$STATE_FILE" 2>/dev/null | tail -1)
    mode=${mode#MODE=}
    echo "${mode:-schedule}"
}

# The brightness percentage the schedule says a display should sit at right
# now: mode override first, then plain time-of-day. Used by the fullscreen
# watcher to restore a display it brightened. Deliberately ignores mid-fade
# positions - a display leaving fullscreen snaps to the boundary target and
# the next schedule tick takes it from there.
schedule_target_pct() {
    case "$(get_mode)" in
        day) echo "$NORMAL_PCT"; return ;;
        night) echo "$DIMMED_PCT"; return ;;
    esac
    local now morning evening
    now=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
    morning=$(( MORNING_HOUR * 60 + MORNING_MINUTE ))
    evening=$(( EVENING_HOUR * 60 + EVENING_MINUTE ))
    if (( now >= morning && now < evening )); then
        echo "$NORMAL_PCT"
    else
        echo "$DIMMED_PCT"
    fi
}

SB_DEST=org.kde.Solid.PowerManagement
SB_IFACE=org.kde.ScreenBrightness.Display

sb_displays() {
    if [[ -n "$DISPLAYS" ]]; then
        echo "$DISPLAYS"
        return
    fi
    gdbus call --session --dest "$SB_DEST" \
        --object-path /org/kde/ScreenBrightness \
        --method org.freedesktop.DBus.Properties.Get \
        org.kde.ScreenBrightness DisplaysDBusNames 2>/dev/null |
        grep -o "'[^']*'" | tr -d "'"
}

sb_get() {
    local display=$1 prop=$2
    gdbus call --session --dest "$SB_DEST" \
        --object-path "/org/kde/ScreenBrightness/$display" \
        --method org.freedesktop.DBus.Properties.Get "$SB_IFACE" "$prop" 2>/dev/null |
        grep -o '[0-9]\+'
}

sb_label() {
    local display=$1
    gdbus call --session --dest "$SB_DEST" \
        --object-path "/org/kde/ScreenBrightness/$display" \
        --method org.freedesktop.DBus.Properties.Get "$SB_IFACE" Label 2>/dev/null |
        sed -n "s/.*'\(.*\)'.*/\1/p"
}

# Stable per-monitor calibration key derived from the Label, e.g.
# "Samsung Electric Company S24C750" -> Samsung_Electric_Company_S24C750.
# The displayN ids are positional: when a monitor drops off the brightness
# list (cable unplugged, DDC/CI disabled, ...) the remaining displays
# reindex, and calibration keyed by displayN would silently apply to
# whichever monitor slid into that slot. Label-derived keys stick to the
# physical monitor.
sb_cal_key() {
    printf '%s' "$(sb_label "$1")" | tr -cs 'A-Za-z0-9' '_'
}

# Map a ScreenBrightness display to its DRM connector name (e.g. DP-2) by
# matching the Label against each connected output's EDID product name -
# the same EDID field KWin builds the Label from. Needed because neither
# side exposes the other's identifier directly.
sb_connector() {
    local label
    label=$(sb_label "$1")
    [[ -z "$label" ]] && return
    python3 - "$label" <<'PY'
import pathlib, sys
label = sys.argv[1]
for p in sorted(pathlib.Path('/sys/class/drm').glob('card*-*')):
    try:
        if (p / 'status').read_text().strip() != 'connected':
            continue
        edid = (p / 'edid').read_bytes()
    except OSError:
        continue
    for k in range(4):
        d = edid[54 + 18 * k:54 + 18 * k + 18]
        if len(d) == 18 and d[:3] == b'\x00\x00\x00' and d[3] == 0xFC:
            name = d[5:18].decode('ascii', 'replace').strip()
            if name and label.endswith(name):
                print(p.name.split('-', 1)[1])
                sys.exit()
PY
}

sb_set() {
    local display=$1 val=$2
    # flags=1 suppresses the brightness OSD - confirmed empirically, KDE
    # doesn't document this bit locally. Without it, a 30-step fade pops the
    # OSD on every single step for the whole duration of the fade.
    gdbus call --session --dest "$SB_DEST" \
        --object-path "/org/kde/ScreenBrightness/$display" \
        --method "$SB_IFACE.SetBrightness" "$val" 1 >/dev/null 2>&1
}

# Per-display calibration: monitors differ wildly in perceived brightness at
# the same raw percentage, so a schedule target like 30% is mapped through
# each display's own floor/ceiling range (default 0/100) rather than applied
# to the raw 0-100 scale directly. Keys are FLOOR_<calkey>/CEIL_<calkey>
# (stable, label-derived - see sb_cal_key); legacy positional
# FLOOR_displayN/CEIL_displayN entries are still honored as a fallback.
sb_cal_floor() {
    local display=$1 key=$2
    local kv="FLOOR_$key" lv="FLOOR_$display"
    local v=${!kv:-}
    echo "${v:-${!lv:-0}}"
}

sb_cal_ceil() {
    local display=$1 key=$2
    local kv="CEIL_$key" lv="CEIL_$display"
    local v=${!kv:-}
    echo "${v:-${!lv:-100}}"
}

sb_calibrated_pct() {
    local display=$1 pct=$2
    local key floor ceil
    key=$(sb_cal_key "$display")
    floor=$(sb_cal_floor "$display" "$key")
    ceil=$(sb_cal_ceil "$display" "$key")
    echo $(( floor + (ceil - floor) * pct / 100 ))
}

#!/bin/bash
# fullscreen-brightness-watch.sh
# Watches the duskwatch inhibit helper's FullscreenOutputs property (the set
# of outputs that currently have a fullscreen/borderless window, maintained
# by the nightcolor-fullscreen-inhibit KWin script) and snaps brightness to
# NORMAL_PCT while a game is fullscreen, restoring the scheduled level when
# it goes away.
#
# FULLSCREEN_BRIGHTNESS_SCOPE (duskwatch.conf) picks which displays get
# brightened: "active-screen" (default) only the display(s) the fullscreen
# window is actually on - the others are left completely untouched - or
# "all" for every display. Only displays this script brightened itself are
# restored, so manual slider levels on other monitors survive a gaming
# session either way.
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

HELPER_DEST=org.duskwatch.NightLightInhibit
HELPER_PATH=/org/duskwatch/NightLightInhibit
HELPER_IFACE=org.duskwatch.NightLightInhibit

# Displays we have forced to NORMAL_PCT and still owe a restore.
declare -A BRIGHT

set_pct() {
    local display=$1 pct=$2 max
    max=$(sb_get "$display" MaxBrightness)
    [[ -n "$max" ]] && sb_set "$display" $(( max * $(sb_calibrated_pct "$display" "$pct") / 100 ))
}

# outputs is comma-separated connector names ("DP-2,HDMI-A-1"), "*" for all
# (legacy boolean channel), or "" for none.
wants_bright() {
    local display=$1 outputs=$2 conn
    [[ -z "$outputs" ]] && return 1
    [[ "$FULLSCREEN_BRIGHTNESS_SCOPE" == "all" || "$outputs" == "*" ]] && return 0
    conn=$(sb_connector "$display")
    # A display we can't map to a connector fails open (brightened): a game
    # screen stuck dim is worse than a side monitor coming up bright.
    [[ -z "$conn" || ",$outputs," == *",$conn,"* ]]
}

apply_state() {
    local outputs=$1 display
    for display in $(sb_displays); do
        if wants_bright "$display" "$outputs"; then
            if [[ -z "${BRIGHT[$display]:-}" ]]; then
                BRIGHT[$display]=1
                set_pct "$display" "$NORMAL_PCT"
            fi
        elif [[ -n "${BRIGHT[$display]:-}" ]]; then
            unset "BRIGHT[$display]"
            set_pct "$display" "$(schedule_target_pct)"
        fi
    done
}

get_outputs() {
    # Properties.Get doubles as D-Bus activation if the helper isn't up yet.
    gdbus call --session --dest "$HELPER_DEST" \
        --object-path "$HELPER_PATH" \
        --method org.freedesktop.DBus.Properties.Get \
        "$HELPER_IFACE" FullscreenOutputs 2>/dev/null |
        sed -n "s/.*<'\(.*\)'>.*/\1/p"
}

apply_state "$(get_outputs)"

# Process substitution rather than a pipe so the loop body shares the shell's
# BRIGHT array across iterations instead of mutating a subshell copy.
while read -r line; do
    if [[ "$line" == *PropertiesChanged* && "$line" == *"'FullscreenOutputs': <'"* ]]; then
        state=${line#*"'FullscreenOutputs': <'"}
        state=${state%%"'"*}
        apply_state "$state"
    fi
done < <(gdbus monitor --session --dest "$HELPER_DEST" --object-path "$HELPER_PATH")

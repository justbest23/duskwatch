#!/bin/bash
# fullscreen-brightness-watch.sh
# Watches org.kde.KWin.NightLight's "inhibited" property (set by the
# nightcolor-fullscreen-inhibit KWin script whenever a fullscreen/borderless
# window is active) and snaps brightness to NORMAL_PCT on every display while
# a game is fullscreen, restoring DIMMED_PCT when it isn't.
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

apply_state() {
    local inhibited=$1
    local pct=$DIMMED_PCT
    [[ "$inhibited" == "true" ]] && pct=$NORMAL_PCT
    for display in $(sb_displays); do
        max=$(sb_get "$display" MaxBrightness)
        [[ -n "$max" ]] && sb_set "$display" $(( max * $(sb_calibrated_pct "$display" "$pct") / 100 ))
    done
}

get_inhibited() {
    gdbus call --session --dest org.kde.KWin \
        --object-path /org/kde/KWin/NightLight \
        --method org.freedesktop.DBus.Properties.Get \
        org.kde.KWin.NightLight inhibited 2>/dev/null |
        grep -o 'true\|false'
}

apply_state "$(get_inhibited)"

gdbus monitor --session --dest org.kde.KWin --object-path /org/kde/KWin/NightLight |
while read -r line; do
    if [[ "$line" == *PropertiesChanged*org.kde.KWin.NightLight* && "$line" == *inhibited* ]]; then
        state=$(echo "$line" | grep -o "'inhibited': <\(true\|false\)>" | grep -o 'true\|false')
        [[ -n "$state" ]] && apply_state "$state"
    fi
done

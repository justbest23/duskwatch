#!/bin/bash
# fade-brightness.sh <target_percent> <duration_seconds>
# Fades all displays known to KDE's org.kde.ScreenBrightness D-Bus service to
# TARGET_PERCENT over DURATION seconds. This goes through the same interface
# System Settings and the brightness keys use, so it works uniformly whether
# a display is controlled via real DDC/CI or KWin's software brightness
# fallback (e.g. a monitor whose DDC/CI is flaky or unsupported).
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

TARGET=$1
DURATION=${2:-600}
STEPS=30

declare -A CURRENT MAX TARGET_RAW
for display in $(sb_displays); do
    max=$(sb_get "$display" MaxBrightness)
    current=$(sb_get "$display" Brightness)
    if [[ -n "$max" && -n "$current" ]]; then
        CURRENT[$display]=$current
        MAX[$display]=$max
        TARGET_RAW[$display]=$(( max * $(sb_calibrated_pct "$display" "$TARGET") / 100 ))
    else
        echo "gloaming: $display not responding, skipping" >&2
    fi
done

all_at_target=true
for display in "${!CURRENT[@]}"; do
    (( CURRENT[$display] != TARGET_RAW[$display] )) && all_at_target=false
done
"$all_at_target" && exit 0

STEP_SLEEP=$(awk "BEGIN { printf \"%f\", $DURATION / $STEPS }")

for i in $(seq 1 "$STEPS"); do
    for display in "${!CURRENT[@]}"; do
        diff=$(( TARGET_RAW[$display] - CURRENT[$display] ))
        val=$(( CURRENT[$display] + diff * i / STEPS ))
        sb_set "$display" "$val"
    done
    sleep "$STEP_SLEEP"
done

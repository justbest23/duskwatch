#!/bin/bash
# fade-brightness.sh <target_percent> <duration_seconds>
# Fades all displays known to KDE's org.kde.ScreenBrightness D-Bus service to
# TARGET_PERCENT over DURATION seconds. This goes through the same interface
# System Settings and the brightness keys use, so it works uniformly whether
# a display is controlled via real DDC/CI or KWin's software brightness
# fallback (e.g. a monitor whose DDC/CI is flaky or unsupported).
#
# FADE_STYLE (from duskwatch.conf) picks the shape of the transition:
#   smooth  (default) - truly linear: re-interpolates from elapsed wall-clock
#                        time every second and only sends a value when the
#                        raw integer actually changed, so long fades creep
#                        one unit at a time instead of visible jumps
#   stepped            - fewer, larger jumps spaced FADE_STEP_MINUTES apart,
#                         however many of those intervals fit in DURATION
#                         (clamped to [1, 500] steps so a stray config value
#                         can't spin this into a runaway loop)
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

TARGET=$1
DURATION=${2:-600}
(( DURATION < 1 )) && DURATION=1

# A newer fade supersedes any still-running one (leaves a paired
# fade-temperature alone - that's the other half of this same transition).
kill_running_fades '[f]ade-brightness\.sh'

declare -A CURRENT MAX TARGET_RAW
for display in $(sb_displays); do
    max=$(sb_get "$display" MaxBrightness)
    current=$(sb_get "$display" Brightness)
    if [[ -n "$max" && -n "$current" ]]; then
        CURRENT[$display]=$current
        MAX[$display]=$max
        TARGET_RAW[$display]=$(( max * $(sb_calibrated_pct "$display" "$TARGET") / 100 ))
    else
        echo "duskwatch: $display not responding, skipping" >&2
    fi
done

all_at_target=true
for display in "${!CURRENT[@]}"; do
    (( CURRENT[$display] != TARGET_RAW[$display] )) && all_at_target=false
done
"$all_at_target" && exit 0

if [[ "${FADE_STYLE:-smooth}" == "stepped" ]]; then
    STEP_SLEEP=$(awk "BEGIN { s = ${FADE_STEP_MINUTES:-5} * 60; if (s < 1) s = 1; printf \"%f\", s }")
    STEPS=$(awk "BEGIN { n = int($DURATION / $STEP_SLEEP + 0.5); if (n < 1) n = 1; if (n > 500) n = 500; print n }")
    for i in $(seq 1 "$STEPS"); do
        for display in "${!CURRENT[@]}"; do
            diff=$(( TARGET_RAW[$display] - CURRENT[$display] ))
            val=$(( CURRENT[$display] + diff * i / STEPS ))
            sb_set "$display" "$val"
        done
        sleep "$STEP_SLEEP"
    done
else
    # Linear interpolation anchored to wall-clock time (immune to drift from
    # sleep/D-Bus latency), writing only when a display's raw value changes.
    declare -A LAST
    for display in "${!CURRENT[@]}"; do
        LAST[$display]=${CURRENT[$display]}
    done
    start=$(date +%s)
    while :; do
        elapsed=$(( $(date +%s) - start ))
        (( elapsed > DURATION )) && elapsed=$DURATION
        for display in "${!CURRENT[@]}"; do
            diff=$(( TARGET_RAW[$display] - CURRENT[$display] ))
            val=$(( CURRENT[$display] + diff * elapsed / DURATION ))
            if (( val != LAST[$display] )); then
                sb_set "$display" "$val"
                LAST[$display]=$val
            fi
        done
        (( elapsed >= DURATION )) && break
        sleep 1
    done
fi

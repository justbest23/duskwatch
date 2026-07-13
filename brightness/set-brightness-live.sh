#!/bin/bash
# set-brightness-live.sh <percent>
# Immediately sets brightness on every display (calibrated per-display, no
# fade). For live slider dragging in the tray widgets - the scheduled fade
# logic in fade-brightness.sh is a separate, deliberately slower path.
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

PCT=$1

# A manual drag takes over from any running scheduled brightness fade -
# otherwise the fade re-imposes its interpolated value within a second and
# the slider appears to do nothing. (Color temperature fades are unrelated
# and keep running.)
kill_running_fades '[f]ade-brightness\.sh'

for display in $(sb_displays); do
    max=$(sb_get "$display" MaxBrightness)
    [[ -n "$max" ]] && sb_set "$display" $(( max * $(sb_calibrated_pct "$display" "$PCT") / 100 ))
done

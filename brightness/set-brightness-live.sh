#!/bin/bash
# set-brightness-live.sh <percent>
# Immediately sets brightness on every display (calibrated per-display, no
# fade). For live slider dragging in the tray widgets - the scheduled fade
# logic in fade-brightness.sh is a separate, deliberately slower path.
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

PCT=$1

for display in $(sb_displays); do
    max=$(sb_get "$display" MaxBrightness)
    [[ -n "$max" ]] && sb_set "$display" $(( max * $(sb_calibrated_pct "$display" "$PCT") / 100 ))
done

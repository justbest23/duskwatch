#!/bin/bash
# schedule-brightness.sh
# Duskwatch's actual redshift/gammastep equivalent: fades both brightness
# and color temperature together on a schedule, since Wayland clients can't
# set gamma tables directly and Redshift/gammastep don't work here at all.
#
# If a manual day/night override is set (see set-mode.sh), applies that and
# stops - this is what makes the tray widgets' mode switch actually stick
# instead of getting overwritten by the next periodic timer tick. Otherwise
# determines the targets from the current time of day (reading
# duskwatch.conf fresh each run, so schedule edits apply on the next periodic
# check without restarting anything) and fades to them. If we're firing near
# the actual scheduled boundary we do a slow fade; if we're catching up long
# after it - PC was off, late login, or the user just edited the schedule to
# a time already in the past - we snap to the target quickly instead.
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

apply() {
    local pct=$1 temp=$2 duration=$3
    ./fade-temperature.sh "$temp" "$duration" &
    ./fade-brightness.sh "$pct" "$duration"
    wait
}

mode=$(get_mode)
if [[ "$mode" == "day" ]]; then
    apply "$NORMAL_PCT" "$NORMAL_TEMP" "$SNAP_DURATION"
    exit 0
elif [[ "$mode" == "night" ]]; then
    apply "$DIMMED_PCT" "$DIMMED_TEMP" "$SNAP_DURATION"
    exit 0
fi

now=$(date +%s)
today=$(date +%Y-%m-%d)
hour=$(date +%-H)
evening_epoch=$(date -d "$today $EVENING_HOUR:00" +%s)
morning_epoch=$(date -d "$today $MORNING_HOUR:00" +%s)

if (( hour >= EVENING_HOUR )); then
    target=$DIMMED_PCT
    temp_target=$DIMMED_TEMP
    boundary=$evening_epoch
elif (( hour < MORNING_HOUR )); then
    target=$DIMMED_PCT
    temp_target=$DIMMED_TEMP
    boundary=$(( evening_epoch - 86400 ))
else
    target=$NORMAL_PCT
    temp_target=$NORMAL_TEMP
    boundary=$morning_epoch
fi

elapsed=$(( now - boundary ))
if (( elapsed <= ONTIME_WINDOW )); then
    duration=$FADE_DURATION
else
    duration=$SNAP_DURATION
fi

apply "$target" "$temp_target" "$duration"

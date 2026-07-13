#!/bin/bash
# fade-temperature.sh <target_kelvin> <duration_seconds>
# Fades KWin Night Color's temperature to TARGET_KELVIN over DURATION
# seconds, using the same FADE_STYLE/FADE_STEP_MINUTES timing as
# fade-brightness.sh so a scheduled transition moves brightness and color
# temperature together - this is Duskwatch's actual redshift/gammastep
# equivalent.
#
# Each step writes NightTemperature to kwinrc and reconfigures KWin with
# Night Color pinned to "Constant" mode: KWin then eases to the new value
# over ~2s (its QUICK_ADJUST_DURATION) and holds it indefinitely, silently.
# The previous implementation used NightLight.preview(), but as of KWin
# 6.7 every preview() call flashes the "Color Temperature Preview" OSD and
# arms a 15s auto-revert timer (it's built for the Settings slider drag,
# not schedules), which meant an OSD popup on every fade step and the
# temperature snapping back between steps. Constant mode has neither
# problem, and it also means closing the Settings window's live slider
# (stopPreview) now falls back to Duskwatch's scheduled value instead of
# reverting to KWin's own schedule.
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

TARGET=$1
DURATION=${2:-600}
(( DURATION < 1 )) && DURATION=1

# A newer fade supersedes any still-running one (leaves a paired
# fade-brightness alone - that's the other half of this same transition).
kill_running_fades '[f]ade-temperature\.sh'

NL_DEST=org.kde.KWin
NL_PATH=/org/kde/KWin/NightLight
NL_IFACE=org.kde.KWin.NightLight

# --notify is what makes this take effect live: KWin's nightlight plugin
# reloads its settings via KConfigWatcher (D-Bus change notifications),
# not via the generic org.kde.KWin.reconfigure - a plain kwriteconfig6
# write sits unread in kwinrc until something else pokes KWin.
nl_set() {
    kwriteconfig6 --notify --file kwinrc --group NightColor --key NightTemperature "$1"
}

# Take ownership of Night Color: Constant mode pins the temperature to
# NightTemperature with no day/night schedule of KWin's own to fight
# Duskwatch's (the fullscreen inhibit still overrides to neutral, that
# works at a level above the mode).
kwriteconfig6 --notify --file kwinrc --group NightColor --key Active true
kwriteconfig6 --notify --file kwinrc --group NightColor --key Mode Constant

CURRENT=$(gdbus call --session --dest "$NL_DEST" --object-path "$NL_PATH" \
    --method org.freedesktop.DBus.Properties.Get "$NL_IFACE" currentTemperature 2>/dev/null |
    grep -oP '(?<=uint32 )\d+|(?<=<)\d+(?=>)')
[[ -z "$CURRENT" ]] && CURRENT=$TARGET
if (( CURRENT == TARGET )); then
    # Already there visually - still commit the target so the config
    # matches (e.g. first run after switching modes).
    nl_set "$TARGET"
    exit 0
fi

if [[ "${FADE_STYLE:-smooth}" == "stepped" ]]; then
    STEP_SLEEP=$(awk "BEGIN { s = ${FADE_STEP_MINUTES:-5} * 60; if (s < 1) s = 1; printf \"%f\", s }")
    STEPS=$(awk "BEGIN { n = int($DURATION / $STEP_SLEEP + 0.5); if (n < 1) n = 1; if (n > 500) n = 500; print n }")
    for i in $(seq 1 "$STEPS"); do
        val=$(( CURRENT + (TARGET - CURRENT) * i / STEPS ))
        nl_set "$val"
        sleep "$STEP_SLEEP"
    done
else
    # Linear interpolation anchored to wall-clock time, committing only
    # when the kelvin value changes - a 4h fade nudges the temperature by
    # 1K every few seconds instead of jumping.
    last=$CURRENT
    start=$(date +%s)
    while :; do
        elapsed=$(( $(date +%s) - start ))
        (( elapsed > DURATION )) && elapsed=$DURATION
        val=$(( CURRENT + (TARGET - CURRENT) * elapsed / DURATION ))
        if (( val != last )); then
            nl_set "$val"
            last=$val
        fi
        (( elapsed >= DURATION )) && break
        sleep 1
    done
fi

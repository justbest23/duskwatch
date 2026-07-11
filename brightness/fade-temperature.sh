#!/bin/bash
# fade-temperature.sh <target_kelvin> <duration_seconds>
# Fades KWin Night Color's live-preview temperature to TARGET_KELVIN over
# DURATION seconds, using the same FADE_STYLE/FADE_STEP_MINUTES timing as
# fade-brightness.sh so a scheduled transition moves brightness and color
# temperature together - this is Duskwatch's actual redshift/gammastep
# equivalent (KWin's own Night Color still runs its own separate schedule
# if enabled; see README Known limitations for how the two interact).
#
# Uses NightLight.preview(), the same call the live Settings slider uses -
# there's no persistent "set the temperature" method, only ephemeral
# preview. It stays applied until something else calls stopPreview() or
# previews again, which is enough to hold a scheduled target between ticks.
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

TARGET=$1
DURATION=${2:-600}

NL_DEST=org.kde.KWin
NL_PATH=/org/kde/KWin/NightLight
NL_IFACE=org.kde.KWin.NightLight

nl_preview() {
    gdbus call --session --dest "$NL_DEST" --object-path "$NL_PATH" \
        --method "$NL_IFACE.preview" "$1" >/dev/null 2>&1
}

CURRENT=$(gdbus call --session --dest "$NL_DEST" --object-path "$NL_PATH" \
    --method org.freedesktop.DBus.Properties.Get "$NL_IFACE" currentTemperature 2>/dev/null |
    grep -oP '(?<=uint32 )\d+|(?<=<)\d+(?=>)')
[[ -z "$CURRENT" ]] && CURRENT=$TARGET
(( CURRENT == TARGET )) && exit 0

if [[ "${FADE_STYLE:-smooth}" == "stepped" ]]; then
    STEP_SLEEP=$(awk "BEGIN { s = ${FADE_STEP_MINUTES:-5} * 60; if (s < 1) s = 1; printf \"%f\", s }")
    STEPS=$(awk "BEGIN { n = int($DURATION / $STEP_SLEEP + 0.5); if (n < 1) n = 1; if (n > 500) n = 500; print n }")
else
    STEPS=30
    STEP_SLEEP=$(awk "BEGIN { printf \"%f\", $DURATION / $STEPS }")
fi

for i in $(seq 1 "$STEPS"); do
    val=$(( CURRENT + (TARGET - CURRENT) * i / STEPS ))
    nl_preview "$val"
    sleep "$STEP_SLEEP"
done

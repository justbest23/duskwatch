#!/bin/bash
# set-software-dimming.sh <displayN> on|off
# Forces KWin's software (gamma-based) brightness dimming for one display by
# disallowing DDC/CI hardware control on its output, or restores DDC/CI.
#
# "on" maps to `kscreen-doctor output.<connector>.ddcCi.disallow`: KWin then
# drops the hardware brightness device for that output and force-enables its
# software SDR brightness fallback (see kde_output_configuration_v2's
# set_ddc_ci_allowed handler), which also makes the display (re)appear in
# org.kde.ScreenBrightness if hardware control wasn't working. Software
# dimming scales the RGB values compositor-side - it can go darker than the
# hardware range allows, but the backlight stays at full power, so it saves
# no energy. The choice persists across sessions (kwinoutputconfig.json).
set -euo pipefail
cd "$(dirname "$0")"
source lib-config.sh

display=${1:-}
state=${2:-}
[[ -n "$display" && ( "$state" == on || "$state" == off ) ]] ||
    { echo "usage: $0 <displayN|connector> on|off" >&2; exit 1; }

# Accept either a ScreenBrightness display id or a raw connector name (the
# latter is how the calibration UI refers to outputs that have no
# brightness control yet, since those have no displayN).
if [[ "$display" =~ ^display[0-9]+$ ]]; then
    connector=$(sb_connector "$display")
    [[ -n "$connector" ]] ||
        { echo "could not map $display to an output connector" >&2; exit 1; }
else
    connector=$display
fi

if [[ "$state" == on ]]; then
    kscreen-doctor "output.$connector.ddcCi.disallow"
else
    kscreen-doctor "output.$connector.ddcCi.allow"
fi

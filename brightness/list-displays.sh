#!/bin/bash
# list-displays.sh
# Lists every connected output with its brightness/calibration state, one
# per line, pipe-delimited:
#   id|label|floor|ceil|calkey|connector|swdim
# - id: org.kde.ScreenBrightness display name (displayN), or "-" for a
#   connected output that currently has no brightness control at all (the
#   calibration UI shows those with a software-dimming offer instead of
#   silently omitting them)
# - floor/ceil: calibration (stable FLOOR_<calkey> preferred, legacy
#   FLOOR_displayN fallback, defaults 0/100)
# - calkey: stable label-derived calibration key (see sb_cal_key)
# - connector: DRM output name (DP-2, HDMI-A-1, ...), may be empty if the
#   label couldn't be matched to an EDID
# - swdim: "on" if DDC/CI is disallowed (KWin software dimming forced),
#   "off" if DDC/CI hardware control is active, "na" if the output has no
#   working DDC/CI (software dimming is then the only mechanism KWin has)
set -uo pipefail
cd "$(dirname "$0")"
source lib-config.sh

kscreen_json=$(kscreen-doctor -j 2>/dev/null)

swdim_for() { # connector
    [[ -z "$1" ]] && { echo na; return; }
    python3 -c "
import json, sys
conn = sys.argv[1]
try:
    outputs = json.loads(sys.argv[2])['outputs']
except Exception:
    outputs = []
state = 'na'
for o in outputs:
    if o.get('name') == conn:
        if 'ddcCiAllowed' in o:
            state = 'off' if o['ddcCiAllowed'] else 'on'
print(state)
" "$1" "$kscreen_json"
}

declare -A seen
for display in $(sb_displays); do
    label=$(sb_label "$display")
    key=$(sb_cal_key "$display")
    floor=$(sb_cal_floor "$display" "$key")
    ceil=$(sb_cal_ceil "$display" "$key")
    connector=$(sb_connector "$display")
    [[ -n "$connector" ]] && seen[$connector]=1
    echo "${display}|${label:-$display}|${floor}|${ceil}|${key}|${connector}|$(swdim_for "$connector")"
done

# Connected outputs with no ScreenBrightness object: KWin can't control
# their brightness right now (no working DDC/CI and software dimming not
# force-enabled). List them so the UI can offer the software-dimming toggle.
while IFS='|' read -r connector name; do
    [[ -z "$connector" || -n "${seen[$connector]:-}" ]] && continue
    echo "-|${name:-$connector}|0|100||${connector}|$(swdim_for "$connector")"
done < <(python3 <<'PY'
import pathlib
for p in sorted(pathlib.Path('/sys/class/drm').glob('card*-*')):
    try:
        if (p / 'status').read_text().strip() != 'connected':
            continue
        edid = (p / 'edid').read_bytes()
    except OSError:
        continue
    name = ''
    for k in range(4):
        d = edid[54 + 18 * k:54 + 18 * k + 18]
        if len(d) == 18 and d[:3] == b'\x00\x00\x00' and d[3] == 0xFC:
            name = d[5:18].decode('ascii', 'replace').strip()
    print(p.name.split('-', 1)[1] + '|' + name)
PY
)

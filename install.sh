#!/bin/bash
# install.sh - installs the KWin script and systemd units by symlinking them
# into place, so future edits in this repo take effect without reinstalling.
set -euo pipefail
cd "$(dirname "$0")"
REPO=$(pwd)

mkdir -p ~/.local/share/kwin/scripts ~/.config/systemd/user ~/.config/duskwatch
[[ -f ~/.config/duskwatch/duskwatch.conf ]] || cp config/duskwatch.conf.default ~/.config/duskwatch/duskwatch.conf

rm -rf ~/.local/share/kwin/scripts/nightcolor-fullscreen-inhibit
ln -sf "$REPO/kwin-scripts/nightcolor-fullscreen-inhibit" ~/.local/share/kwin/scripts/nightcolor-fullscreen-inhibit
kwriteconfig6 --file kwinrc --group Plugins --key nightcolor-fullscreen-inhibitEnabled true
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure

# D-Bus activation file for the Night Light inhibit helper (see
# helper/nightlight-inhibit-helper.py for why the KWin script can't call
# uninhibit itself). Generated rather than symlinked because Exec= needs the
# absolute repo path. SystemdService is required by dbus-broker, which only
# activates services through systemd; Exec covers classic dbus-daemon.
mkdir -p ~/.local/share/dbus-1/services
cat > ~/.local/share/dbus-1/services/org.duskwatch.NightLightInhibit.service <<EOF
[D-BUS Service]
Name=org.duskwatch.NightLightInhibit
Exec=$REPO/helper/nightlight-inhibit-helper.py
SystemdService=duskwatch-nightlight-inhibit-helper.service
EOF
chmod +x helper/nightlight-inhibit-helper.py

for unit in systemd/*.service systemd/*.timer systemd/*.path; do
    ln -sf "$REPO/$unit" ~/.config/systemd/user/"$(basename "$unit")"
done
systemctl --user daemon-reload
# Make the bus daemon rescan activation files (needed by dbus-broker; harmless
# no-op elsewhere).
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig 2>/dev/null || true

mkdir -p ~/.local/share/plasma/plasmoids
rm -rf ~/.local/share/plasma/plasmoids/org.duskwatch.trayapplet
ln -sf "$REPO/plasmoid" ~/.local/share/plasma/plasmoids/org.duskwatch.trayapplet

chmod +x brightness/*.sh

echo "Installed. Edit ~/.config/duskwatch/duskwatch.conf to set your schedule,"
echo "brightness levels, and per-display calibration."
echo "Then enable the timers/services you want, e.g.:"
echo "  systemctl --user enable --now duskwatch-brightness-schedule.timer"
echo "  systemctl --user enable --now duskwatch-config-apply.path"
echo "  systemctl --user enable --now duskwatch-fullscreen-brightness-watch.service"
echo "Two tray widget options are installed - pick one, not both:"
echo "  Plasmoid (recommended for now): add via your panel's 'Add Widgets'"
echo "  dialog. It will NOT dock inside the System Tray's grouped icons - KDE"
echo "  only does that for its own built-in tray items - so place it"
echo "  directly on a panel instead."
echo "  Standalone app: docks as a real grouped tray icon, but left-click to"
echo "  open doesn't reliably work on Plasma Wayland (known Qt/SNI gap) -"
echo "  use right-click -> Open Duskwatch instead. See README known limitations."
echo "  systemctl --user enable --now duskwatch-tray.service"
echo "  (requires PyQt6: 'pacman -S python-pyqt6' if not already installed)"

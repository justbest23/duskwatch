# Duskwatch

A Redshift/gammastep replacement for KDE Plasma 6 on Wayland, plus scheduled screen brightness and a fullscreen-aware inhibitor for games.

## Why this exists

On Wayland, clients can't set gamma tables directly, so Redshift/gammastep don't work at all. KDE's built-in **Night Color** (KWin's `NightLightManager`) is the only thing on the system that can actually shift color temperature — but it has gaps Duskwatch fills:

1. Nothing on Plasma schedules color temperature *and* brightness together the way Redshift did — Duskwatch's own scheduler (`schedule-brightness.sh` + `fade-temperature.sh`) fades both in sync, driven by KWin's `NightLight.preview()` D-Bus call since that's the only available color-temperature control on Wayland.
2. Night Color doesn't exempt fullscreen windows (games, video), so it keeps shifting color temperature under them — there's no built-in way to pause it automatically for a fullscreen app ([KDE wishlist bug 487304](https://bugs.kde.org/show_bug.cgi?id=487304)). Duskwatch's KWin script inhibits it for the duration.
3. Plasma has no scheduled *brightness* control at all for external monitors (only an ambient-light-sensor auto-brightness for laptop panels, and nothing over DDC/CI for desktop displays).

If you also have KDE's own Night Color enabled with its own schedule, the two can fight over color temperature between Duskwatch's periodic ticks — see Known limitations.

## Components

### `kwin-scripts/nightcolor-fullscreen-inhibit`

A KWin script that watches for fullscreen windows — both true fullscreen (`_NET_WM_STATE_FULLSCREEN`) and borderless-fullscreen (many game engines just show an undecorated window sized to the output without setting the fullscreen hint) — and calls KWin's `org.kde.KWin.NightLight` D-Bus `inhibit()`/`uninhibit()` methods accordingly, the same mechanism video players use to suppress Night Color during playback.

### `brightness/`

- `lib-config.sh` — shared config loader plus helpers for KDE's `org.kde.ScreenBrightness` D-Bus API (`org.kde.Solid.PowerManagement`, objects `/org/kde/ScreenBrightness/displayN`). This is the same interface System Settings and the hardware brightness keys use, and it transparently covers both real DDC/CI monitors and KWin's software-brightness fallback for displays where DDC/CI doesn't work at all — no need to shell out to `ddcutil` directly, and no bus numbers to configure.
- `fade-brightness.sh <percent> <seconds>` — smoothly fades every display to a target brightness, applying each display's `FLOOR_<display>`/`CEIL_<display>` calibration from `duskwatch.conf` so a shared percentage can look visually consistent across monitors with very different raw ranges.
- `fade-temperature.sh <kelvin> <seconds>` — the color-temperature half of the pair above, fading KWin Night Color's `preview()` temperature to a target over the same duration using the same `FADE_STYLE`/`FADE_STEP_MINUTES` timing, so brightness and color move together.
- `schedule-brightness.sh` — computes the correct brightness *and* color-temperature target from the current time of day and runs both fades together. Distinguishes an on-time trigger (does a slow fade, `FADE_DURATION`) from a catch-up trigger — e.g. the PC was off at 19:00 and logs in at 9am the next day, or you just edited the schedule to a time already in the past — where it snaps to the target in `SNAP_DURATION` instead of doing a slow fade hours after the fact.
- `fullscreen-brightness-watch.sh` — watches the `inhibited` property on `org.kde.KWin.NightLight` (set by the KWin script above) and snaps brightness to full while a fullscreen app is active, restoring the scheduled level when it isn't.

### `systemd/`

User-level systemd units wiring the above into your session:
- `duskwatch-brightness-schedule.timer` / `.service` — fires at the configured evening/morning times (edit the `OnCalendar=` lines), `Persistent=true` and `OnStartupSec=30` so a missed trigger (PC off, late login) still gets caught up correctly on next session start.
- `duskwatch-fullscreen-brightness-watch.service` — the long-running watcher daemon.

### `plasmoid/`

A native Plasma 6 tray applet, split into a quick popup and a Settings window so the everyday click stays uncluttered:

- **Quick popup** (click the tray icon) — just **On / Off / Schedule**. On and Off pin brightness *and* color temperature to `NORMAL_PCT`/`NORMAL_TEMP` or `DIMMED_PCT`/`DIMMED_TEMP` regardless of time of day, until you switch back to Schedule. This isn't just a shortcut: without a mode pinned, the periodic schedule timer re-applies the time-of-day target every few minutes, so a plain slider drag alone gets silently overwritten within minutes.
- **Settings…** (button in the popup, or right-click the icon → "Duskwatch Settings…") opens everything else:
  - **Brightness** / **Color temperature** sliders for live manual override — brightness applies instantly and stays put (via `set-brightness-live.sh`); color temperature live-previews via `NightLight.preview()`/`stopPreview()` the same way KDE's own Night Color KCM slider does, and reverts to the schedule when you close the window.
  - **Schedule** — Evening/Morning hours (spinboxes) each with their own Brightness and Color temperature sliders, so the schedule targets are set the same way as the live sliders above. Writes to `duskwatch.conf` via `set-config.sh`.
  - **Fade** dropdown — named presets (Instant, Smooth 20 min/1 hour, Stepped every 5/15 min) or a custom minutes field (decimals allowed, up to 12h). Smooth interpolates in 30 even steps; Stepped jumps in fewer, more noticeable increments spaced a chosen number of minutes apart — see `fade-brightness.sh`'s `FADE_STYLE`.
  - **Calibrate displays…** — opens a separate window listing every detected monitor with Floor/Ceiling sliders; dragging one live-previews on that single display (via `preview-raw.sh`, bypassing calibration so you're seeing the raw effect) and releasing commits `FLOOR_<display>`/`CEIL_<display>` to `duskwatch.conf`. Split out further since it's a one-time-per-monitor setup task, not a quick toggle.
  - **Edit configuration file…** — for anything not exposed above (fade catch-up window, display allowlist, etc).

Note: the tray icon does **not** dock inside the System Tray's grouped icons. KDE's system tray only auto-shows its own hardcoded set of "known" items (volume, battery, network, etc.) — a third-party `Plasma/Applet` package gets silently dropped from that list even with `X-Plasma-NotificationArea: true` set and `Plasmoid.status` forced to `ActiveStatus`. Add it via "Add Widgets" and place it directly on a panel instead. Recommended for now — see the tray-app note below.

### `tray-app/`

A standalone Python (PyQt6) tray app with the same quick-popup/Settings split as the Plasmoid, outside of Plasma's widget system — kept in sync with it. Because it registers as a real `StatusNotifierItem` (the same protocol Discord, Bluetooth, etc. use), it docks correctly inside the System Tray's grouped icons, unlike the Plasmoid. However left-click to open it doesn't reliably work on Plasma Wayland — use right-click → "Open Duskwatch" or "Settings…" instead (see Known limitations). Pick one or the other; running both gives you two icons.

## Requirements

- KDE Plasma 6 (6.3+, for `org.kde.ScreenBrightness`), Wayland session
- `kwriteconfig6`, `kpackagetool6`, `gdbus` (part of a standard Plasma 6 install)
- PyQt6 (`python-pyqt6` on Arch) for the standalone tray app — recommended, see the System Tray note above

## Install

```
./install.sh
```

This symlinks the KWin script into `~/.local/share/kwin/scripts/`, the systemd units into `~/.config/systemd/user/`, and copies the default config to `~/.config/duskwatch/duskwatch.conf` if it doesn't already exist — so edits in this repo (or to your config) take effect without reinstalling. It does **not** enable any systemd timers/services for you — see the printed instructions to opt in.

Edit `~/.config/duskwatch/duskwatch.conf` for your schedule, brightness/color-temperature levels, and per-display calibration.

## Known limitations

- KWin's Night Color inhibitor is cookie-based and, in testing, only the original calling connection could reliably release its own inhibit — if a script/process holding an inhibit dies uncleanly, Night Color can get stuck inhibited until you log out and back in.
- The `SetBrightness` OSD-suppression flag (`flags=1`) was found empirically, not from documentation — it could change in a future Plasma release.
- The Plasmoid does not dock inside the System Tray's grouped icons — see the note in the `plasmoid/` section above. Currently the recommended default despite that, because of the tray-app issue below.
- Real DDC/CI monitors can visibly ease into a new brightness over ~1-2s due to the monitor's own firmware, even though `SetBrightness` returns and the D-Bus `Brightness` property updates instantly (confirmed by polling it immediately after a call — no server-side ramping happens on Duskwatch's or KDE's end). Displays using KWin's software-brightness fallback apply changes instantly since there's no hardware round-trip. Nothing to fix here; it's how those monitors respond to a DDC brightness write.
- Scheduled color temperature is applied via `NightLight.preview()` since there's no persistent "set the temperature" D-Bus method - only ephemeral preview, the same call the live Settings slider uses. It holds until something else calls `stopPreview()` or previews again, which is enough to survive between Duskwatch's own periodic ticks, but two things can disturb it: closing the Settings window's live color slider calls `stopPreview()`, which can revert to KDE's own Night Color state until the next tick (up to a few minutes later, or instantly if you're in Day/Night mode - re-running `set-mode.sh` re-applies immediately); and if you *also* have KDE's own Night Color enabled with its own schedule, the two can fight over the temperature between ticks. If you want Duskwatch to fully own color temperature, turn off Night Color's own schedule in System Settings and let Duskwatch's schedule drive it instead.
- `tray-app/`'s left-click-to-open doesn't reliably work under Plasma Wayland: `QSystemTrayIcon.activated` (the `Trigger` reason Qt fires on left-click) often doesn't come through KDE's Wayland StatusNotifierItem backend — a known Qt/Wayland gap, not specific to this app. Right-click → "Open Duskwatch" is the guaranteed-working path; left-click is still wired up in case it fires on your setup. Testing process: added the icon to the panel, confirmed it placed inline in the tray as a real SNI icon, then found left-click did nothing and right-click only showed "Quit" — traced to the known `activated` signal gap and added the menu action as a working fallback.

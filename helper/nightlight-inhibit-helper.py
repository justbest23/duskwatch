#!/usr/bin/env python3
# nightlight-inhibit-helper.py
# D-Bus-activated helper that inhibits/uninhibits KWin Night Light on behalf
# of the nightcolor-fullscreen-inhibit KWin script.
#
# Why this exists: KWin's JS callDBus() marshals every JS number as int32
# (KDE bug 486024, fix MR plasma/kwin!5695 still unmerged as of 6.7.2), so a
# script can call uninhibit(uint cookie) but the call never dispatches -
# "Could not find slot NightLightAdaptor::uninhibit" - leaving the inhibit
# stuck until the compositor restarts. KWin also keys inhibit cookies to the
# caller's bus connection, so no other process can release them. Routing both
# calls through this helper gives them a real uint32 signature, and if the
# helper ever dies while inhibiting, KWin's service watcher releases the
# inhibit automatically instead of leaving it stuck.

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

BUS_NAME = "org.duskwatch.NightLightInhibit"
OBJECT_PATH = "/org/duskwatch/NightLightInhibit"

INTROSPECTION_XML = """
<node>
  <interface name="org.duskwatch.NightLightInhibit">
    <method name="SetInhibited">
      <arg type="b" name="inhibited" direction="in"/>
    </method>
  </interface>
</node>
"""

session_bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
cookie = None


def call_nightlight(method, params=None):
    return session_bus.call_sync(
        "org.kde.KWin", "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight",
        method, params, None, Gio.DBusCallFlags.NONE, 5000, None)


def set_inhibited(inhibited):
    global cookie
    if inhibited and cookie is None:
        cookie = call_nightlight("inhibit").unpack()[0]
    elif not inhibited and cookie is not None:
        try:
            call_nightlight("uninhibit", GLib.Variant("(u)", (cookie,)))
        finally:
            # A stale cookie (e.g. after a compositor restart) is a server-side
            # no-op; never let it wedge the helper in the inhibited state.
            cookie = None


def handle_method_call(connection, sender, path, interface, method, params, invocation):
    if method == "SetInhibited":
        try:
            set_inhibited(params.unpack()[0])
            invocation.return_value(None)
        except GLib.Error as e:
            invocation.return_dbus_error("org.duskwatch.NightLightInhibit.Error", str(e))
    else:
        invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)


node_info = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML)
session_bus.register_object(OBJECT_PATH, node_info.interfaces[0], handle_method_call, None, None)

loop = GLib.MainLoop()
Gio.bus_own_name_on_connection(session_bus, BUS_NAME, Gio.BusNameOwnerFlags.NONE,
                               None, lambda *a: loop.quit())
loop.run()

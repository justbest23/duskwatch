function isFullscreenLike(client) {
    if (!client) return false;
    if (client.desktopWindow || client.dock) return false;
    if (client.fullScreen) return true;
    if (!client.normalWindow) return false;
    // A maximized window is not the same thing as fullscreen, even if some
    // window rule strips its border - maximize and fullscreen are distinct
    // KWin states, so explicitly exclude maximized windows here rather than
    // relying on geometry/border alone to tell them apart.
    if (client.maximizeMode !== 0) return false;
    // Borderless fullscreen: undecorated normal window covering the whole output
    var output = client.output;
    if (!output) return false;
    var geo = client.frameGeometry;
    var screenGeo = output.geometry;
    return !client.decorationHasAlpha && client.noBorder &&
           geo.width === screenGeo.width && geo.height === screenGeo.height &&
           geo.x === screenGeo.x && geo.y === screenGeo.y;
}

// Inhibit/uninhibit is delegated to the duskwatch helper service instead of
// calling org.kde.KWin.NightLight directly: callDBus() marshals JS numbers as
// int32 (KDE bug 486024, fix unmerged), so uninhibit(uint cookie) can never
// dispatch from here and the inhibit gets stuck until the compositor
// restarts. Booleans marshal fine, and the helper is D-Bus activated, so this
// call also starts it on demand.
var inhibited = null; // null forces the initial state to be sent

function updateForClient(client) {
    var active = isFullscreenLike(client);
    if (active === inhibited) return;
    inhibited = active;
    callDBus("org.duskwatch.NightLightInhibit", "/org/duskwatch/NightLightInhibit",
        "org.duskwatch.NightLightInhibit", "SetInhibited", active);
}

function watch(client) {
    client.fullScreenChanged.connect(function() { updateForClient(workspace.activeWindow); });
    client.frameGeometryChanged.connect(function() { updateForClient(workspace.activeWindow); });
}

workspace.windowActivated.connect(updateForClient);
workspace.windowAdded.connect(watch);
workspace.windowList().forEach(watch);
updateForClient(workspace.activeWindow);
